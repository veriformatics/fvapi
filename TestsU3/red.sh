#!/usr/bin/env bash
# Freeze credit: expected adapter-import failure; succeeds only when every T group is red.
set -uo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 2
python3 -I TestsU3/corpus.py .lake/tests-u3 || exit 2
failed=0
for suite in T{1..10}; do
    start="${EPOCHREALTIME//[!0-9]/}"
    bash TestsU3/run.sh --prepared "$suite" > ".lake/tests-u3/red-$suite.log" 2>&1
    rc=$?
    finish="${EPOCHREALTIME//[!0-9]/}"
    cause="$(/usr/bin/grep -m 1 -E 'Fvapi[/.]Json|Fvapi[/.]Hash' \
        ".lake/tests-u3/red-$suite.log" || true)"
    printf '%s rc=%s ms=%s first=%s\n' "$suite" "$rc" "$(((finish-start)/1000))" "$cause"
    if [[ $rc -ne 2 || -z "$cause" ]]; then
        printf 'freeze red: %s did not fail at the implementation adapter\n' "$suite" >&2
        head -35 ".lake/tests-u3/red-$suite.log" >&2
        failed=1
    fi
done
printf 'freeze red rc=%s (expected red, not implementation green)\n' "$failed"
exit "$failed"
