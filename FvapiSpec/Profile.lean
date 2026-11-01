import Fvapi.Verify.Profile
import FvapiSpec.Policy

/-! Reviewed vocabulary for the verification profile's run set (`docs/contracts/U2-trust.md`
P2), stated apart from the implementation's `runSetOk`. -/

namespace FvapiSpec.Profile

open Fvapi.Verify

/-- fvapi's own profile names every kernel exactly once; a caller-held one names kernels without
repeats, including Lean's default kernel and one of another implementation. -/
def RunSetOk : Scope → List KernelId → Prop
  | .service, ks => ks.Nodup ∧ ∀ k : KernelId, k ∈ ks
  | .caller, ks => ks.Nodup ∧ .leanchecker ∈ ks ∧ ∃ k ∈ ks, FvapiSpec.Policy.Independent k

end FvapiSpec.Profile
