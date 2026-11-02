#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Test the race observer itself: same script, guarded control + deliberately unguarded close. */
static pthread_mutex_t guard = PTHREAD_MUTEX_INITIALIZER;
static int fd, unguarded;
static const char *mode, *control;

static void marker(const char *name) {
  char path[8192];
  if (snprintf(path, sizeof path, "%s/%s", control, name) >= (int)sizeof path) _exit(2);
  int file = open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
  if (file < 0 || close(file) != 0) _exit(2);
}

static void *first(void *unused) {
  (void)unused;
  pthread_mutex_lock(&guard);
  if (strcmp(mode, "write") == 0) {
    if (write(fd, "abc", 3) < 0 && !unguarded) _exit(2);
  } else if (fsync(fd) < 0 && !unguarded) _exit(2);
  pthread_mutex_unlock(&guard);
  return NULL;
}

static void *second(void *unused) {
  (void)unused;
  marker("close-started");
  if (!unguarded) pthread_mutex_lock(&guard);
  (void)close(fd);
  if (!unguarded) pthread_mutex_unlock(&guard);
  marker("close-done");
  return NULL;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  mode = argv[1];
  control = argv[3];
  unguarded = getenv("U3B_PROBE_UNGUARDED") != NULL;
  fd = open(argv[2], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0644);
  if (fd < 0) return 2;
  pthread_t a, b;
  if (pthread_create(&a, NULL, first, NULL) != 0) return 2;
  char entered[8192];
  if (snprintf(entered, sizeof entered, "%s/entered", control) >= (int)sizeof entered) return 2;
  bool found = false;
  for (int i = 0; i < 10000; ++i) {
    if (access(entered, F_OK) == 0) { found = true; break; }
    usleep(1000);
  }
  if (!found || pthread_create(&b, NULL, second, NULL) != 0) return 2;
  pthread_join(a, NULL);
  pthread_join(b, NULL);
  printf("{\"ok\":true,\"mode\":\"%s\"}\n", mode);
  return 0;
}
