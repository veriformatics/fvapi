import Fvapi.Verify.Policy
import FvapiSpec.Policy

namespace FvapiSelf.Policy

open Fvapi.Verify

/-- `verdict` passes exactly the result lists the reviewed policy passes. -/
def PolicyExact : Prop := ∀ rs, verdict rs = .pass ↔ FvapiSpec.Policy.Pass rs

/-- `accepting` names exactly the ordered kernels that reported `accept`. -/
def AcceptingExact : Prop :=
  ∀ order rs k, k ∈ accepting order rs ↔ (k ∈ order ∧ ∃ r ∈ rs, r.kernel = k ∧ r.status = .accept)

end FvapiSelf.Policy
