import Fvapi.Verify.Policy

/-! Reviewed vocabulary for the kernel policy (`Decisions` → `Answer guarantee`), stated apart
from the implementation's `lineage` + `admissible`. -/

namespace FvapiSpec.Policy

open Fvapi.Verify

/-- A kernel of another implementation than Lean's own kernel (lineage ≠ `lean`). -/
def Independent : KernelId → Prop
  | .nanoda | .conLeche | .conRon => True
  | .leanchecker | .leancheckerParanoid | .lean4lean => False

def Pass (rs : List KernelResult) : Prop :=
  (∃ r ∈ rs, r.kernel = .leanchecker ∧ r.status = .accept) ∧
  (∃ r ∈ rs, Independent r.kernel ∧ r.status = .accept) ∧
  (∀ r ∈ rs, r.status ≠ .reject ∧ r.status ≠ .crash ∧ r.status ≠ .timeout ∧
    ∀ feature, r.status = .decline feature → feature.trimAscii.isEmpty = false)

end FvapiSpec.Policy
