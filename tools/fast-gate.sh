#!/usr/bin/env bash
# Iteration gate: FAST_STAGES from tools/gate.sh — the independent checks in parallel, then the
# incremental Lean build + the stages that consume it. Never the claim: the stages it skips (the
# registry minus FAST_STAGES) run in tools/gate.sh alone and are printed. rc 0 iff every selected
# stage returned 0. Run on vflab: tools/vflab-run bash tools/fast-gate.sh
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1
# shellcheck source=tools/gate.sh
source tools/gate.sh
registry_ok || exit 2
start="$(stamp)"

sequential=(lean-build lean-test cli)
parallel=()
for name in $FAST_STAGES; do
    [[ " ${sequential[*]} " == *" $name "* ]] || parallel+=("$name")
done

log="$(mktemp -d)"
trap 'rm -rf "$log"' EXIT
pids=()
for name in "${parallel[@]}"; do
    (
        t0="$(stamp)"
        ("${name//-/_}") >"$log/$name" 2>&1
        rc=$?
        elapsed "$t0" >"$log/$name.time"
        exit $rc
    ) &
    pids+=($!)
done

for name in "${sequential[@]}"; do
    stage "$name" "${name//-/_}"
done

for i in "${!parallel[@]}"; do
    wait "${pids[$i]}"
    rc=$?
    printf '\n=== %s ===\n' "${parallel[$i]}"
    cat "$log/${parallel[$i]}"
    printf '%s rc=%d %ss\n' "${parallel[$i]}" "$rc" "$(cat "$log/${parallel[$i]}.time")"
    [[ $rc -eq 0 ]] || failed+=("${parallel[$i]}")
done

skipped="$(awk -v fast=" $FAST_STAGES " 'NF && index(fast, " " $1 " ") == 0 { printf "%s ", $1 }' <<<"$STAGES")"
printf '\n=== fast gate ===\nselected: %s\nskipped (tools/gate.sh alone): %s\n' "$FAST_STAGES" "$skipped"
if [[ ${#failed[@]} -ne 0 ]]; then
    printf 'FAILED: %s\nfast-gate rc=1 %ss\n' "${failed[*]}" "$(elapsed "$start")"
    exit 1
fi
printf 'fast-gate rc=0 %ss\n' "$(elapsed "$start")"
