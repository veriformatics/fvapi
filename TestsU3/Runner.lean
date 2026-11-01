import TestsU3.JsonSuite
import TestsU3.HashSuite

namespace TestsU3.Runner

private def runSuite (json : JsonApi) (hash : HashApi) (name : String)
    (dir : System.FilePath) : IO Nat := do
  match name with
  | "T1" | "T2" | "T3" | "T4" | "T5" | "T6" => JsonSuite.corpus json dir name
  | "T7" => JsonSuite.laws json
  | "T9" => HashSuite.nist hash dir
  | "T10" => HashSuite.differential hash dir
  | _ => throw (IO.userError s!"setup: bad suite {name}")

private def run (json : JsonApi) (hash : HashApi) (args : List String) : IO Unit := do
  match args with
  | ["resource", kind, size, mode] =>
    let some n := size.toNat? | throw (IO.userError "setup: resource size")
    JsonSuite.resource json kind n mode
  | [name, dir] =>
    let selected := if name == "all" then
        ["T1", "T2", "T3", "T4", "T5", "T6", "T7", "T9", "T10"]
      else [name]
    for suite in selected do
      let start ← IO.monoMsNow
      let count ← runSuite json hash suite dir
      IO.println s!"{suite}: {count} cases/properties; {(← IO.monoMsNow) - start} ms"
  | _ => throw (IO.userError
      "setup: usage: fvapi-tests-u3 SUITE CORPUS_DIR | resource KIND N MODE")

def main (json : JsonApi) (hash : HashApi) (args : List String) : IO UInt32 := do
  try
    let normalized := match args with
      | [] => ["all", ".lake/tests-u3"]
      | [name] => [name, ".lake/tests-u3"]
      | xs => xs
    run json hash normalized
    return 0
  catch e =>
    let message := e.toString
    IO.eprintln message
    if (message.splitOn "assertion:").length > 1 then return 1
    else if (message.splitOn "setup:").length > 1 then return 2
    else return 3

end TestsU3.Runner
