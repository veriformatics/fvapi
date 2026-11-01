#!/usr/bin/env bash
# The one gate command: a human, an agent and CI run exactly this, so one result is one claim.
# Run it on vflab (user ruling: all fvapi work runs there): tools/vflab-run bash tools/gate.sh.
# Stages run to completion after a failure, each in a subshell (a stage that exits cannot end the
# run), so one run reports every problem; each prints `<stage> rc=N <s>s`, the run closes on
# `gate rc=N <s>s`. A missing tool or one whose pinned identity fails fails its stage: an
# unavailable tool = gate incomplete, never green. Contract: docs/contracts/U1-foundation.md.
# Usage: tools/gate.sh [--shard NAME] — no argument = every stage; a shard = its stages alone
# (CI runs one job per shard, see STAGES).
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1

failed=()

stamp() { printf '%s' "${EPOCHREALTIME//[!0-9]/}"; }
elapsed() {
    local us=$(($(stamp) - $1))
    printf '%d.%d' $((us / 1000000)) $((us / 100000 % 10))
}

stage() {
    local name="$1" start rc
    shift
    start="$(stamp)"
    printf '\n=== %s ===\n' "$name"
    ("$@")
    rc=$?
    printf '%s rc=%d %ss\n' "$name" "$rc" "$(elapsed "$start")"
    [[ $rc -eq 0 ]] || failed+=("$name")
    return 0
}

# Stage · CI shards. A full run takes every stage in this order, each running the function of its
# name (`-` → `_`). CI runs one job per shard (gate.yml matrix), each on a fresh checkout, so a
# shard whose stages read the build lists lean-build too; `fanout` holds the matrix = these shards.
STAGES='
tools       checks
lean-style  checks
lean-build  lean
lean-test   lean
cli         lean
probes      lean
profile     lean
inventory   lean
imports     checks
spec        checks
shell       checks
secrets     checks
workflows   checks
fanout      checks
deps        checks
renovate    checks
meta        checks
'

# The iteration subset tools/fast-gate.sh runs (build-consuming stages after lean-build).
# shellcheck disable=SC2034
FAST_STAGES='lean-style imports spec shell fanout deps renovate meta lean-build lean-test cli'

# Every shard STAGES names, once each, in first-use order.
shard_names() { awk 'NF { for (i = 2; i <= NF; i++) if (!seen[$i]++) print $i }' <<<"$STAGES"; }

# STAGES is nonempty; each row = a unique stage whose function exists + ≥ 1 shard.
registry_ok() {
    local rc=0 rows row name shards
    mapfile -t rows < <(awk 'NF' <<<"$STAGES")
    if [[ ${#rows[@]} -eq 0 ]]; then
        printf 'gate: STAGES is empty\n' >&2
        return 1
    fi
    for row in "${rows[@]}"; do
        read -r name shards <<<"$row"
        if [[ -z "$shards" ]]; then
            printf 'gate: stage %s has no shard\n' "$name" >&2
            rc=1
        fi
        if [[ "$(type -t "${name//-/_}")" != function ]]; then
            printf 'gate: stage %s has no function %s\n' "$name" "${name//-/_}" >&2
            rc=1
        fi
    done
    if [[ -n "$(awk 'NF { print $1 }' <<<"$STAGES" | sort | uniq -d)" ]]; then
        printf 'gate: duplicate stage names\n' >&2
        rc=1
    fi
    return $rc
}

# A pinned tool's installed path after tools/fetch-tools.sh verified it (prints nothing + fails
# otherwise); stages call this path, never a PATH lookup.
pinned() { bash tools/fetch-tools.sh "$1" >&2 && printf '%s' "$root/.tools/bin/$1"; }

tools() { bash tools/fetch-tools.sh; }

# Lean sources: no tab, no trailing whitespace, lines ≤ 100 characters, final newline.
lean_style() { bash tools/lean-style.sh; }

# Every target; `warningAsError` turns lints into failures, `autoImplicit` off rejects implicit
# variables (probes plant both).
lean_build() { lake build Fvapi FvapiProofs fvapi «fvapi-tests»; }

lean_test() { lake test; }

# The shipped binary end to end: output streams + exit codes (docs/api.md).
cli() { bash tests/cli/smoke.sh "$root/.lake/build/bin/fvapi"; }

# Each purpose-built check passes on a clean copy, fails on its planted input, passes restored.
probes() { bash tools/gate-probe.sh; }

# verify/profile.json names exactly the kernels, exporter, comparator + runtime this host executes.
profile() { bash tools/check-profile.sh; }

# verify/claims.json ↔ the elaborated closed claims, proof types, call paths, matrix rows (U2 P4).
inventory() {
    lake build FvapiProofs >/dev/null 2>&1 || {
        printf 'inventory: FvapiProofs does not build\n' >&2
        return 1
    }
    lake env lean --run tools/lean/Inventory.lean
}

# Shipped modules import Init, Std + Fvapi alone (`Decisions` → `Stack`: a Std-only server binary).
imports() { bash tools/check-imports.sh; }

spec() { sh .agent/spec-lint .agent/spec.md; }

# Every shell script: `*.sh` + each other file whose shebang names sh or bash.
shell() {
    local files=()
    mapfile -t files < <(
        git ls-files -co --exclude-standard -- '*.sh'
        git ls-files -co --exclude-standard -z -- ':!*.sh' | xargs -0 awk 'FNR == 1 {
            if (/^#!(\/usr)?\/bin\/(env +)?(ba)?sh([ \t]|$)/) print FILENAME
            nextfile }'
    )
    if ! command -v shellcheck >/dev/null; then
        printf 'shell: shellcheck missing\n' >&2
        return 1
    fi
    if [[ ${#files[@]} -eq 0 ]]; then
        printf 'shell: no shell script found\n' >&2
        return 1
    fi
    shellcheck -- "${files[@]}"
}

# History + every tracked or untracked-unignored file; live validation stays off (no network).
secrets() {
    local rc=0 leaks
    leaks="$(pinned betterleaks)" || return 1
    "$leaks" git --no-banner --redact . || rc=1
    git ls-files -co --exclude-standard -z | xargs -0 -r "$leaks" dir --no-banner --redact || rc=1
    return $rc
}

workflows() {
    local rc=0 zizmor actionlint
    zizmor="$(pinned zizmor)" || return 1
    actionlint="$(pinned actionlint)" || return 1
    "$zizmor" --no-progress .github/ || rc=1
    "$actionlint" || rc=1
    return $rc
}

# CI runs the gate as one job per gate.yml matrix shard: the matrix = the gate's shards, every
# stage has a shard, and job `gate` runs exactly one unconditional, unmasked
# `bash tools/gate.sh --shard "$SHARD"` step with SHARD bound to the matrix value and fail-fast
# off. Matched by YAML position (job keys at 2 spaces, job properties at 4, steps at 6, step keys
# at 8): the same text in a comment or a block scalar runs no gate and does not count.
fanout() {
    local rc=0 wf=.github/workflows/gate.yml matrix shards facts
    awk 'NF == 1 { print "fanout: stage " $1 " has no CI shard"; bad = 1 } END { exit bad }' \
        <<<"$STAGES" >&2 || rc=1
    matrix="$(sed -n 's/^ *shard: \[\(.*\)\]$/\1/p' "$wf" | tr -d ' ' | tr ',' '\n' | sort)"
    shards="$(shard_names | sort)"
    if [[ -z "$matrix" || "$matrix" != "$shards" ]]; then
        printf 'fanout: %s matrix shards [%s] != tools/gate.sh shards [%s]\n' "$wf" \
            "$(paste -sd, - <<<"$matrix")" "$(paste -sd, - <<<"$shards")" >&2
        rc=1
    fi
    # shellcheck disable=SC2016
    facts="$(awk '
        function flush() { if (run) { runs++; if (cond) masked++ } run = 0; cond = 0 }
        /^[^ #]/ { flush(); top = $0 }
        top == "jobs:" && /^  [^ #]/ { flush(); job = $1 }
        job == "gate:" {
            if ($0 ~ /^    (if|continue-on-error):/) jobmask = 1
            if ($0 ~ /^      fail-fast: false$/) failfast = 1
            if ($0 ~ /^      SHARD: \$\{\{ matrix\.shard \}\}$/) bound = 1
            if ($0 ~ /^      - /) flush()
            if ($0 ~ /^        run: bash tools\/gate\.sh --shard "\$SHARD"$/) run = 1
            if ($0 ~ /^(      - |        )(if|continue-on-error):/) cond = 1
        }
        END { flush(); print runs + 0, masked + 0, jobmask + 0, failfast + 0, bound + 0 }' "$wf")"
    if [[ "$facts" != "1 0 0 1 1" ]]; then
        printf 'fanout: %s job gate needs one unconditional, unmasked gate step, SHARD bound to the matrix + fail-fast false (runs masked job-mask fail-fast bound = %s)\n' \
            "$wf" "$facts" >&2
        rc=1
    fi
    return $rc
}

# Every pin (lean-toolchain, tools/tools.lock, workflow actions, Lake packages) has a row in
# docs/dependencies.md naming its update path + scanner.
deps() { bash tools/check-deps.sh; }

# Renovate's custom managers extract every pin they own (lean-toolchain, tools/tools.lock, a Lake
# manifest), and the lock file keeps one coherent version per tool.
renovate() { python3 -I tools/check-renovate.py; }

# The version Lake + the binary each read agree (exactly one nonempty value each); every rule
# file's frontmatter keeps the quoted `paths:` list the loader parses.
meta() {
    local rc=0 lean lake f
    lean="$(sed -n 's/^def version : String := "\(.*\)"$/\1/p' Fvapi/Version.lean)"
    lake="$(sed -n 's/^  version := v!"\(.*\)"$/\1/p' lakefile.lean)"
    if [[ -z "$lean" || "$lean" == *$'\n'* || "$lean" != "$lake" ]]; then
        printf 'meta: Fvapi/Version.lean version "%s" != lakefile.lean version "%s"\n' "$lean" "$lake" >&2
        rc=1
    fi
    for f in .claude/rules/*.md; do
        [[ -e "$f" ]] || continue
        awk -v f="$f" '
            NR == 1 { if ($0 != "---") exit 0; fm = 1; next }
            fm && $0 == "---" { closed = 1; exit }
            fm && /^paths:/ { paths = 1; next }
            fm && /^[^ ]/ { paths = 0 }
            fm && paths && !/^  - "[^"]+"$/ { printf "meta: %s:%d: paths entry is not a quoted glob\n", f, NR; bad = 1 }
            END { if (fm && !closed) { printf "meta: %s: frontmatter not closed\n", f; bad = 1 } exit bad }
        ' "$f" >&2 || rc=1
    done
    return $rc
}

main() {
    local start shard="" rows row name shards
    registry_ok || exit 2
    if [[ $# -gt 0 ]]; then
        if [[ $# -ne 2 || "$1" != --shard ]] || ! shard_names | grep -x -F -- "$2" >/dev/null; then
            printf 'usage: tools/gate.sh [--shard %s]\n' "$(shard_names | paste -sd'|' -)" >&2
            exit 2
        fi
        shard="$2"
    fi
    start="$(stamp)"
    # An array, not a `while read` loop: stages keep the caller's stdin.
    mapfile -t rows <<<"$STAGES"
    for row in "${rows[@]}"; do
        read -r name shards <<<"$row"
        if [[ -n "$name" && ( -z "$shard" || " $shards " == *" $shard "* ) ]]; then
            stage "$name" "${name//-/_}"
        fi
    done
    printf '\n=== gate%s ===\n' "${shard:+ (shard $shard)}"
    if [[ ${#failed[@]} -ne 0 ]]; then
        printf 'FAILED: %s\n' "${failed[*]}"
        printf 'gate rc=1 %ss\n' "$(elapsed "$start")"
        exit 1
    fi
    printf 'gate rc=0 %ss\n' "$(elapsed "$start")"
}

# Sourcing exposes the stage functions without running the gate (tools/fast-gate.sh, probes).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
