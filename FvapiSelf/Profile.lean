import FvapiSpec.Profile

namespace FvapiSelf.Profile

open Fvapi.Verify

/-- `runSetOk` admits exactly the run sets the reviewed rule admits, per scope. -/
def RunSetExact : Prop :=
  ∀ (s : Scope) (ks : List KernelId), runSetOk s ks = true ↔ FvapiSpec.Profile.RunSetOk s ks

end FvapiSelf.Profile
