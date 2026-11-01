#!/usr/bin/env bash
# Probes every purpose-built check of the gate (gate stage `probes`; contract U1 P1): in a scratch
# copy of the worktree the check passes (control), fails once its bad input is planted — for the
# named cause, matched in its output — and passes again once the copy is restored byte for byte.
# A check that cannot fail and a clean tree print the same green. Run on vflab:
# tools/vflab-run bash tools/gate-probe.sh. (tools/vflab-run's own behaviour is qualified on the
# real host from the desktop: tools/vflab-run-probe.sh.) Prints one PROBE line each; exit status
# = probes that failed.
# Check + plant functions run indirectly, through probe().
# shellcheck disable=SC2329
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 1

# A git-tracked scratch copy of the worktree (the checks read `git ls-files`); pinned tools come
# along so tool stages run offline, and the Lake build cache so Lean plants rebuild incrementally.
copy() {
    local dir
    dir="$(mktemp -d)"
    git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -C "$dir" -xf -
    git -C "$dir" init -q && git -C "$dir" add -A &&
        git -C "$dir" -c user.name=probe -c user.email=probe@invalid commit -q -m probe
    [[ -d "$root/.tools" ]] && cp -a "$root/.tools" "$dir/"
    # Lake rebuilds what a plant changes (content-keyed traces); the rest stays cached.
    [[ -d "$root/.lake" ]] && cp -a "$root/.lake" "$dir/"
    printf '%s' "$dir"
}

# probe NAME PLANT EXPECT CHECK… — CHECK passes on a fresh copy, fails after PLANT with EXPECT in
# its output, passes again after the copy is restored. Probes run in the background, at most
# $jobs at a time (each owns its copy); results print in declaration order once all finish.
jobs=4
results="$(mktemp -d)"
trap 'rm -rf "$results"' EXIT
n=0
run_probe() {
    local name="$1" plant="$2" expect="$3" dir pristine control planted restored
    shift 3
    dir="$(copy)"
    pristine="$(mktemp -d)"
    cp -a "$dir/." "$pristine/"
    (cd -- "$dir" && "$@") >"$pristine.control" 2>&1
    control=$?
    (cd -- "$dir" && "$plant") >/dev/null 2>&1
    (cd -- "$dir" && "$@") >"$pristine.planted" 2>&1
    planted=$?
    rsync -a --delete "$pristine/" "$dir/"
    (cd -- "$dir" && "$@") >"$pristine.restored" 2>&1
    restored=$?
    if [[ $control -eq 0 && $planted -ne 0 && $restored -eq 0 ]] &&
        grep -q -F -- "$expect" "$pristine.planted"; then
        printf 'PROBE %s: fired (control 0, planted %d naming "%s", restored 0)\n' \
            "$name" "$planted" "$expect"
    else
        printf 'PROBE %s: FAILED (control %d, planted %d, restored %d; want 0, ≠0 naming "%s", 0)\n' \
            "$name" "$control" "$planted" "$restored" "$expect"
        sed 's/^/    planted: /' "$pristine.planted" | tail -n 20
    fi
    rm -rf -- "$dir" "$pristine" "$pristine".{control,planted,restored}
}
probe() {
    while [[ "$(jobs -rp | wc -l)" -ge $jobs ]]; do wait -n; done
    n=$((n + 1))
    run_probe "$@" >"$results/$(printf '%03d' "$n")" 2>&1 &
}

plant_marker() { touch .planted; }

# A gate main() over planted stages; `.planted` switches each scenario's bad case on.
run_main() { # STAGES-text FUNCTIONS-text ARGS…
    local stages="$1" fns="$2"
    shift 2
    bash -c 'source tools/gate.sh
STAGES="$1"
eval "$2"
shift 2
main "$@"' _ "$stages" "$fns" "$@" 2>&1
}

# G1: a failing stage among passing ones → every stage runs, rc 1, the failure named.
aggregate() {
    local out rc
    out="$(run_main $'\nok-stage probe\nmid-stage probe\nlate-stage probe\n' \
        'ok_stage() { return 0; }; mid_stage() { [[ ! -e .planted ]] || return 3; }; late_stage() { return 0; }' \
        --shard probe)"
    rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] && return 0
    [[ $rc -eq 1 && "$out" == *"mid-stage rc=3"* && "$out" == *"late-stage rc=0"* &&
        "$out" == *"FAILED: mid-stage"* && "$out" == *"gate rc=1"* ]] && return 1
    return 0
}
probe gate-aggregate plant_marker "FAILED: mid-stage" aggregate

# G1: a stage that exits its process cannot end the run; several failures are all named.
exits() {
    local out rc
    out="$(run_main $'\nfirst probe\nleaver probe\nsecond probe\nlast probe\n' \
        'first() { [[ ! -e .planted ]] || return 4; }; leaver() { [[ ! -e .planted ]] || exit 9; }; second() { return 0; }; last() { [[ ! -e .planted ]] || return 5; }' \
        --shard probe)"
    rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] && return 0
    [[ $rc -eq 1 && "$out" == *"leaver rc=9"* && "$out" == *"second rc=0"* &&
        "$out" == *"FAILED: first leaver last"* ]] && return 1
    return 0
}
probe gate-stage-exit plant_marker "FAILED: first leaver last" exits

# G1/G2: an invalid registry (empty, undefined function, duplicate, shardless) fails before any
# stage runs, rc 2.
registry() {
    local out rc stages=$'\nok-stage probe\n'
    if [[ -e .planted ]]; then
        stages=$'\nok-stage probe\nghost-stage probe\nok-stage probe\nlonely\n'
    fi
    out="$(run_main "$stages" 'ok_stage() { return 0; }; lonely() { return 0; }')"
    rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] && return 0
    [[ $rc -eq 2 && "$out" != *"=== "* ]] && return 2
    return 0
}
probe gate-registry plant_marker "has no function ghost_stage" registry

# G2: an unknown shard → rc 2, no stage runs (control: a real shard).
usage() {
    local out rc shard=probe
    [[ -e .planted ]] && shard=nonesuch
    out="$(run_main $'\nok-stage probe\n' 'ok_stage() { return 0; }' --shard "$shard")"
    rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] && return 0
    [[ $rc -eq 2 && "$out" != *"=== "* ]] && return 2
    return 0
}
probe gate-usage plant_marker "usage: tools/gate.sh" usage

# G3: a stage whose tool is absent fails (control: shellcheck on PATH).
shell_stage() {
    if [[ -e .planted ]]; then
        bash -c 'source tools/gate.sh; PATH=/nonexistent; shell'
    else
        bash -c 'source tools/gate.sh; shell'
    fi
}
probe gate-missing-tool plant_marker "shellcheck missing" shell_stage

# G3: a changed cached tool binary is not used: fetch-tools reinstalls it from the verified archive
# (the planted case fails if the corrupt bytes survive).
cached_tool() {
    local before after recorded
    bash tools/fetch-tools.sh zizmor >/dev/null || return 1
    if [[ -e .planted ]]; then
        printf 'corrupt' >>.tools/bin/zizmor
        before="$(sha256sum .tools/bin/zizmor | cut -d' ' -f1)"
        bash tools/fetch-tools.sh zizmor >/dev/null || return 1
        after="$(sha256sum .tools/bin/zizmor | cut -d' ' -f1)"
        recorded="$(awk '{ print $3 }' .tools/bin/.zizmor.stamp)"
        if [[ "$after" != "$before" && "$after" == "$recorded" ]]; then
            printf 'corrupt cached binary replaced\n'
            return 1
        fi
    fi
    return 0
}
probe tool-identity plant_marker "corrupt cached binary replaced" cached_tool

# imports: a shipped module importing `Lean`.
plant_import() { sed -i '1i import Lean' Fvapi/Cli.lean; }
probe imports plant_import "import Lean" bash tools/check-imports.sh

# imports: a shipped module importing the audit tree (U2: Fvapi/** never imports FvapiSpec/Self/Proof).
plant_audit_import() { sed -i '1i import FvapiSpec.Policy' Fvapi/Cli.lean; }
probe imports-audit-tree plant_audit_import "import FvapiSpec.Policy" bash tools/check-imports.sh

# profile: a tampered kernel hash; a dropped comparator target; a missing kernel; a wrong id; a wrong
# runtime digest. The runtime manifest (≈ 18k files) is hashed once here by the stage's own rule and
# reused; the gate's `profile` stage hashes it in full on every run.
if prefix="$(lean --print-prefix 2>/dev/null)"; then
    FVAPI_RUNTIME_DIGEST="$(cd "$prefix" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64)"
    export FVAPI_RUNTIME_DIGEST
fi
profile_stage() { bash tools/check-profile.sh; }
jq_edit() { jq "$1" verify/profile.json >verify/profile.tmp && mv verify/profile.tmp verify/profile.json; }
plant_kernel_sha() { jq_edit '.kernels[0].sha256 = ("0" * 64)'; }
probe profile-kernel plant_kernel_sha "leanchecker: " profile_stage
plant_target() { jq_edit '.comparator.targets -= ["Nat.add"]'; }
probe profile-targets plant_target "comparator targets" profile_stage
plant_runset() { jq_edit 'del(.kernels[3])'; }
probe profile-runset plant_runset "service run set" profile_stage
plant_id() { jq_edit '.id = "sha256:" + ("0" * 64)'; }
probe profile-id plant_id "!= recomputed" profile_stage
plant_runtime() { jq_edit '.runtime.sha256 = ("0" * 64)'; }
probe profile-runtime plant_runtime "runtime manifest" profile_stage

# inventory: a dropped row; a wrong proof type; a non-production call path; a missing matrix row;
# a closed-claim module importing another domain's claims.
inventory_stage() { bash -c 'source tools/gate.sh; inventory'; }
claims_edit() { jq "$1" verify/claims.json >verify/claims.tmp && mv verify/claims.tmp verify/claims.json; }
plant_row() { claims_edit 'del(.claims[1])'; }
probe inventory-row plant_row "with 0 inventory rows" inventory_stage
plant_proof() { claims_edit '.claims[0].proof = "FvapiProof.Policy.accepting_exact"'; }
probe inventory-proof plant_proof "does not have type exactly" inventory_stage
plant_path() { claims_edit '.claims[0].shipped_call_paths = ["FvapiSpec.Policy.Pass"]'; }
probe inventory-path plant_path "not a definition in a production module" inventory_stage
# shellcheck disable=SC2016  # backticks are literal Markdown here
plant_matrix_row() { sed -i 's/`policy-exact`/`policy-gone`/' docs/obligations.md; }
probe inventory-matrix plant_matrix_row "no row in" inventory_stage
plant_locality() {
    printf 'import FvapiSelf.Policy\n\nnamespace FvapiSelf.Probe\n\ndef ProbeClaim : Prop := True\n\nend FvapiSelf.Probe\n' >FvapiSelf/Probe.lean
    printf 'import FvapiSelf.Probe\n' >>FvapiProofs.lean
}
probe inventory-locality plant_locality "claims stay domain-local" inventory_stage

# lean-style: a tab in a Lean source.
plant_tab() { printf '\t-- tab\n' >>Fvapi/Version.lean; }
probe lean-style plant_tab ": tab" bash tools/lean-style.sh

# fanout: a missing shard; a disabled gate step; a masked one; SHARD unbound; fail-fast on.
fanout_stage() { bash -c 'source tools/gate.sh; fanout'; }
plant_matrix() { sed -i 's/^\( *shard: \)\[lean, checks\]$/\1[lean]/' .github/workflows/gate.yml; }
probe fanout-shards plant_matrix "matrix shards" fanout_stage
plant_disabled() {
    sed -i 's/^\(      - name: Run the gate shard\)$/\1\n        if: false/' .github/workflows/gate.yml
}
probe fanout-disabled plant_disabled "unconditional, unmasked" fanout_stage
plant_masked() {
    sed -i 's/^\(      - name: Run the gate shard\)$/\1\n        continue-on-error: true/' .github/workflows/gate.yml
}
probe fanout-masked plant_masked "unconditional, unmasked" fanout_stage
plant_unbound() { sed -i '/^      SHARD: \${{ matrix.shard }}$/d' .github/workflows/gate.yml; }
probe fanout-unbound plant_unbound "SHARD bound" fanout_stage
plant_failfast() { sed -i 's/^      fail-fast: false$/      fail-fast: true/' .github/workflows/gate.yml; }
probe fanout-failfast plant_failfast "fail-fast false" fanout_stage

# deps: a pinned tool without a dependency-table row.
plant_tool() {
    printf 'planted 1.0.0 linux-x86_64 %064d https://github.com/planted/planted/releases/download/v1.0.0/planted.tar.gz\n' 0 \
        >>tools/tools.lock
}
probe deps plant_tool "planted has no row" bash tools/check-deps.sh

# renovate: the vendored-C manager stops matching its lock.
plant_vendor_manager() { sed -i 's/\\"commit\\":/\\"revision\\":/' renovate.json; }
probe renovate-vendor plant_vendor_manager "vendor/hacl-star/lock.json: extracted" python3 -I tools/check-renovate.py

# vendor: one changed byte, a missing file, an extra file in the vendored HACL* tree; a vendored
# upstream without a dependency-table row.
hacl=vendor/hacl-star/dist/gcc-compatible
plant_vendor_byte() { sed -i '1s/MIT License/MIT License /' "$hacl/Hacl_Hash_SHA2.c"; }
plant_vendor_missing() { rm "$hacl/Hacl_Krmllib.h"; }
plant_vendor_extra() { printf 'int planted;\n' >"$hacl/planted.c"; }
plant_vendor_row() { sed -i 's/hacl-star\/hacl-star/hacl-star\/planted/' vendor/hacl-star/lock.json; }
probe vendor-byte plant_vendor_byte "Hacl_Hash_SHA2.c sha256 differs" bash tools/check-vendor.sh
probe vendor-missing plant_vendor_missing "Hacl_Krmllib.h missing" bash tools/check-vendor.sh
probe vendor-extra plant_vendor_extra "planted.c not in" bash tools/check-vendor.sh
probe vendor-deps plant_vendor_row "hacl-star/planted has no row" bash tools/check-deps.sh

# renovate: a manager that stops matching; a half-applied version bump.
plant_manager() { sed -i 's/leanprover\/lean4:v(?<currentValue>/leanprover\/lean5:v(?<currentValue>/' renovate.json; }
probe renovate-extract plant_manager "lean-toolchain: extracted" python3 -I tools/check-renovate.py
plant_halfbump() { sed -i 's/^\(zizmor\) \([0-9.]*\) /\1 99.0.0 /' tools/tools.lock; }
probe renovate-repin plant_halfbump "re-pin with tools/pin-tool.sh zizmor 99.0.0" \
    python3 -I tools/check-renovate.py

# meta: version disagreement; an unquoted rule `paths:` entry.
meta_stage() { bash -c 'source tools/gate.sh; meta'; }
plant_version() {
    sed -i 's/^def version : String := ".*"$/def version : String := "9.9.9"/' Fvapi/Version.lean
}
probe meta-version plant_version 'version "9.9.9" !=' meta_stage
plant_rule() {
    mkdir -p .claude/rules
    printf -- '---\npaths:\n  - Fvapi/**\n---\n\n# planted\n' >.claude/rules/planted.md
}
probe meta-frontmatter plant_rule "paths entry is not a quoted glob" meta_stage

# spec: a spec missing its Phase section.
plant_spec() { sed -i '/^## Phase/,$d' .agent/spec.md; }
probe spec plant_spec "spec-lint:" bash -c 'source tools/gate.sh; spec'

# cli: a binary answering as the contract says passes; one printing a wrong version fails.
fake_binary() {
    local version
    version="$(sed -n 's/^def version : String := "\(.*\)"$/\1/p' Fvapi/Version.lean)"
    [[ -e .planted ]] && version=0.0.0-planted
    cat >fake-fvapi <<SH
#!/bin/sh
usage='usage: fvapi <command>'
case "\$*" in
    --version) echo "fvapi $version" ;;
    help|--help) printf '%s\n\ncommands:\n  --version   Print the version.\n  help        Print this help.\n' "\$usage" ;;
    *) echo "\$usage" >&2; exit 2 ;;
esac
SH
    chmod +x fake-fvapi
    bash tests/cli/smoke.sh ./fake-fvapi
}
probe cli plant_marker "FAIL --version" fake_binary

# Compiler options: `autoImplicit` off rejects an implicit variable and `warningAsError` turns a
# lint into a failure; each plant compiles once its owning option is removed (the option, not
# something else, rejects it).
owned() { # OPTION-PATTERN PLANT-LINE
    local option="$1" line="$2"
    lake build Fvapi >/dev/null 2>&1 || return 0
    [[ -e .planted ]] || return 0
    printf '\n%s\n' "$line" >>Fvapi/Version.lean
    lake build Fvapi >build.log 2>&1 && return 0
    sed -i "s/, ⟨\`$option, [a-z]*⟩//; s/⟨\`$option, [a-z]*⟩, //" lakefile.lean
    lake build Fvapi >/dev/null 2>&1 || return 0
    printf 'rejected only while %s is set\n' "$option"
    return 1
}
implicit() { owned autoImplicit 'def probeImplicit (x : α) : α := x'; }
probe option-autoImplicit plant_marker "rejected only while autoImplicit is set" implicit
warning() { owned warningAsError 'def probeWarning (x : Nat) : Nat := 0'; }
probe option-warningAsError plant_marker "rejected only while warningAsError is set" warning

# ci-gate: a run whose shard job was skipped is not green (fixtures of `gh run view --json jobs`).
ci_verdict() {
    local doc missing
    doc='{"jobs":[{"name":"gate (lean)","conclusion":"success"},{"name":"gate (checks)","conclusion":"success"}]}'
    [[ -e .planted ]] && doc='{"jobs":[{"name":"gate (lean)","conclusion":"success"},{"name":"gate (checks)","conclusion":"skipped"}]}'
    missing="$(bash -c 'source tools/ci-gate.sh; ci_missing "$1" lean checks' _ "$doc")" || return 1
    [[ -z "$missing" ]] && return 0
    printf 'not green: %s\n' "$missing"
    return 1
}
probe ci-verdict plant_marker "not green: checks" ci_verdict

# fast gate: a failing background stage fails the fast gate, named.
plant_fast() { sed -i '1i import Lean' Fvapi/Cli.lean; }
probe fast-gate plant_fast "FAILED: imports" bash tools/fast-gate.sh

wait
cat "$results"/*
missed="$(cat "$results"/* | grep -c '^PROBE .*: FAILED')"
# A probe job that died before printing its line counts as failed.
reported="$(cat "$results"/* | grep -c '^PROBE ')"
if [[ $reported -ne $n ]]; then
    printf 'gate-probe: %d of %d probes printed no result\n' $((n - reported)) "$n"
    missed=$((missed + n - reported))
fi
printf 'gate-probe: %d probe(s) failed\n' "$missed"
exit "$missed"
