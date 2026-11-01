#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$root"
mkdir -p .lake
scratch=$(mktemp -d "$root/.lake/u2-fixture-check.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
python3 -I TestsU2/fixtures.py prepare --root "$scratch" --repo "$root" \
  --base "${U2_BASE_PROFILE:-$root/verify/profile.json}" > "$scratch/prepare.json"
failures=0
cases=0
# Profile-only cases share valid sources; replay mutations + every inventory fixture are distinct.
while IFS=$'\t' read -r test_id _ case_root _; do
  [[ $test_id == P2-* ]] && continue
  if (cd -- "$case_root/package" && lake build FvapiProofs Fvapi fixture) > "$scratch/fixture.log" 2>&1; then
    printf 'PASS fixture-build %s\n' "$test_id"
  else
    printf 'FAIL fixture-build %s\n' "$test_id"
    cat "$scratch/fixture.log"
    failures=$((failures + 1))
  fi
  cases=$((cases + 1))
done < <(python3 -I TestsU2/fixtures.py list "$scratch/cases.json" all)
printf 'fixture-build cases=%s failures=%s\n' "$cases" "$failures"
(( failures == 0 ))
