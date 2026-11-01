#!/usr/bin/env bash
# Layout rules for tracked Lean sources (the 4.35 toolchain ships no formatter): no tabs, no
# trailing whitespace, lines ≤ 100 characters, final newline. Prints `file:line: rule` per finding.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1

mapfile -t files < <(git ls-files -co --exclude-standard -- '*.lean')
rc=0
for f in "${files[@]}"; do
    LC_ALL=C.UTF-8 awk -v f="$f" '
        /\t/ { printf "%s:%d: tab\n", f, FNR; bad = 1 }
        /[ \t]$/ { printf "%s:%d: trailing whitespace\n", f, FNR; bad = 1 }
        length($0) > 100 { printf "%s:%d: line longer than 100 characters\n", f, FNR; bad = 1 }
        END { exit bad }
    ' "$f" || rc=1
    if [[ -s "$f" && "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" != '\n' ]]; then
        printf '%s: no final newline\n' "$f"
        rc=1
    fi
done
exit $rc
