import Fvapi

open Fvapi.Cli

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
  ].mapM id
  let failed := (results.filter (!·.ok)).length
  match results.foldl (fun acc r => if r.ms ≥ acc.ms then r else acc) ⟨"", true, 0⟩ with
  | slowest => IO.println s!"slowest: {slowest.name} ({slowest.ms} ms)"
  IO.println s!"tests: {results.length - failed} passed, {failed} failed"
  return failed.toUInt32
