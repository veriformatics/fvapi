#!/usr/bin/env bash
# Reads + classifies the step ledger tools/gate.sh appends (.gate/ledger.tsv; columns in its
# header) = the record of which stages buy signal: unique catches per wall-clock (CLAUDE.md
# `Execution`). Each red classifies on the spot — product | gate | flake | planted — and a rerun
# counts only once its red sits classified here. Run where the gate ran (vflab keeps the ledger
# per worktree workspace): tools/vflab-run bash tools/gate-ledger.sh [reds|classify|summary].
# Usage: gate-ledger.sh [reds]               unclassified reds, each with its line number
#        gate-ledger.sh classify LINE CLASS  set that red row's class
#        gate-ledger.sh summary              per stage: runs, reds by class, mean/max/total seconds
# rc 0 = done, 1 = LINE is no red row, 2 = usage or no ledger.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="$root/.gate/ledger.tsv"

usage() {
    printf 'usage: tools/gate-ledger.sh [reds | classify LINE product|gate|flake|planted | summary]\n' >&2
    exit 2
}

[[ -r "$ledger" ]] || {
    printf 'gate-ledger: no ledger at %s\n' "$ledger" >&2
    exit 2
}

case "${1:-reds}" in
reds)
    [[ $# -le 1 ]] || usage
    awk -F'\t' 'NR > 1 && $7 == "unclassified" { print NR ": " $0 }' "$ledger"
    ;;
classify)
    [[ $# -eq 3 && "$2" =~ ^[1-9][0-9]*$ && "$3" =~ ^(product|gate|flake|planted)$ ]] || usage
    tmp="$(mktemp "$ledger.XXXXXX")" || exit 2
    if awk -F'\t' -v OFS='\t' -v n="$2" -v c="$3" '
        NR == n && NR > 1 && $6 == "red" { $7 = c; hit = 1 }
        { print }
        END { exit !hit }' "$ledger" >"$tmp"; then
        mv -- "$tmp" "$ledger"
    else
        rm -f -- "$tmp"
        printf 'gate-ledger: line %s is no red row\n' "$2" >&2
        exit 1
    fi
    ;;
summary)
    [[ $# -le 1 ]] || usage
    awk -F'\t' '
        NR > 1 {
            runs[$4]++; total[$4] += $5; if ($5 > max[$4]) max[$4] = $5
            if ($6 == "red") reds[$4 SUBSEP $7]++
        }
        END {
            for (s in runs)
                printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.1f\t%.1f\t%.1f\n", s, runs[s],
                    reds[s SUBSEP "product"], reds[s SUBSEP "gate"], reds[s SUBSEP "flake"],
                    reds[s SUBSEP "planted"], reds[s SUBSEP "unclassified"],
                    total[s] / runs[s], max[s], total[s]
        }' "$ledger" | sort -t $'\t' -k10,10gr |
        { printf 'step\truns\tproduct\tgate\tflake\tplanted\tunclassified\tmean_s\tmax_s\ttotal_s\n'; cat; }
    ;;
*) usage ;;
esac
