import TestsU2.PolicyApi
import TestsU2.PolicyCases

open TestsU2

def suites : List (String × IO Unit) :=
  [("controls", PolicyCases.namedControls PolicyApi.pass),
   ("features", PolicyCases.featureBoundaries PolicyApi.pass),
   ("differential", PolicyCases.differential PolicyApi.pass),
   ("accepting", PolicyCases.reporting PolicyApi.accepting)]

/-- Runs the named suite (or all), printing each one's wall-clock; rc 1 = a failed case. -/
def main (args : List String) : IO UInt32 := do
  let selected := match args with
    | [] | ["all"] => suites
    | [name] => suites.filter (·.1 == name)
    | _ => []
  if selected.isEmpty then
    IO.eprintln "usage: fvapi-tests-u2 [differential|controls|features|accepting|all]"
    return 2
  try
    for (name, suite) in selected do
      let t0 ← IO.monoMsNow
      suite
      IO.println s!"{name}: {(← IO.monoMsNow) - t0} ms"
    return 0
  catch e =>
    IO.eprintln e.toString
    return 1
