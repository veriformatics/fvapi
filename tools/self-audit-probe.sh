#!/usr/bin/env bash
# P6 synthetic native subject. All cases run the real pinned fva; output plants use its clean report.
set -euo pipefail
kind="${1:?probe kind}"
capsule="${FVAPI_TEST_CAPSULE:?gate-probe supplies a revalidated capsule}"
root="$(pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/"{tools,verify,AuditProbe}
cp tools/self-audit.py "$work/tools/"
cp lean-toolchain "$work/"
cp verify/profile.json "$work/verify/"
cat >"$work/lakefile.lean" <<'LEAN'
import Lake
open Lake DSL
package auditprobe
@[default_target] lean_lib AuditProbe
LEAN
printf 'import AuditProbe.Proof\n' >"$work/AuditProbe.lean"
cat >"$work/AuditProbe/Subject.lean" <<'LEAN'
namespace AuditProbe.Subject
def value (n : Nat) : Nat := n
end AuditProbe.Subject
LEAN
cat >"$work/AuditProbe/Self.lean" <<'LEAN'
import AuditProbe.Subject
namespace AuditProbe.Self
def Claim : Prop := ∀ n, Subject.value n = Subject.value n
end AuditProbe.Self
LEAN
cat >"$work/AuditProbe/Proof.lean" <<'LEAN'
import AuditProbe.Self
namespace AuditProbe.Proof
theorem proof : AuditProbe.Self.Claim := by intro n; rfl
end AuditProbe.Proof
LEAN
cat >"$work/verify/claims.json" <<'JSON'
{"claims":[{"domain":"Probe","claim_module":"AuditProbe.Self","claim":"AuditProbe.Self.Claim","proof":"AuditProbe.Proof.proof","proof_root":"AuditProbe","audit_subjects":["AuditProbe.Subject"],"reviewed_surface_budget":40}]}
JSON
if [[ -e "$root/.planted" ]]; then
    case "$kind" in
        sorry)
            sed -i 's/by intro n; rfl/by sorry/' "$work/AuditProbe/Proof.lean"
            ;;
        axiom)
            sed -i '/^theorem/i axiom injected : AuditProbe.Self.Claim' "$work/AuditProbe/Proof.lean"
            sed -i 's/by intro n; rfl/injected/' "$work/AuditProbe/Proof.lean"
            ;;
        partial)
            sed -i 's/def value (n : Nat) : Nat := n/partial def value (n : Nat) : Nat := value n/' \
                "$work/AuditProbe/Subject.lean"
            ;;
        build) printf '\nthis is not Lean\n' >>"$work/AuditProbe/Subject.lean" ;;
        malformed | claims | proof | subjects) ;;
        *) printf 'self-audit-probe: unknown kind %s\n' "$kind" >&2; exit 2 ;;
    esac
fi
python3 -I "$work/tools/self-audit.py" --capsule "$capsule" --domain Probe >"$work/result"
# Success-envelope plants exercise the same parser with the real clean envelope and rc 0.
if [[ -e "$root/.planted" && ( "$kind" == malformed || "$kind" == claims || "$kind" == proof || "$kind" == subjects ) ]]; then
    case "$kind" in
        malformed) printf '{"verdict":"pass"}\n' >"$work/envelope.json" ;;
        claims) jq 'del(.report.claims[0])' "$work/.cache/self-audit/Probe.stdout" >"$work/envelope.json" ;;
        proof) jq '.report.claims[0].proofs[0].name = "Wrong.proof"' "$work/.cache/self-audit/Probe.stdout" >"$work/envelope.json" ;;
        subjects) jq '.report.claims[0].subjects = ["Wrong.Subject"]' "$work/.cache/self-audit/Probe.stdout" >"$work/envelope.json" ;;
    esac
    python3 -I "$work/tools/self-audit.py" --capsule "$capsule" --domain Probe \
        --validate-report "$work/envelope.json" --rc 0
fi
