#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int __open_2(const char *, int);

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int fd;
  if (strcmp(argv[1], "directory") == 0)
    fd = open(argv[2], O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  else if (strcmp(argv[1], "open") == 0)
    fd = open(argv[2], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0640);
  else if (strcmp(argv[1], "open64") == 0)
    fd = open64(argv[2], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0640);
  else if (strcmp(argv[1], "openat") == 0)
    fd = openat(AT_FDCWD, argv[2], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0640);
  else if (strcmp(argv[1], "__open_2") == 0)
    fd = __open_2(argv[2], O_WRONLY | O_CLOEXEC | O_NOFOLLOW);
  else return 2;
  int oe = fd < 0 ? errno : 0;
  ssize_t w = -2;
  int we = 0, s = -2, se = 0, c = -2, ce = 0;
  if (fd >= 0) {
    if (strcmp(argv[1], "directory") != 0) {
      w = write(fd, "abc", 3); we = w < 0 ? errno : 0;
    }
    s = fsync(fd); se = s < 0 ? errno : 0;
    c = close(fd); ce = c < 0 ? errno : 0;
  }
  printf("{\"open\":%d,\"open_errno\":%d,\"write\":%zd,\"write_errno\":%d,"
         "\"sync\":%d,\"sync_errno\":%d,\"close\":%d,\"close_errno\":%d}\n",
         fd, oe, w, we, s, se, c, ce);
  return 0;
}
