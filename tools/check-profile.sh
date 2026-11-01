#!/usr/bin/env bash
# Gate stage `profile` (docs/contracts/U2-trust.md P2): verify/profile.json names exactly what this
# host executes — each kernel, the exporter + Lake (comparator) by sha256 under `lean
# --print-prefix`, the comparator source hash + its fixed target set (parsed from the installed
# Lake/CLI/Check.lean), the toolchain runtime manifest — plus the service run set (the six
# kernels, once each) and the profile id rule. Each difference is named; rc 1 on any.
# Canary bytes join with the capsule (U2 part B): reported as not run until `canaries.files` exists.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-$root/verify/profile.json}"
rc=0
bad() { printf 'profile: %s\n' "$1" >&2; rc=1; }

prefix="$(lean --print-prefix)" || { bad "lean --print-prefix failed"; exit 1; }
want_id="sha256:$(jq -S -c 'del(.id)' "$profile" | tr -d '\n' | sha256sum | cut -c1-64)"
[[ "$(jq -r .id "$profile")" == "$want_id" ]] || bad "id $(jq -r .id "$profile") != recomputed $want_id"

check_exe() { # LABEL EXECUTABLE SHA256
    local path="${2//\{lean_prefix\}/$prefix}" got
    if [[ ! -x "$path" ]]; then
        bad "$1: $path missing"
        return
    fi
    got="$(sha256sum "$path" | cut -c1-64)"
    [[ "$got" == "$3" ]] || bad "$1: $path sha256 $got != profile $3"
}
while IFS=$'\t' read -r label exe sha; do
    check_exe "$label" "$exe" "$sha"
done < <(jq -r '(.kernels[] | [.name, .executable, .sha256]), ["exporter", .exporter.executable, .exporter.sha256], ["comparator", .comparator.executable, .comparator.sha256] | @tsv' "$profile")

names="$(jq -r '.kernels[].name' "$profile" | sort | paste -sd' ' -)"
[[ "$names" == "con-leche con-ron lean4lean leanchecker leanchecker-paranoid nanoda" ]] ||
    bad "service run set must be the six kernels once each, got: $names"

src="$prefix/$(jq -r .comparator.source "$profile")"
if [[ -f "$src" ]]; then
    got="$(sha256sum "$src" | cut -c1-64)"
    [[ "$got" == "$(jq -r .comparator.source_sha256 "$profile")" ]] || bad "comparator source sha256 $got != profile"
    parsed="$( { awk '/^def primitiveTargets/{p=1} p && /^ *``/{gsub(/[`, ]/, ""); print} p && /^ *\]/{exit}' "$src"
        awk '/^def builtinTargets/{p=1} p{while (match($0, /``Quot[A-Za-z.]*/)) {print substr($0, RSTART + 2, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH)}} p && /^$/{exit}' "$src" |
            grep -v '^Quot.sound$'; } | sort -u | paste -sd' ' -)"
    listed="$(jq -r '.comparator.targets[]' "$profile" | sort -u | paste -sd' ' -)"
    [[ -n "$parsed" && "$parsed" == "$listed" ]] || bad "comparator targets [$listed] != installed source [$parsed]"
else
    bad "comparator source $src missing"
fi

got="$(cd "$prefix" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64)"
[[ "$got" == "$(jq -r .runtime.sha256 "$profile")" ]] || bad "runtime manifest $got != profile"

if [[ "$(jq '.canaries.files | length' "$profile")" -eq 0 ]]; then
    printf 'profile: not run: canary bytes (pinned by set/known hashes; bytes join with the capsule, U2 part B)\n'
fi
exit $rc
