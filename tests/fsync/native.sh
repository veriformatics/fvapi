#!/usr/bin/env bash
# Real Lean external objects, not a mock runtime; instrument the entire bridge with ASan + UBSan.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$root"
for tool in gcc lean; do
    command -v "$tool" >/dev/null || { printf 'fsync native: %s missing\n' "$tool" >&2; exit 1; }
done
prefix="$(lean --print-prefix)"
out="$(mktemp -d)"
trap 'rm -rf -- "$out"' EXIT
gcc -std=gnu11 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined \
    -fno-sanitize-recover=all -Wall -Wextra -Werror -pthread \
    -I "$prefix/include" -L "$prefix/lib/lean" -Wl,-rpath,"$prefix/lib/lean" \
    -o "$out/lifecycle" tests/fsync/lifecycle.c -lleanshared
ASAN_OPTIONS=detect_leaks=1:abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
    "$out/lifecycle" "$out/work"
