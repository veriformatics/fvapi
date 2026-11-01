#!/usr/bin/env bash
# P5 checker controls: immutable source/binaries/canaries get private replacement files.
set -euo pipefail
kind="${1:?probe kind}"
base="${FVAPI_TEST_CAPSULE:?gate-probe supplies a revalidated capsule}"
# Hardlinks require the capsule's filesystem (the host's /tmp can be a separate mount).
work="$(mktemp -d "$(dirname "$base")/.probe-XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -al "$base" "$work/capsule"
if [[ -e .planted ]]; then
    case "$kind" in
        missing) rm "$work/capsule/fva/.lake/build/bin/fva" ;;
        partial) rm "$work/capsule/capsule.json" ;;
        tool)
            path="$work/capsule/fva/.lake/build/bin/fvamut"
            cp "$path" "$path.bad"
            printf 'planted' >>"$path.bad"
            mv "$path.bad" "$path"
            ;;
        source)
            path="$work/capsule/fva/FVATest/Mutate/Main.lean"
            cp "$path" "$path.bad"
            printf '\n-- planted\n' >>"$path.bad"
            mv "$path.bad" "$path"
            ;;
        canary)
            path="$work/capsule/fva/.cache/canaries/prelude-15704/replaced-prelude.ndjson"
            printf 'planted' >"$path.bad"
            mv "$path.bad" "$path"
            ;;
        *) printf 'capsule-probe: unknown kind %s\n' "$kind" >&2; exit 2 ;;
    esac
fi
FVAPI_CAPSULE_ROOT="$work" bash tools/build-capsule.sh --check "$work/capsule"
