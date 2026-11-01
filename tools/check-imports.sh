#!/usr/bin/env bash
# Shipped modules (Main.lean, Fvapi.lean, Fvapi/**) import Init, Std + Fvapi alone, so the server
# binary stays Std-only (`Decisions` → `Stack`). Prints `file:line: import X` per violation.
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1
mapfile -t files < <(git ls-files -co --exclude-standard -- Main.lean Fvapi.lean 'Fvapi/*.lean')
if [[ ${#files[@]} -eq 0 ]]; then
    printf 'imports: no shipped module found\n' >&2
    exit 1
fi
awk '
    match($0, /^[ \t]*((public|private|meta)[ \t]+)*import[ \t]+/) {
        n = split(substr($0, RSTART + RLENGTH), mods, /[ \t]+/)
        for (i = 1; i <= n; i++) {
            if (mods[i] == "" || mods[i] ~ /^--/) break
            if (mods[i] !~ /^(Init|Std|Fvapi)(\.|$)/) {
                printf "%s:%d: import %s\n", FILENAME, FNR, mods[i]
                bad = 1
            }
        }
    }
    END { exit bad }' "${files[@]}" >&2
