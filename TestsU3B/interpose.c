#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Only the test root + descriptors opened from it participate; runtime/output IO is untouched.
 * Control IO uses raw syscalls, outside the intercepted stream. close faults release the fd
 * before reporting errno, matching Linux rather than POSIX's portable EINTR ambiguity. */
enum { CAP_FD = 65536, CAP_RULE = 512 };
struct rule { char op[16], kind[16]; long value, left; };
static struct rule rules[CAP_RULE];
static size_t nrules;
static unsigned char owned[CAP_FD]; /* 1=file, 2=directory, 3=reused poison */
static char root[4096], control[4096], poison[4096];
static int logfd = -1, ready, reuse_fd;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t logmu = PTHREAD_MUTEX_INITIALIZER;
static int (*real_open)(const char *, int, ...);
static int (*real_open64)(const char *, int, ...);
static int (*real_openat)(int, const char *, int, ...);
static ssize_t (*real_write)(int, const void *, size_t);
static int (*real_fsync)(int);
static int (*real_close)(int);

static void fail_setup(const char *message) {
  (void)syscall(SYS_write, STDERR_FILENO, message, strlen(message));
  _exit(122);
}

__attribute__((constructor)) static void initialize(void) {
  real_open = dlsym(RTLD_NEXT, "open");
  real_open64 = dlsym(RTLD_NEXT, "open64");
  real_openat = dlsym(RTLD_NEXT, "openat");
  real_write = dlsym(RTLD_NEXT, "write");
  real_fsync = dlsym(RTLD_NEXT, "fsync");
  real_close = dlsym(RTLD_NEXT, "close");
  const char *r = getenv("U3B_ROOT"), *s = getenv("U3B_SCRIPT"), *l = getenv("U3B_TRACE");
  const char *c = getenv("U3B_CONTROL");
  if (!r || !s || !l || !real_open || !real_open64 || !real_openat || !real_write || !real_fsync || !real_close)
    fail_setup("interposer setup: missing environment/symbol\n");
  if (strlen(r) >= sizeof root || (c && strlen(c) >= sizeof control))
    fail_setup("interposer setup: path too long\n");
  strcpy(root, r);
  if (c) strcpy(control, c);
  reuse_fd = getenv("U3B_REUSE") != NULL;
  if (snprintf(poison, sizeof poison, "%s/poison", control) >= (int)sizeof poison)
    fail_setup("interposer setup: poison path too long\n");
  logfd = (int)syscall(SYS_openat, AT_FDCWD, l, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  int fd = (int)syscall(SYS_openat, AT_FDCWD, s, O_RDONLY | O_CLOEXEC, 0);
  if (logfd < 0 || fd < 0) fail_setup("interposer setup: open script/trace\n");
  char script[65536];
  ssize_t n = syscall(SYS_read, fd, script, sizeof script - 1);
  (void)syscall(SYS_close, fd);
  if (n < 0 || n == (ssize_t)sizeof script - 1) fail_setup("interposer setup: script size\n");
  script[n] = 0;
  char *save = NULL;
  for (char *line = strtok_r(script, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
    if (*line == '#') continue;
    if (nrules == CAP_RULE) fail_setup("interposer setup: too many rules\n");
    struct rule *rule = &rules[nrules++];
    if (sscanf(line, "%15s %15s %ld %ld", rule->op, rule->kind, &rule->value, &rule->left) != 4 || rule->left < 1)
      fail_setup("interposer setup: bad rule\n");
  }
  ready = 1;
}

static bool in_root(const char *path) {
  size_t n = strlen(root);
  return strncmp(path, root, n) == 0 && (path[n] == 0 || path[n] == '/');
}

static bool owned_path(int dirfd, const char *path) {
  if (path[0] == '/') return in_root(path);
  if (dirfd >= 0 && dirfd < CAP_FD && owned[dirfd] == 2) return true;
  if (dirfd != AT_FDCWD) return false;
  char full[8192], cwd[4096];
  if (syscall(SYS_getcwd, cwd, sizeof cwd) < 0) return false;
  if (snprintf(full, sizeof full, "%s/%s", cwd, path) >= (int)sizeof full) return false;
  return in_root(full);
}

static struct rule action(const char *op) {
  struct rule result = { .kind = "pass", .left = 1 };
  pthread_mutex_lock(&mu);
  for (size_t i = 0; i < nrules; ++i) {
    if (rules[i].left && strcmp(rules[i].op, op) == 0) {
      result = rules[i];
      rules[i].left--;
      break;
    }
  }
  pthread_mutex_unlock(&mu);
  return result;
}

static void record(const char *op, int fd, size_t count, long result, int err,
                   int flags, mode_t mode, const char *phase, bool reused) {
  char line[512];
  int n = snprintf(line, sizeof line,
    "{\"op\":\"%s\",\"fd\":%d,\"count\":%zu,\"ret\":%ld,\"errno\":%d,"
    "\"flags\":%d,\"mode\":%u,\"phase\":\"%s\",\"reused\":%s}\n",
    op, fd, count, result, err, flags, (unsigned)mode, phase, reused ? "true" : "false");
  if (n < 0 || n >= (int)sizeof line) fail_setup("interposer setup: trace format\n");
  pthread_mutex_lock(&logmu);
  if (syscall(SYS_write, logfd, line, (size_t)n) != n) fail_setup("interposer setup: trace write\n");
  pthread_mutex_unlock(&logmu);
}

static void block_call(const char *op, int fd, size_t count, bool reused) {
  record(op, fd, count, 0, 0, 0, 0, "blocked", reused);
  char entered[8192], fifo[8192];
  if (!*control || snprintf(entered, sizeof entered, "%s/entered", control) >= (int)sizeof entered ||
      snprintf(fifo, sizeof fifo, "%s/release", control) >= (int)sizeof fifo)
    fail_setup("interposer setup: block control\n");
  int marker = (int)syscall(SYS_openat, AT_FDCWD, entered, O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
  if (marker < 0) fail_setup("interposer setup: entered marker\n");
  (void)syscall(SYS_close, marker);
  int gate = (int)syscall(SYS_openat, AT_FDCWD, fifo, O_RDONLY | O_CLOEXEC, 0);
  char byte;
  if (gate < 0 || syscall(SYS_read, gate, &byte, 1) != 1) fail_setup("interposer setup: block release\n");
  (void)syscall(SYS_close, gate);
}

static int do_open(int dirfd, const char *path, int flags, mode_t mode, int variant) {
  if (!ready) return (int)syscall(SYS_openat, dirfd, path, flags, mode);
  bool track = owned_path(dirfd, path);
  const char *op = (flags & O_DIRECTORY) ? "openDir" : "create";
  struct rule rule = track ? action(op) : (struct rule){ .kind = "pass" };
  int result;
  if (strcmp(rule.kind, "errno") == 0) {
    errno = (int)rule.value;
    result = -1;
  } else {
    result = variant == 2 ? real_openat(dirfd, path, flags, mode) :
             variant == 1 ? real_open64(path, flags, mode) : real_open(path, flags, mode);
  }
  int err = result < 0 ? errno : 0;
  if (track) {
    if (result >= CAP_FD) fail_setup("interposer setup: descriptor cap\n");
    if (result >= 0) {
      pthread_mutex_lock(&mu);
      owned[result] = (flags & O_DIRECTORY) ? 2 : 1;
      pthread_mutex_unlock(&mu);
    }
    record(op, result, 0, result, err, flags, mode, "return", false);
  }
  errno = err;
  return result;
}

int open(const char *path, int flags, ...) {
  mode_t mode = 0;
  if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
  return do_open(AT_FDCWD, path, flags, mode, 0);
}
int __open_2(const char *path, int flags) { return do_open(AT_FDCWD, path, flags, 0, 0); }
int open64(const char *path, int flags, ...) {
  mode_t mode = 0;
  if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
  return do_open(AT_FDCWD, path, flags, mode, 1);
}
int openat(int dirfd, const char *path, int flags, ...) {
  mode_t mode = 0;
  if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
  return do_open(dirfd, path, flags, mode, 2);
}

static int kind_of(int fd) {
  if (!ready || fd < 0 || fd >= CAP_FD) return 0;
  pthread_mutex_lock(&mu);
  int kind = owned[fd];
  pthread_mutex_unlock(&mu);
  return kind;
}

ssize_t write(int fd, const void *buffer, size_t count) {
  int kind = kind_of(fd);
  if (!kind) return ready ? real_write(fd, buffer, count) : syscall(SYS_write, fd, buffer, count);
  const char *op = "write";
  struct rule rule = action(op);
  if (strcmp(rule.kind, "block") == 0) block_call(op, fd, count, kind == 3);
  ssize_t result;
  if (strcmp(rule.kind, "errno") == 0) { errno = (int)rule.value; result = -1; }
  else if (strcmp(rule.kind, "zero") == 0) result = 0;
  else if (strcmp(rule.kind, "ack") == 0) result = (ssize_t)count;
  else result = real_write(fd, buffer, strcmp(rule.kind, "short") == 0 && rule.value >= 0 && (size_t)rule.value < count ? (size_t)rule.value : count);
  int err = result < 0 ? errno : 0;
  record(op, fd, count, result, err, 0, 0, "return", kind == 3);
  errno = err;
  return result;
}

int fsync(int fd) {
  int kind = kind_of(fd);
  if (!kind) return ready ? real_fsync(fd) : (int)syscall(SYS_fsync, fd);
  const char *op = kind == 2 ? "syncDir" : "sync";
  struct rule rule = action(op);
  if (strcmp(rule.kind, "block") == 0) block_call(op, fd, 0, kind == 3);
  int result;
  if (strcmp(rule.kind, "errno") == 0) { errno = (int)rule.value; result = -1; }
  else result = real_fsync(fd);
  int err = result < 0 ? errno : 0;
  record(op, fd, 0, result, err, 0, 0, "return", kind == 3);
  errno = err;
  return result;
}

int close(int fd) {
  int kind = kind_of(fd);
  if (!kind) return ready ? real_close(fd) : (int)syscall(SYS_close, fd);
  const char *op = kind == 2 ? "closeDir" : "close";
  struct rule rule = action(op);
  int result = real_close(fd);
  int err = result < 0 ? errno : 0;
  pthread_mutex_lock(&mu);
  owned[fd] = 0;
  if (reuse_fd && kind != 3) {
    int replacement = (int)syscall(SYS_openat, AT_FDCWD, poison, O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
    if (replacement < 0) fail_setup("interposer setup: poison open\n");
    if (replacement != fd) {
      if (syscall(SYS_dup3, replacement, fd, O_CLOEXEC) < 0) fail_setup("interposer setup: poison dup\n");
      (void)syscall(SYS_close, replacement);
    }
    owned[fd] = 3;
  }
  pthread_mutex_unlock(&mu);
  if (strcmp(rule.kind, "errno") == 0) { result = -1; err = (int)rule.value; }
  record(op, fd, 0, result, err, 0, 0, "return", kind == 3);
  errno = err;
  return result;
}
