import Fvapi.Verify.Policy
import TestsU2.Oracle

namespace TestsU2.PolicyApi

private def kernel : Oracle.Kernel → Fvapi.Verify.KernelId
  | .leanchecker => .leanchecker
  | .leancheckerParanoid => .leancheckerParanoid
  | .lean4lean => .lean4lean
  | .nanoda => .nanoda
  | .conLeche => .conLeche
  | .conRon => .conRon

private def status : Oracle.Status → Fvapi.Verify.KernelStatus
  | .accept => .accept
  | .reject => .reject
  | .decline feature => .decline feature
  | .crash => .crash
  | .timeout => .timeout

private def facts (rs : List Oracle.Fact) : List Fvapi.Verify.KernelResult :=
  rs.map fun r => { kernel := kernel r.kernel, status := status r.status }

def pass (rs : List Oracle.Fact) : Bool :=
  match Fvapi.Verify.verdict (facts rs) with
  | .pass => true
  | .fail => false

def accepting (order : List Oracle.Kernel) (rs : List Oracle.Fact) : List Oracle.Kernel :=
  let observed := Fvapi.Verify.accepting (order.map kernel) (facts rs)
  observed.map fun k => match k with
    | .leanchecker => .leanchecker
    | .leancheckerParanoid => .leancheckerParanoid
    | .lean4lean => .lean4lean
    | .nanoda => .nanoda
    | .conLeche => .conLeche
    | .conRon => .conRon

end TestsU2.PolicyApi
