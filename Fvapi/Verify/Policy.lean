namespace Fvapi.Verify

/-- The kernels a verification profile may name (`docs/contracts/U2-trust.md` P1). -/
inductive KernelId where
  | leanchecker
  | leancheckerParanoid
  | lean4lean
  | nanoda
  | conLeche
  | conRon
  deriving DecidableEq, Repr

/-- Implementation families: Lean's kernel, its modes + the port derived from it, are one. -/
inductive Lineage where
  | lean
  | nanoda
  | con
  deriving DecidableEq, Repr

def KernelId.lineage : KernelId → Lineage
  | .leanchecker | .leancheckerParanoid | .lean4lean => .lean
  | .nanoda => .nanoda
  | .conLeche | .conRon => .con

def KernelId.name : KernelId → String
  | .leanchecker => "leanchecker"
  | .leancheckerParanoid => "leanchecker-paranoid"
  | .lean4lean => "lean4lean"
  | .nanoda => "nanoda"
  | .conLeche => "con-leche"
  | .conRon => "con-ron"

inductive KernelStatus where
  | accept
  | reject
  | decline (feature : String)
  | crash
  | timeout
  deriving DecidableEq, Repr

structure KernelResult where
  kernel : KernelId
  status : KernelStatus
  deriving DecidableEq, Repr

inductive Verdict where
  | pass
  | fail
  deriving DecidableEq, Repr

/-- Neither a failure nor an unnamed decline: accept, or a decline naming a nonblank feature. -/
def KernelStatus.admissible : KernelStatus → Bool
  | .accept => true
  | .decline feature => !feature.trimAscii.isEmpty
  | .reject | .crash | .timeout => false

def accepted (r : KernelResult) : Bool := r.status == .accept

/-- `Answer guarantee`: Lean's default kernel + a kernel of another lineage accept, and every
result is admissible. Run-set completeness is the replay's check, not this function's. -/
def verdict (rs : List KernelResult) : Verdict :=
  if rs.any (fun r => r.kernel == .leanchecker && accepted r) &&
      rs.any (fun r => r.kernel.lineage != .lean && accepted r) &&
      rs.all (fun r => r.status.admissible) then .pass
  else .fail

/-- The accepting kernels, once each, in profile order. -/
def accepting (order : List KernelId) (rs : List KernelResult) : List KernelId :=
  order.filter fun k => rs.any fun r => r.kernel == k && accepted r

end Fvapi.Verify
