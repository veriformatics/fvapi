import Std

namespace TestsU2.Oracle

inductive Kernel where
  | leanchecker | leancheckerParanoid | lean4lean | nanoda | conLeche | conRon
  deriving BEq, DecidableEq, Repr

inductive Status where
  | accept | reject | decline (feature : String) | crash | timeout
  deriving BEq, DecidableEq, Repr

structure Fact where
  kernel : Kernel
  status : Status
  deriving BEq, DecidableEq, Repr

def kernels : List Kernel :=
  [.leanchecker, .leancheckerParanoid, .lean4lean, .nanoda, .conLeche, .conRon]

def statuses : List Status :=
  [.accept, .reject, .decline "", .decline " ", .decline "x", .crash, .timeout]

/-- Independent vocabulary: the oracle imports only Std. -/
def independent : Kernel → Bool
  | .nanoda | .conLeche | .conRon => true
  | _ => false

def nonblank (feature : String) : Bool :=
  feature.toList.any fun c =>
    !(c == ' ' || c == '\t' || c == '\n' || c == '\r')

def harmless : Status → Bool
  | .accept => true
  | .decline feature => nonblank feature
  | _ => false

/-- P1: duplicate/omitted facts remain facts; completeness belongs to P3. -/
def Pass (rs : List Fact) : Prop :=
  rs.any (fun r => r.kernel == .leanchecker && r.status == .accept) = true ∧
  rs.any (fun r => independent r.kernel && r.status == .accept) = true ∧
  rs.all (fun r => harmless r.status) = true

instance (rs : List Fact) : Decidable (Pass rs) := inferInstanceAs (Decidable (_ ∧ _ ∧ _))

def pass (rs : List Fact) : Bool := decide (Pass rs)

/-- Stable first occurrence in profile order; result-list order is immaterial. -/
def accepting (profileOrder : List Kernel) (rs : List Fact) : List Kernel := Id.run do
  let mut seen : List Kernel := []
  for kernel in profileOrder do
    if !seen.contains kernel && rs.any (fun r => r.kernel == kernel && r.status == .accept) then
      seen := seen ++ [kernel]
  return seen

end TestsU2.Oracle
