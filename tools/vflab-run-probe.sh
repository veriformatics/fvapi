#!/usr/bin/env bash
# Probes tools/vflab-run itself from the desktop (contract U1 R1, R5): the command's exit status
# comes back unchanged; a command ended by a signal, an OOM kill or the timeout never exits 0;
# arguments stay literal; the remote workspace path maps back to this worktree on both streams.
# Prints PROBE lines; exit status = probes that failed.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/tools/vflab-run"
missed=0

# check NAME DETAIL TEST… — TEST (a `test` expression) must hold.
check() {
    local name="$1" detail="$2"
    shift 2
    if "$@"; then
        printf 'PROBE %s: held (%s)\n' "$name" "$detail"
    else
        printf 'PROBE %s: FAILED (%s)\n' "$name" "$detail"
        missed=$((missed + 1))
    fi
}

"$run" bash -c 'exit 7' >/dev/null 2>&1
rc=$?
check exit-status "rc $rc, want 7" test "$rc" -eq 7

for sig in HUP INT TERM PIPE KILL; do
    "$run" bash -c "kill -$sig \$\$" >/dev/null 2>&1
    rc=$?
    check "signal-$sig" "rc $rc, want nonzero" test "$rc" -ne 0
done

FVAPI_VFLAB_MEMORY=64M "$run" python3 -I -c 'b = bytearray(512 * 1024 * 1024)' >/dev/null 2>&1
rc=$?
check oom "rc $rc, want nonzero" test "$rc" -ne 0

FVAPI_VFLAB_TIMEOUT=2 "$run" sleep 30 >/dev/null 2>&1
rc=$?
check timeout "rc $rc, want nonzero" test "$rc" -ne 0

# shellcheck disable=SC2016
literal='$HOME $$'
out="$("$run" printf '%s' "$literal" 2>/dev/null)"
check literal-argv "output \"$out\"" test "$out" = "$literal"

out="$("$run" pwd 2>/dev/null)"
check path-map-stdout "output \"$out\"" test "$out" = "$root"

out="$("$run" bash -c 'pwd >&2' 2>&1 >/dev/null)"
check path-map-stderr "output \"$out\"" test "$out" = "$root"

# Workspace = exactly the worktree's file set: a deleted file disappears, an ignored file never
# uploads, executable bits + symlinks survive.
printf 'stale\n' >"$root/probe-stale.txt"
"$run" test -e probe-stale.txt >/dev/null 2>&1
rc=$?
rm -f "$root/probe-stale.txt"
"$run" test ! -e probe-stale.txt >/dev/null 2>&1
rc2=$?
check deleted-file "present rc $rc, after deletion rc $rc2" test "$rc$rc2" = 00
mkdir -p "$root/.scratch"
printf 'canary\n' >"$root/.scratch/probe-canary"
"$run" test ! -e .scratch/probe-canary >/dev/null 2>&1
rc=$?
rm -f "$root/.scratch/probe-canary"
check ignored-file "rc $rc, want 0 (absent remotely)" test "$rc" -eq 0
# The gate's step ledger (.gate/) outlives the reset, like the caches.
"$run" bash -c 'mkdir -p .gate && printf kept >.gate/probe-kept' >/dev/null 2>&1
"$run" test -e .gate/probe-kept >/dev/null 2>&1
rc=$?
"$run" rm -f .gate/probe-kept >/dev/null 2>&1
check ledger-kept "rc $rc, want 0 (kept across runs)" test "$rc" -eq 0
printf '#!/bin/sh\n' >"$root/probe-exec.sh"
chmod +x "$root/probe-exec.sh"
ln -s probe-exec.sh "$root/probe-link"
"$run" bash -c 'test -x probe-exec.sh && test -L probe-link' >/dev/null 2>&1
rc=$?
rm -f "$root/probe-exec.sh" "$root/probe-link"
check exec-bit-symlink "rc $rc, want 0" test "$rc" -eq 0

# Runs of one worktree serialize: two 3 s runs take ≥ 6 s together.
start=$SECONDS
"$run" sleep 3 >/dev/null 2>&1 &
p1=$!
"$run" sleep 3 >/dev/null 2>&1 &
p2=$!
wait "$p1"
r1=$?
wait "$p2"
r2=$?
took=$((SECONDS - start))
check same-worktree-serial "rcs $r1 $r2, ${took}s, want 0 0 + ≥ 6 s" test "$r1$r2" = 00 -a "$took" -ge 6

# A linked worktree gets its own workspace (its path maps back to it).
wt="$(mktemp -d)/probe-wt"
git -C "$root" worktree add -q --detach "$wt" HEAD
mkdir -p "$wt/tools"
cp "$run" "$wt/tools/vflab-run"
out="$("$wt/tools/vflab-run" pwd 2>/dev/null)"
rc=$?
wt_id="probe-wt-$(printf '%s' "$wt" | sha256sum | cut -c1-8)"
ssh -o BatchMode=yes "${FVAPI_VFLAB:-vflab}" "rm -rf ~/gate/ws/$wt_id ~/gate/ws/$wt_id.origin ~/gate/ws/$wt_id.lock
    git -C ~/gate/repo.git update-ref -d refs/heads/ws/$wt_id"
git -C "$root" worktree remove --force "$wt"
check linked-worktree "rc $rc, output \"$out\"" test "$rc" -eq 0 -a "$out" = "$wt"

# A workspace recorded for another path is refused (exit 125), then restored.
id="$(basename -- "$root" | tr -c 'A-Za-z0-9._\n-' _)-$(printf '%s' "$root" | sha256sum | cut -c1-8)"
host="${FVAPI_VFLAB:-vflab}"
ssh -o BatchMode=yes "$host" "printf '/elsewhere\n' >~/gate/ws/$id.origin"
"$run" true >/dev/null 2>&1
rc=$?
ssh -o BatchMode=yes "$host" "printf '%s\n' '$root' >~/gate/ws/$id.origin"
check origin-collision "rc $rc, want 125" test "$rc" -eq 125

# A failing output filter never yields green: a `sed` that exits 1 → 125.
fake="$(mktemp -d)"
printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$fake/sed"
chmod +x "$fake/sed"
PATH="$fake:$PATH" "$run" true >/dev/null 2>&1
rc=$?
rm -rf "$fake"
check filter-failure "rc $rc, want 125" test "$rc" -eq 125

printf 'vflab-run-probe: %d probe(s) failed\n' "$missed"
exit "$missed"
