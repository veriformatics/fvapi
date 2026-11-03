import Fvapi.Verify.Profile

namespace Fvapi.Verify.Replay

/-- The deadline flag comes from the supervisor. A missing capture is malformed (crash);
a matched blank capture stays a decline fact, whose inadmissibility P1 judges. -/
def adaptStatus (spec : KernelSpec) (rc : Option Nat) (timedOut : Bool)
    (stderr : String) : KernelStatus × Option String :=
  if timedOut then (.timeout, none)
  else match rc with
  | none => (.crash, none)
  | some rc =>
    if rc > 128 then (.crash, none)
    else match spec.statusMap.lookup rc with
    | some .accept => (.accept, none)
    | some .reject =>
      if (spec.crashPattern.bind (Regex.search · stderr)).isSome then (.crash, none)
      else (.reject, none)
    | some .decline =>
      if (spec.crashPattern.bind (Regex.search · stderr)).isSome then (.crash, none)
      else match spec.declinePattern.bind (Regex.search · stderr) with
      | none => (.crash, some "unnamed_unsupported")
      | some feature => (.decline feature,
          if feature.trimAscii.isEmpty then some "unnamed_unsupported" else none)
    | none => (.crash, none)

def mapStatus (spec : KernelSpec) (rc : Option Nat) (timedOut : Bool)
    (stderr : String) : KernelStatus :=
  (adaptStatus spec rc timedOut stderr).1

/-- The comparator pins these messages through its source hash; other failures are errors. -/
def comparatorCause (rc : Option Nat) (timedOut : Bool) (stderr : String) : Option String :=
  if !timedOut && rc == some 0 then none
  else if timedOut || rc.isNone || (rc.getD 255) ≥ 128 then some "comparator_error"
  else if Read.hasPlaceholder stderr "Illegal axiom detected:" then some "forbidden_axiom"
  else if ["Const does not match between challenge and target",
      "Challenge and solution theorem statement do not match:",
      "Challenge and solution constant kind don't match:"].any (Read.hasPlaceholder stderr) then
    some "challenge_mismatch"
  else some "comparator_error"

structure Facts where
  setupCauses : List String := []
  snapshotOk : Bool := true
  exportsOk : Bool := true
  comparatorCause : Option String := none

/-- Complete, unique coverage is independent of the acceptance policy's facts. -/
def complete (expected : List KernelId) (rs : List KernelResult) : Bool :=
  decide (rs.map (·.kernel)).Nodup &&
    expected.all (fun k => rs.any (·.kernel == k)) && rs.all (fun r => expected.contains r.kernel)

/-- Facts collected by IO → explicit causes + P1's verdict. A missing stage never passes. -/
def judge (expected : List KernelId) (facts : Facts) (rs : List KernelResult) :
    List String × Verdict := Id.run do
  let mut causes := facts.setupCauses
  unless facts.snapshotOk do causes := causes ++ ["challenge_mismatch"]
  unless facts.exportsOk do causes := causes ++ ["export_failed"]
  if let some cause := facts.comparatorCause then causes := causes ++ [cause]
  unless complete expected rs do causes := causes ++ ["kernel_missing"]
  for r in rs do
    match r.status with
    | .reject => causes := causes ++ ["kernel_rejected"]
    | .crash => causes := causes ++ ["kernel_crashed"]
    | .timeout => causes := causes ++ ["kernel_timeout"]
    | .decline feature =>
      if feature.trimAscii.isEmpty then causes := causes ++ ["unnamed_unsupported"]
    | .accept => pure ()
  unless rs.any (fun r => r.kernel == .leanchecker && accepted r) &&
      rs.any (fun r => r.kernel.lineage != .lean && accepted r) do
    causes := causes ++ ["insufficient_independent_kernels"]
  let result := Fvapi.Verify.verdict rs
  return (causes.eraseDups, if causes.isEmpty && result == .pass then .pass else .fail)

end Fvapi.Verify.Replay
