#include "../../c/fvapi_fsync.c"
#include <stdio.h>
#include <sys/stat.h>

extern void lean_initialize_runtime_module(void);
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);

#define CHECK(condition, message) do { \
    if (!(condition)) { \
        fprintf(stderr, "fsync lifecycle: %s\n", message); \
        exit(1); \
    } \
} while (0)

static lean_object *unwrap(lean_object *io) {
    CHECK(lean_io_result_is_ok(io), "unexpected IO exception");
    lean_object *value = lean_io_result_get_value(io);
    lean_inc(value);
    lean_dec(io);
    return value;
}

static lean_object *new_writer(int fd, const char *path) {
    lean_object *name = lean_mk_string(path);
    lean_object *object = unwrap(fvapi_fsync_writer_new((uint32_t)fd, name));
    lean_dec(name);
    return object;
}

static bool acquire_writer(lean_object *object) {
    lean_object *snapshot = unwrap(fvapi_fsync_writer_acquire(object));
    bool closed = lean_unbox(lean_ctor_get(snapshot, 1));
    lean_dec(snapshot);
    return closed;
}

static void release_writer(lean_object *object) {
    lean_dec(unwrap(fvapi_fsync_writer_release(object)));
}

static void mark_closed(lean_object *object) {
    lean_dec(unwrap(fvapi_fsync_writer_mark_closed(object)));
}

static int reopen_at(int fd) {
    int replacement = open("/dev/null", O_WRONLY | O_CLOEXEC);
    CHECK(replacement >= 0, "replacement open failed");
    if (replacement != fd) {
        CHECK(dup2(replacement, fd) == fd, "replacement dup2 failed");
        CHECK(close(replacement) == 0, "replacement cleanup failed");
    }
    return fd;
}

typedef struct {
    lean_object *object;
    pthread_mutex_t status;
    pthread_cond_t changed;
    bool started;
    bool closed;
} close_job;

static void *close_task(void *data) {
    close_job *job = data;
    lean_initialize_thread();
    CHECK(pthread_mutex_lock(&job->status) == 0, "status lock failed");
    job->started = true;
    CHECK(pthread_cond_signal(&job->changed) == 0, "status signal failed");
    CHECK(pthread_mutex_unlock(&job->status) == 0, "status unlock failed");
    CHECK(!acquire_writer(job->object), "concurrent close observed early close");
    fvapi_writer *writer = lean_get_external_data(job->object);
    mark_closed(job->object);
    CHECK(fvapi_close(writer->fd).value == 0, "concurrent close failed");
    release_writer(job->object);
    job->closed = true;
    lean_finalize_thread();
    return NULL;
}

int main(int argc, char **argv) {
    lean_initialize_runtime_module();
    CHECK(argc == 2, "workspace argument missing");
    const char *directory = argv[1];
    CHECK(mkdir(directory, 0700) == 0, "workspace creation failed");
    char path[256];
    CHECK(snprintf(path, sizeof(path), "%s/file", directory) > 0, "path failed");
    mode_t mask = umask(0);
    fvapi_sys_result opened = fvapi_open_file(path, 0600);
    umask(mask);
    CHECK(opened.value >= 0, "create failed");
    int fd = (int)opened.value;
    CHECK((fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0, "create lacks CLOEXEC");
    CHECK((fcntl(fd, F_GETFL) & O_ACCMODE) == O_WRONLY, "create is not write-only");
    struct stat statbuf;
    CHECK(fstat(fd, &statbuf) == 0 && (statbuf.st_mode & 0777) == 0600, "mode changed");
    CHECK(fvapi_open_file(path, 0600).error == EEXIST, "create did not exclude existing file");
    uint8_t bytes[] = {0, 1, 127, 255};
    CHECK(fvapi_write(fd, bytes, sizeof(bytes)).value == 4, "write failed");
    CHECK(fvapi_sync(fd).value == 0, "sync failed");
    lean_object *object = new_writer(fd, path);
    lean_inc(object);
    lean_dec(object);
    CHECK(fcntl(fd, F_GETFD) >= 0, "nonlast reference finalized writer");
    lean_dec(object);
    CHECK(fcntl(fd, F_GETFD) < 0 && errno == EBADF, "last reference did not close writer");

    fd = open(path, O_WRONLY | O_CLOEXEC);
    CHECK(fd >= 0, "reopen failed");
    object = new_writer(fd, path);
    CHECK(!acquire_writer(object), "new writer is closed");
    mark_closed(object);
    CHECK(fvapi_close(fd).value == 0, "explicit close failed");
    release_writer(object);
    reopen_at(fd);
    CHECK(acquire_writer(object), "explicit close did not persist closed flag");
    release_writer(object);
    lean_dec(object);
    CHECK(fcntl(fd, F_GETFD) >= 0, "finalizer closed a reused descriptor");
    CHECK(close(fd) == 0, "reused descriptor cleanup failed");

    fd = open(path, O_WRONLY | O_CLOEXEC);
    CHECK(fd >= 0, "concurrency reopen failed");
    object = new_writer(fd, path);
    lean_mark_mt(object);
    CHECK(!acquire_writer(object), "open writer is closed");
    fvapi_writer *writer = lean_get_external_data(object);
    CHECK(pthread_mutex_trylock(&writer->guard) == EBUSY, "writer guard not held");
    close_job job = {object, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, false, false};
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, close_task, &job) == 0, "thread start failed");
    CHECK(pthread_mutex_lock(&job.status) == 0, "main status lock failed");
    while (!job.started) CHECK(pthread_cond_wait(&job.changed, &job.status) == 0, "wait failed");
    CHECK(pthread_mutex_unlock(&job.status) == 0, "main status unlock failed");
    CHECK(fvapi_write(fd, bytes, sizeof(bytes)).value == 4, "guarded write lost descriptor");
    release_writer(object);
    CHECK(pthread_join(thread, NULL) == 0 && job.closed, "concurrent close did not finish");
    reopen_at(fd);
    lean_dec(object);
    CHECK(fcntl(fd, F_GETFD) >= 0, "concurrent finalizer closed reused descriptor");
    CHECK(close(fd) == 0, "concurrent replacement cleanup failed");
    CHECK(pthread_mutex_destroy(&job.status) == 0, "status destroy failed");
    CHECK(pthread_cond_destroy(&job.changed) == 0, "condition destroy failed");

    opened = fvapi_open_dir(directory);
    CHECK(opened.value >= 0, "directory open failed");
    CHECK(fvapi_sync((int)opened.value).value == 0, "directory sync failed");
    CHECK(fvapi_close((int)opened.value).value == 0, "directory close failed");
    CHECK(unlink(path) == 0 && rmdir(directory) == 0, "filesystem cleanup failed");
    puts("fsync lifecycle: flags, last-reference finalizer, close-once, guard, reuse PASS");
    return 0;
}
