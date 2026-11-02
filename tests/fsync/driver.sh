#!/usr/bin/env bash
# Package-boundary control on the gate workspace's actual filesystem.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$root"
bin="$root/.lake/build/bin/fvapi"
[[ -x "$bin" ]] || { printf 'fsync driver: binary missing\n' >&2; exit 1; }
out="$(mktemp -d "$root/.lake/fsync-driver.XXXXXX")"
trap 'rm -rf -- "$out"' EXIT
fail() { printf 'fsync driver: %s\n' "$1" >&2; exit 1; }
printf 'a\0b\377' >"$out/input"
"$bin" dev fsync run create "$out/file" 600 write 4 sync close close write 0 sync drop \
    syncdir "$out" <"$out/input" >"$out/result"
cmp "$out/input" "$out/file" || fail 'exact bytes differ'
jq -se 'length == 9 and .[0].ok and .[1].ok and .[2].ok and .[3].ok and
    (.[4].error == {op:"close",cause:"alreadyClosed"}) and
    (.[5].error == {op:"write",cause:"alreadyClosed"}) and
    (.[6].error == {op:"sync",cause:"alreadyClosed"}) and .[7].ok and .[8].ok' \
    "$out/result" >/dev/null || fail 'success/closed/error record mismatch'
"$bin" dev fsync run create "$out/file" create "$out/second" write 0 drop \
    >"$out/result"
jq -se 'length == 4 and .[0].error.cause == "errno" and .[0].error.errno == 17 and
    .[1].ok and .[2].ok and .[3].ok' "$out/result" >/dev/null || fail 'create/drop lifecycle'
for bad in '' 'write -1' 'write +1' 'sync' 'drop' 'create'; do
    read -ra args <<<"$bad"
    rc=0
    "$bin" dev fsync run "${args[@]}" >"$out/result" 2>"$out/error" || rc=$?
    [[ "$rc" == 2 ]] || fail "usage rc $rc ($bad)"
done
rc=0
"$bin" dev fsync run create "$out/third" 0777 >"$out/result" 2>"$out/error" || rc=$?
[[ "$rc" == 2 ]] || fail 'invalid mode accepted'
rc=0
"$bin" dev fsync run create "$out/short" write 2 < /dev/null \
    >"$out/result" 2>"$out/error" || rc=$?
[[ "$rc" == 2 ]] || fail 'short stdin accepted'
printf 'fsync driver: workspace create/write/sync/close/syncdir + usage PASS\n'
