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
mode="${1:---all}"
case "$mode" in --all | --base | --audit) ;; *) printf 'usage: gate-probe.sh [--base|--audit]\n' >&2; exit 2 ;; esac

# A git-tracked scratch copy of the worktree (the checks read `git ls-files`); pinned tools come
# along so tool stages run offline, and the Lake build cache so Lean plants rebuild incrementally.
copy() {
    local dir
    dir="$(mktemp -d)"
    git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -C "$dir" -xf -
    git -C "$dir" init -q && git -C "$dir" add -A &&
        git -C "$dir" -c user.name=probe -c user.email=probe@invalid commit -q -m probe
    # CI keeps the multi-GB capsule here; probes share its revalidated external path instead.
    [[ -d "$root/.tools" ]] && rsync -a --exclude=/capsules/ "$root/.tools/" "$dir/.tools/"
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

if [[ "$mode" != --audit ]]; then
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

# G5: each stage's verdict + wall-clock lands in the step ledger as it ends (a red row
# `unclassified`; tree = the graded file set, an untracked file included); an unwritable ledger
# fails the run, named.
plant_ledger() { rm -rf .gate && mkdir -p .gate/ledger.tsv; }
ledger_rows() {
    local out rc tree want
    printf 'untracked\n' >probe-untracked
    out="$(run_main $'\nok-stage probe\nred-stage probe\n' \
        'ok_stage() { return 0; }; red_stage() { return 3; }' --shard probe)"
    rc=$?
    printf '%s\n' "$out"
    git add -A && tree="$(git write-tree)" || return 1
    want="$tree"$'\tshard:probe\tok-stage\tgreen\t-\n'"$tree"$'\tshard:probe\tred-stage\tred\tunclassified'
    [[ $rc -eq 1 && "$out" == *"FAILED: red-stage"* && "$out" != *ledger* &&
        "$tree" != "$(git rev-parse 'HEAD^{tree}')" &&
        "$(head -n 1 .gate/ledger.tsv)" == $'date\ttree\tkind\tstep\tseconds\tverdict\tclass' &&
        "$(tail -n +2 .gate/ledger.tsv | cut -f2-4,6,7)" == "$want" ]] &&
        awk -F'\t' 'NR > 1 && !(NF == 7 && $1 ~ /^[0-9-]+T[0-9:]+Z$/ && $5 ~ /^[0-9]+\.[0-9]$/) {
            bad = 1 } END { exit bad }' .gate/ledger.tsv
}
probe gate-ledger plant_ledger "ledger: cannot append" ledger_rows

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

# python: both pinned scanners fire inside unannotated helpers; a missing config stays red.
python_stage() { bash -c 'source tools/gate.sh; python'; }
plant_python_lint() {
    printf 'def lint_probe():\n    return ruff_probe_missing_name\n' >tools/python-probe.py
}
plant_python_type() {
    printf 'import importlib.util\ndef type_probe():\n    spec = importlib.util.spec_from_file_location("probe", "probe.py")\n    return spec.loader\n' >tools/python-probe.py
}
plant_python_warning() {
    printf 'def warning_probe():\n    try:\n        int("invalid")\n    except (ValueError, UnicodeError):\n        pass\n' >tools/python-probe.py
}
plant_python_config() { plant_python_type; rm pyrefly.toml; }
plant_python_ruff_missing() { sed -i '/^ruff /d' tools/tools.lock; }
plant_python_pyrefly_missing() { sed -i '/^pyrefly /d' tools/tools.lock; }
probe python-ruff plant_python_lint "F821" python_stage
probe python-pyrefly plant_python_type "[missing-attribute]" python_stage
probe python-warning plant_python_warning "[unreachable-except-clause]" python_stage
probe python-config plant_python_config "pyrefly.toml" python_stage
probe python-ruff-missing plant_python_ruff_missing "no pinned tool matches linux-x86_64 ruff" python_stage
probe python-pyrefly-missing plant_python_pyrefly_missing "no pinned tool matches linux-x86_64 pyrefly" python_stage

# wire: the raw check cap is enforced by the shipped decision function, not a fixture.
plant_wire_cap() { sed -i 's/body.size ≤ 65536/body.size ≤ 65537/' Fvapi/Wire/Decide.lean; }
wire_stage() {
    lake build fvapi >/dev/null 2>&1 || return 1
    bash -c 'source tools/gate.sh; wire'
}
probe wire-body-cap plant_wire_cap "wire: check_over_cap" wire_stage

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
plant_canary_pin() { jq_edit '.canaries.files["prelude-15704/replaced-prelude"] = ("0" * 64)'; }
probe profile-canary-pin plant_canary_pin "canaries.files != pinned canary set" profile_stage
plant_canary_bytes() {
    local cache
    cache="$(python3 -I tools/canaries.py)" || return 1
    printf 'planted' >"$cache/prelude-15704/replaced-prelude.ndjson"
}
probe profile-canary-bytes plant_canary_bytes "canaries.files.prelude-15704/replaced-prelude" profile_stage

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

# P4's elaboration-sensitive boundaries; diagnostics must identify the planted check itself.
plant_inventory_empty() { claims_edit '.claims = []'; }
probe inventory-empty plant_inventory_empty "inventory is empty" inventory_stage
plant_inventory_duplicate() { claims_edit '.claims += [.claims[0]]'; }
probe inventory-duplicate plant_inventory_duplicate "duplicate or empty id" inventory_stage
plant_inventory_alias() {
    printf '\nnamespace FvapiSelf.Policy\nabbrev PropAlias := Prop\ndef Aliased : PropAlias := True\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-aliased-prop plant_inventory_alias "FvapiSelf.Policy.Aliased is a closed claim with 0" inventory_stage
plant_inventory_open() {
    printf '\nnamespace FvapiSelf.Policy\ndef OpenClaim (n : Nat) : Prop := n = n\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-closed plant_inventory_open "claim is not closed" inventory_stage
plant_inventory_universe() {
    printf '\nnamespace FvapiSelf.Policy\nuniverse u\ndef UniverseClaim : Prop := ∀ (α : Type u) (x : α), x = x\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-universe plant_inventory_universe "claim is not universe-free" inventory_stage
plant_inventory_subject() { claims_edit '.claims[0].audit_subjects = ["Fvapi.Missing"]'; }
probe inventory-subject plant_inventory_subject "audit subject Fvapi.Missing is not a production module" inventory_stage
plant_inventory_kind() { claims_edit '.claims[0].proof = "Fvapi.Verify.verdict"'; }
probe inventory-theorem plant_inventory_kind "proof Fvapi.Verify.verdict is not a theorem" inventory_stage
plant_inventory_aggregate() { sed -i '/^import FvapiProof.Profile$/d' FvapiProofs.lean; }
probe inventory-aggregate plant_inventory_aggregate "aggregate proof root omits FvapiProof.Profile" inventory_stage
plant_inventory_production() { sed -i '1i import FvapiSpec.Policy' Fvapi/Cli.lean; }
probe inventory-production plant_inventory_production "production import closure contains audit module" inventory_stage
plant_inventory_transitive() {
    printf 'import FvapiSelf.Policy\n' >FvapiSpec/ProbeBridge.lean
    printf 'import FvapiSpec.ProbeBridge\nnamespace FvapiSelf.Probe\ndef ProbeClaim : Prop := True\nend FvapiSelf.Probe\n' >FvapiSelf/Probe.lean
    printf 'import FvapiSelf.Probe\n' >>FvapiProofs.lean
}
probe inventory-transitive plant_inventory_transitive "claims stay domain-local" inventory_stage
plant_inventory_domain() { claims_edit '.claims[0].spec_module = "FvapiSpec.Profile"'; }
probe inventory-domain plant_inventory_domain "domain module identities disagree" inventory_stage
plant_inventory_proof_module() { claims_edit '.claims[0].proof_module = "FvapiProof.Profile"'; }
probe inventory-proof-module plant_inventory_proof_module "proof is not declared in FvapiProof.Profile" inventory_stage
probe inventory-proof-domain plant_inventory_proof_module "domain module identities disagree" inventory_stage
plant_inventory_helper() { claims_edit '.claims[0].spec_module = "FvapiSpec.Missing"'; }
probe inventory-helper plant_inventory_helper "helper spec module FvapiSpec.Missing does not resolve" inventory_stage
plant_inventory_roots() { claims_edit '.production_roots = []'; }
probe inventory-roots plant_inventory_roots "production and audit roots must be nonempty" inventory_stage
plant_inventory_helper_location() {
    printf '\nnamespace FvapiSelf.Policy\ndef misplacedHelper : Nat := 1\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-helper-location plant_inventory_helper_location "helpers belong in FvapiSpec modules" inventory_stage
plant_inventory_claim_kind() {
    printf '\nnamespace FvapiSelf.Policy\ntheorem misplacedProof : True := by trivial\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-claim-kind plant_inventory_claim_kind "closed-claim modules contain claim definitions alone" inventory_stage
plant_inventory_matrix_extra() {
    printf '| Unlisted promise | unlisted-claim | | | | |\n' >>docs/obligations.md
}
probe inventory-matrix-extra plant_inventory_matrix_extra "matrix row names no inventoried claim" inventory_stage
plant_inventory_matrix_header() {
    claims_edit '.claims[0].id = "Claim id"'
    # shellcheck disable=SC2016  # literal Markdown cells
    sed -i 's/`policy-exact`/`accepting-exact`/g' docs/obligations.md
}
probe inventory-matrix-header plant_inventory_matrix_header "Claim id: no row in" inventory_stage
plant_inventory_production_roots() { claims_edit '.production_roots = ["Fvapi"]'; }
probe inventory-production-roots plant_inventory_production_roots "production_roots must be exactly" inventory_stage
plant_inventory_audit_roots() { claims_edit '.audit_roots += ["FvapiProof.Policy"]'; }
probe inventory-audit-roots plant_inventory_audit_roots "audit_roots must be exactly" inventory_stage
plant_inventory_hidden_domain() {
    claims_edit '.claims |= map(select(.domain != "Profile"))'
    sed -i '/^import FvapiProof.Profile$/d' FvapiProofs.lean
}
probe inventory-hidden-domain plant_inventory_hidden_domain "aggregate proof root does not reach closed-claim module FvapiSelf.Profile" inventory_stage
plant_inventory_budget() { claims_edit '.claims[0].reviewed_surface_budget = 0'; }
probe inventory-budget plant_inventory_budget "reviewed_surface_budget must be a positive integer" inventory_stage
plant_inventory_budget_type() { claims_edit '.claims[0].reviewed_surface_budget = "40"'; }
probe inventory-budget-type plant_inventory_budget_type "reviewed_surface_budget:" inventory_stage
plant_inventory_snapshot() { claims_edit '.claims[0].expected_snapshot = "sha256:" + ("A" * 64)'; }
probe inventory-snapshot plant_inventory_snapshot "expected_snapshot must be sha256: + 64 lowercase hex" inventory_stage
plant_inventory_private() {
    printf '\nnamespace FvapiSelf.Policy\nprivate def Hidden : Prop := True\nend FvapiSelf.Policy\n' >>FvapiSelf/Policy.lean
}
probe inventory-private plant_inventory_private "FvapiSelf.Policy.Hidden is a closed claim with 0" inventory_stage

# Lake must trace the file included in the shipped runner, not only its importing Lean source.
plant_inventory_embed() { printf '\n-- FVAPI_EMBEDDED_PROBE\n' >>tools/lean/Inventory.lean; }
inventory_embed_stage() {
    lake build fvapi >/dev/null 2>&1 || return 2
    if grep -a -q -F FVAPI_EMBEDDED_PROBE .lake/build/bin/fvapi; then
        printf 'embedded checker source changed binary\n'
        return 1
    fi
    return 0
}
probe inventory-embedded-source plant_inventory_embed "embedded checker source changed binary" inventory_embed_stage

# P7 zero-site controls: well-typed serializer + substitution defects must fail assertions.
plant_rc_json() {
    sed -i 's/)).getD .null/)).getD (.int 0)/' Fvapi/Verify/Replay.lean
}
probe replay-rc-json-exact plant_rc_json "assertion: replay-rc-json-exact" \
    bash tests/replay/rc-json-exact.sh
plant_placeholder_substitution() {
    python3 -I - <<'PY'
from pathlib import Path
path = Path("Fvapi/Verify/Replay.lean")
text = path.read_text()
old = '    |>.replace "{axioms}" (",".intercalate axioms)'
assert text.count(old) == 1
path.write_text(text.replace(old, '    |>.replace "{unbound_axioms}" (",".intercalate axioms)'))
PY
}
probe replay-placeholder-substitution plant_placeholder_substitution \
    "assertion: replay-placeholder-substitution" bash tests/replay/placeholder-substitution.sh

# lean-style: a tab in a Lean source.
plant_tab() { printf '\t-- tab\n' >>Fvapi/Version.lean; }
probe lean-style plant_tab ": tab" bash tools/lean-style.sh

# fanout: a missing shard; a disabled gate step; a masked one; SHARD unbound; fail-fast on.
fanout_stage() { bash -c 'source tools/gate.sh; fanout'; }
plant_matrix() { sed -i 's/^\( *shard: \)\[lean, checks, audit\]$/\1[lean, checks]/' .github/workflows/gate.yml; }
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

# native: a wrong total length in the SHA-256 core (digest mismatch); one block read past each chunk
# (only a live AddressSanitizer catches it).
plant_native_total() {
    sed -i 's/n % 64, (uint64_t)n, out);/n % 64, (uint64_t)n + 1, out);/' c/fvapi_sha256_core.c
}
plant_native_overread() {
    sed -i 's/update_nblocks((uint32_t)n, /update_nblocks((uint32_t)n + 64, /' c/fvapi_sha256_core.c
}
probe native-total plant_native_total "MISMATCH one-shot" bash tests/native/run.sh
probe native-asan plant_native_overread "AddressSanitizer" bash tests/native/run.sh

# fsync: the real external object's finalizer must preserve a reused descriptor; ASan stays live.
plant_fsync_lifecycle() {
    sed -i 's/writer->closed = true;/writer->closed = false;/' c/fvapi_fsync.c
}
plant_fsync_asan() {
    sed -i '/free(writer->path);/i\    writer->path[strlen(writer->path) + 1] = 0;' c/fvapi_fsync.c
}
probe fsync-lifecycle plant_fsync_lifecycle "explicit close did not persist closed flag" \
    bash tests/fsync/native.sh
probe fsync-asan plant_fsync_asan "AddressSanitizer" bash tests/fsync/native.sh

# renovate: the vendored-C manager stops matching its lock.
plant_vendor_manager() { sed -i 's/\\"commit\\":/\\"revision\\":/' renovate.json; }
probe renovate-vendor plant_vendor_manager "vendor/hacl-star/lock.json: extracted" python3 -I tools/check-renovate.py
plant_capsule_manager() { sed -i 's#verify/capsule#verify/missing-capsule#' renovate.json; }
probe renovate-capsule plant_capsule_manager "verify/capsule.lock: extracted" python3 -I tools/check-renovate.py

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
    doc='{"jobs":[{"name":"gate (lean)","conclusion":"success"},{"name":"gate (checks)","conclusion":"success"},{"name":"gate (audit)","conclusion":"success"}]}'
    [[ -e .planted ]] && doc='{"jobs":[{"name":"gate (lean)","conclusion":"success"},{"name":"gate (checks)","conclusion":"skipped"},{"name":"gate (audit)","conclusion":"success"}]}'
    missing="$(bash -c 'source tools/ci-gate.sh; ci_missing "$1" lean checks audit' _ "$doc")" || return 1
    [[ -z "$missing" ]] && return 0
    printf 'not green: %s\n' "$missing"
    return 1
}
probe ci-verdict plant_marker "not green: checks" ci_verdict

# fast gate: a failing background stage fails the fast gate, named.
plant_fast() { sed -i '1i import Lean' Fvapi/Cli.lean; }
probe fast-gate plant_fast "FAILED: imports" bash tools/fast-gate.sh
fi

if [[ "$mode" != --base ]]; then
    # The capsule is shared + locked; each plant gets private hardlinks and replaces whole files.
    FVAPI_TEST_CAPSULE="$(bash tools/build-capsule.sh)" || exit 1
    export FVAPI_TEST_CAPSULE
    probe capsule-missing-tool plant_marker "tool fva: missing executable" bash tools/capsule-probe.sh missing
    probe capsule-partial plant_marker "partial capsule: capsule.json missing" bash tools/capsule-probe.sh partial
    probe capsule-tool-bytes plant_marker "capsule binaries: bytes differ" bash tools/capsule-probe.sh tool
    probe capsule-source-bytes plant_marker "source FVATest/Mutate/Main.lean differs" bash tools/capsule-probe.sh source
    probe capsule-canary-bytes plant_marker "canary prelude-15704/replaced-prelude" bash tools/capsule-probe.sh canary
    probe self-audit-sorry plant_marker "non_pass tags=axiom" bash tools/self-audit-probe.sh sorry
    probe self-audit-axiom plant_marker "non_pass tags=axiom" bash tools/self-audit-probe.sh axiom
    probe self-audit-partial plant_marker "override" bash tools/self-audit-probe.sh partial
    probe self-audit-malformed plant_marker "malformed success output" bash tools/self-audit-probe.sh malformed
    probe self-audit-claim-set plant_marker "claim set != inventory" bash tools/self-audit-probe.sh claims
    probe self-audit-proof-set plant_marker "proof identities != inventory" bash tools/self-audit-probe.sh proof
    probe self-audit-subjects plant_marker "subject identities != inventory" bash tools/self-audit-probe.sh subjects
    probe self-audit-build plant_marker "build_failed" bash tools/self-audit-probe.sh build
    probe self-audit-memory plant_marker "aggregate_memory_exceeded" python3 -I tools/audit-supervisor-probe.py memory
    probe self-audit-timeout plant_marker "whole_invocation_timeout" python3 -I tools/audit-supervisor-probe.py timeout
fi

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
