#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <lean/lean.h>

/* Policy stays in Lean; these five functions issue exactly one libc syscall each. */
typedef struct {
    ssize_t value;
    int error;
} fvapi_sys_result;

static fvapi_sys_result fvapi_open_file(const char *path, mode_t mode) {
    int value = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode);
    int error = value < 0 ? errno : 0;
    return (fvapi_sys_result){value, error};
}

static fvapi_sys_result fvapi_open_dir(const char *path) {
    int value = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    int error = value < 0 ? errno : 0;
    return (fvapi_sys_result){value, error};
}

static fvapi_sys_result fvapi_write(int fd, const uint8_t *bytes, size_t count) {
    ssize_t value = write(fd, bytes, count);
    int error = value < 0 ? errno : 0;
    return (fvapi_sys_result){value, error};
}

static fvapi_sys_result fvapi_sync(int fd) {
    int value = fsync(fd);
    int error = value < 0 ? errno : 0;
    return (fvapi_sys_result){value, error};
}

static fvapi_sys_result fvapi_close(int fd) {
    int value = close(fd);
    int error = value < 0 ? errno : 0;
    return (fvapi_sys_result){value, error};
}

static lean_obj_res fvapi_response(fvapi_sys_result response) {
    lean_object *result = lean_alloc_ctor(response.value < 0 ? 0 : 1, 1, 0);
    lean_ctor_set(result, 0, lean_usize_to_nat(response.value < 0 ?
        (size_t)response.error : (size_t)response.value));
    return lean_io_result_mk_ok(result);
}

LEAN_EXPORT lean_obj_res fvapi_fsync_open_file(b_lean_obj_arg path, uint32_t mode) {
    return fvapi_response(fvapi_open_file(lean_string_cstr(path), (mode_t)mode));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_open_dir(b_lean_obj_arg path) {
    return fvapi_response(fvapi_open_dir(lean_string_cstr(path)));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_write(uint32_t fd, b_lean_obj_arg bytes,
                                          size_t offset, size_t count) {
    size_t size = lean_sarray_size(bytes);
    if (offset > size || count > size - offset)
        return fvapi_response((fvapi_sys_result){-1, EINVAL});
    return fvapi_response(fvapi_write((int)fd, lean_sarray_cptr(bytes) + offset, count));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_sync(uint32_t fd) {
    return fvapi_response(fvapi_sync((int)fd));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_close(uint32_t fd) {
    return fvapi_response(fvapi_close((int)fd));
}

/* The guard covers the Lean policy's complete operation, not each individual syscall. */
typedef struct {
    pthread_mutex_t guard;
    int fd;
    bool closed;
    char *path;
} fvapi_writer;

static void fvapi_guard_check(int result) {
    if (result != 0) {
        lean_internal_panic("fvapi fsync: native writer guard failed");
        abort();
    }
}

static void fvapi_writer_finalize(void *data) {
    fvapi_writer *writer = data;
    fvapi_guard_check(pthread_mutex_lock(&writer->guard));
    if (!writer->closed) {
        writer->closed = true;
        (void)fvapi_close(writer->fd);
    }
    fvapi_guard_check(pthread_mutex_unlock(&writer->guard));
    fvapi_guard_check(pthread_mutex_destroy(&writer->guard));
    free(writer->path);
    free(writer);
}

static void fvapi_writer_foreach(void *data, b_lean_obj_arg visitor) {
    (void)data;
    (void)visitor;
}

static lean_external_class *fvapi_writer_class;
static pthread_once_t fvapi_writer_once = PTHREAD_ONCE_INIT;

static void fvapi_register_writer(void) {
    fvapi_writer_class = lean_register_external_class(fvapi_writer_finalize, fvapi_writer_foreach);
}

LEAN_EXPORT lean_obj_res fvapi_fsync_writer_new(uint32_t fd, b_lean_obj_arg path) {
    fvapi_guard_check(pthread_once(&fvapi_writer_once, fvapi_register_writer));
    fvapi_writer *writer = malloc(sizeof(*writer));
    if (writer == NULL) {
        (void)fvapi_close((int)fd);
        lean_internal_panic("fvapi fsync: native writer allocation failed");
        abort();
    }
    writer->path = strdup(lean_string_cstr(path));
    if (writer->path == NULL) {
        free(writer);
        (void)fvapi_close((int)fd);
        lean_internal_panic("fvapi fsync: native writer path allocation failed");
        abort();
    }
    writer->fd = (int)fd;
    writer->closed = false;
    fvapi_guard_check(pthread_mutex_init(&writer->guard, NULL));
    return lean_io_result_mk_ok(lean_alloc_external(fvapi_writer_class, writer));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_writer_acquire(b_lean_obj_arg object) {
    fvapi_writer *writer = lean_get_external_data(object);
    fvapi_guard_check(pthread_mutex_lock(&writer->guard));
    lean_object *snapshot = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(snapshot, 0, lean_box((size_t)writer->fd));
    lean_ctor_set(snapshot, 1, lean_box(writer->closed));
    return lean_io_result_mk_ok(snapshot);
}

LEAN_EXPORT lean_obj_res fvapi_fsync_writer_mark_closed(b_lean_obj_arg object) {
    fvapi_writer *writer = lean_get_external_data(object);
    writer->closed = true;
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res fvapi_fsync_writer_release(b_lean_obj_arg object) {
    fvapi_writer *writer = lean_get_external_data(object);
    fvapi_guard_check(pthread_mutex_unlock(&writer->guard));
    return lean_io_result_mk_ok(lean_box(0));
}
