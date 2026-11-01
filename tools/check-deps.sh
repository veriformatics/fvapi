#!/usr/bin/env bash
# Every pinned dependency has a row in docs/dependencies.md (`name` in backticks) naming its update
# path + scanner: the Lean toolchain, each tools/tools.lock tool, each workflow action, each Lake
# package. Prints each missing name.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1
table=docs/dependencies.md
[[ -f "$table" ]] || {
    printf 'deps: %s missing\n' "$table" >&2
    exit 1
}
mapfile -t names < <(
    sed -n 's#^leanprover/\(lean4\):.*#leanprover/\1#p' lean-toolchain
    awk '!/^#/ && NF == 5 { print $1 }' tools/tools.lock
    sed -n 's#^ *- *uses: \([^@ ]*\)@.*#\1#p; s#^ *uses: \([^@ ]*\)@.*#\1#p' .github/workflows/*.yml
    if [[ -f lake-manifest.json ]]; then jq -r '.packages[]?.name' lake-manifest.json; fi
)
rc=0
for n in $(printf '%s\n' "${names[@]}" | sort -u); do
    grep -F -q -- "\`$n\`" "$table" || {
        printf 'deps: %s has no row in %s\n' "$n" "$table" >&2
        rc=1
    }
done
exit $rc
