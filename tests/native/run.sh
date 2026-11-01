#!/usr/bin/env bash
# Gate stage `native`: builds tests/native/sha256_core.c with c/fvapi_sha256_core.c + HACL*'s C
# under ASan + UBSan (gcc; the toolchain's clang ships no sanitizer runtime) with small chunk
# ceilings, then runs it; any sanitizer report or digest mismatch fails (U3 contract S5).
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$root"
if ! command -v gcc >/dev/null; then
    printf 'native: gcc missing (tools/bootstrap-vflab.sh installs it)\n' >&2
    exit 1
fi
out="$(mktemp -d)"
trap 'rm -rf -- "$out"' EXIT
hacl=vendor/hacl-star/dist
gcc -std=gnu11 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined \
    -fno-sanitize-recover=all -Wall -Wextra -Werror \
    -DFVAPI_SHA256_ONESHOT_MAX=100 -DFVAPI_SHA256_CHUNK=128 \
    -I c -I "$hacl/gcc-compatible" -I "$hacl/karamel/include" \
    -I "$hacl/karamel/krmllib/dist/minimal" \
    -o "$out/sha256-core" tests/native/sha256_core.c c/fvapi_sha256_core.c \
    "$hacl/gcc-compatible/Hacl_Hash_SHA2.c"
ASAN_OPTIONS=detect_leaks=1:abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
    "$out/sha256-core"
