import Fvapi

open Fvapi.Cli
open Fvapi.Verify

/-- One case: its name, whether it held, and its wall-clock in milliseconds. -/
structure Outcome where
  name : String
  ok : Bool
  ms : Nat

def check (name : String) (ok : Unit → Bool) : IO Outcome := do
  let t0 ← IO.monoMsNow
  let held := ok ()
  let t1 ← IO.monoMsNow
  IO.println s!"{if held then "PASS" else "FAIL"} {name}"
  return ⟨name, held, t1 - t0⟩

/-- Prints PASS|FAIL per case, then the slowest case; exits with the failure count. -/
def main : IO UInt32 := do
  let results ← [
    check "cli: --version prints the version on stdout, rc 0" fun _ =>
      dispatch ["--version"] == ⟨.stdout, s!"fvapi {Fvapi.version}\n", 0⟩,
    check "cli: help + --help print usage on stdout, rc 0" fun _ =>
      dispatch ["help"] == ⟨.stdout, usage, 0⟩ && dispatch ["--help"] == ⟨.stdout, usage, 0⟩,
    check "cli: no argument prints usage on stderr, rc 2" fun _ =>
      dispatch [] == ⟨.stderr, usage, 2⟩,
    check "cli: an unknown command prints usage on stderr, rc 2" fun _ =>
      dispatch ["frobnicate"] == ⟨.stderr, usage, 2⟩ &&
        dispatch ["--version", "x"] == ⟨.stderr, usage, 2⟩
    -- Kernel policy controls (docs/contracts/U2-trust.md P1).
  , check "policy: leanchecker accept + five valid declines fails (no independent accept)" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.leancheckerParanoid, .decline "f"⟩,
        ⟨.lean4lean, .decline "f"⟩, ⟨.nanoda, .decline "f"⟩, ⟨.conLeche, .decline "f"⟩,
        ⟨.conRon, .decline "f"⟩] == .fail,
    check "policy: the three lean-lineage kernels accept + three valid declines fails" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.leancheckerParanoid, .accept⟩, ⟨.lean4lean, .accept⟩,
        ⟨.nanoda, .decline "f"⟩, ⟨.conLeche, .decline "f"⟩, ⟨.conRon, .decline "f"⟩] == .fail,
    check "policy: leanchecker accept + nanoda accept passes" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩] == .pass,
    check "policy: missing leanchecker fails" fun _ =>
      verdict [⟨.nanoda, .accept⟩, ⟨.conLeche, .accept⟩] == .fail,
    check "policy: any timeout, crash or reject fails" fun _ =>
      [KernelStatus.timeout, .crash, .reject].all fun s =>
        verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩, ⟨.conRon, s⟩] == .fail,
    check "policy: empty result list fails" fun _ => verdict [] == .fail,
    check "policy: a blank or whitespace decline feature fails" fun _ =>
      ["", " ", "\t "].all fun f =>
        verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩, ⟨.conRon, .decline f⟩] == .fail,
    check "policy: accepting lists accepting kernels once each, in profile order" fun _ =>
      accepting [.conRon, .leanchecker, .nanoda]
        [⟨.nanoda, .accept⟩, ⟨.leanchecker, .accept⟩, ⟨.conRon, .decline "x"⟩] ==
        [.leanchecker, .nanoda]
  ].mapM id
  let failed := (results.filter (!·.ok)).length
  match results.foldl (fun acc r => if r.ms ≥ acc.ms then r else acc) ⟨"", true, 0⟩ with
  | slowest => IO.println s!"slowest: {slowest.name} ({slowest.ms} ms)"
  IO.println s!"tests: {results.length - failed} passed, {failed} failed"
  return failed.toUInt32
