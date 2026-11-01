#!/usr/bin/env bash
# Vendored upstream trees equal their locks (docs/contracts/U3-codecs.md S1): each vendor/*/lock.json
# pins an upstream commit and names every file with its sha256; every named file exists with that
# digest and the tree holds nothing else. Prints each difference. Refresh: tools/vendor-hacl.sh.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1

mapfile -t locks < <(git ls-files -co --exclude-standard -- 'vendor/*/lock.json')
if [[ ${#locks[@]} -eq 0 ]]; then
    printf 'vendor: no vendor/*/lock.json\n' >&2
    exit 1
fi
rc=0
for lock in "${locks[@]}"; do
    dir="$(dirname "$lock")"
    if ! jq -e '(.upstream | type == "string") and (.commit | test("^[0-9a-f]{40}$"))
            and (.files | type == "object" and length > 0)
            and all(.files[]; type == "string" and test("^[0-9a-f]{64}$"))' "$lock" >/dev/null; then
        printf 'vendor: %s: needs upstream, commit (40 hex), files {path: sha256}\n' "$lock" >&2
        rc=1
        continue
    fi
    while IFS=$'\t' read -r f want; do
        if [[ ! -f "$dir/$f" ]]; then
            printf 'vendor: %s/%s missing\n' "$dir" "$f" >&2
            rc=1
        elif [[ "$(sha256sum "$dir/$f" | cut -d' ' -f1)" != "$want" ]]; then
            printf 'vendor: %s/%s sha256 differs from %s\n' "$dir" "$f" "$lock" >&2
            rc=1
        fi
    done < <(jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$lock")
    while read -r f; do
        printf 'vendor: %s/%s not in %s\n' "$dir" "$f" "$lock" >&2
        rc=1
    done < <(comm -13 <(jq -r '.files | keys[]' "$lock" | LC_ALL=C sort) \
        <(git ls-files -co --exclude-standard -- "$dir" | sed "s#^$dir/##" |
            grep -v -x 'lock.json' | LC_ALL=C sort))
done
exit $rc
