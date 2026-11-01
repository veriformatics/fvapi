#!/usr/bin/env bash
# CI's Lean install: elan from tools/tools.lock (sha256-verified, tools/fetch-tools.sh), then the
# toolchain named in lean-toolchain. Every download is bounded + retried, so a stalled server fails
# the step within minutes (the workflow step's `timeout-minutes` is the outer bound); an unbounded
# install once held a job until its 60 min timeout. Adds elan's bin folder to $GITHUB_PATH.
# Usage: tools/install-lean.sh
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root"

# Per attempt: an install measured 17 s (macOS) to 55 s (Windows).
attempt_secs=180
attempts=3

# Runs "$@" until it exits or `attempt_secs` pass (then kills it: rc 124); portable (macOS has no
# `timeout`), polled once a second so no watchdog outlives it.
bounded() {
    local start=$SECONDS pid rc=0
    "$@" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if ((SECONDS - start >= attempt_secs)); then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
    done
    wait "$pid" || rc=$?
    return "$rc"
}

retried() {
    local i rc=0
    for ((i = 1; i <= attempts; i++)); do
        rc=0
        bounded "$@" || rc=$?
        [[ $rc -eq 0 ]] && return 0
        printf 'install-lean: attempt %d/%d of "%s" failed (rc %d%s)\n' "$i" "$attempts" "$*" "$rc" \
            "$([[ $rc -eq 124 ]] && printf ', past %s s' "$attempt_secs")" >&2
    done
    printf 'install-lean: "%s" failed %d times\n' "$*" "$attempts" >&2
    return 1
}

retried bash tools/fetch-tools.sh elan-init
init=.tools/bin/elan-init
[[ -x "$init.exe" ]] && init="$init.exe"
retried "$init" -y --no-modify-path --default-toolchain none
elan_bin="$HOME/.elan/bin"
export PATH="$elan_bin:$PATH"
retried elan toolchain install "$(tr -d '[:space:]' <lean-toolchain)"
lean --version
lake --version
if [[ -n "${GITHUB_PATH:-}" ]]; then printf '%s\n' "$elan_bin" >>"$GITHUB_PATH"; fi
