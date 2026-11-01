#!/usr/bin/env bash
# The built binary end to end: output streams + exit codes (docs/api.md; contract U1 K2).
# Usage: tests/cli/smoke.sh <fvapi binary>. Prints PASS|FAIL per case; rc = failures.
set -uo pipefail

bin="${1:?usage: tests/cli/smoke.sh <fvapi binary>}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^def version : String := "\(.*\)"$/\1/p' "$root/Fvapi/Version.lean")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

# case NAME WANT_RC WANT_STREAM(stdout|stderr) WANT_FIRST_LINE ARGS…
case_() {
    local name="$1" want_rc="$2" stream="$3" first="$4" rc out err
    shift 4
    "$bin" "$@" >"$tmp/out" 2>"$tmp/err"
    rc=$?
    out="$tmp/out" err="$tmp/err"
    [[ "$stream" == stderr ]] && { out="$tmp/err" err="$tmp/out"; }
    if [[ $rc -eq $want_rc && "$(head -n 1 "$out")" == "$first" && ! -s "$err" ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (rc %d, want %d; %s first line "%s", want "%s")\n' \
            "$name" "$rc" "$want_rc" "$stream" "$(head -n 1 "$out")" "$first"
        fails=$((fails + 1))
    fi
}

case_ "--version" 0 stdout "fvapi $version" --version
# Whole-output checks: --version prints exactly one line; help names every bootstrap command.
"$bin" --version >"$tmp/out" 2>/dev/null
if [[ "$(od -An -c "$tmp/out" | tr -s ' ')" == "$(printf 'fvapi %s\n' "$version" | od -An -c | tr -s ' ')" ]]; then
    printf 'PASS --version output is exactly "fvapi %s" + LF\n' "$version"
else
    printf 'FAIL --version output is not exactly "fvapi %s" + LF\n' "$version"
    fails=$((fails + 1))
fi
"$bin" help >"$tmp/out" 2>/dev/null
if grep -q -- '--version' "$tmp/out" && grep -q -- '  help ' "$tmp/out"; then
    printf 'PASS help names --version + help\n'
else
    printf 'FAIL help does not name --version + help\n'
    fails=$((fails + 1))
fi
case_ "help" 0 stdout "usage: fvapi <command>" help
case_ "--help" 0 stdout "usage: fvapi <command>" --help
case_ "no argument" 2 stderr "usage: fvapi <command>"
case_ "unknown command" 2 stderr "usage: fvapi <command>" frobnicate
case_ "extra argument" 2 stderr "usage: fvapi <command>" --version extra
exit "$fails"
