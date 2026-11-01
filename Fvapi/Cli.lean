import Fvapi.Version
import Fvapi.Dev

namespace Fvapi.Cli

inductive Stream where
  | stdout
  | stderr
  deriving DecidableEq, Repr

/-- What one invocation prints and returns; `run` performs it, tests inspect it. -/
structure Reply where
  stream : Stream
  text : String
  code : UInt32
  deriving DecidableEq, Repr

def usage : String :=
  "usage: fvapi <command>\n\n" ++
  "commands:\n" ++
  "  --version   Print the version.\n" ++
  "  help        Print this help.\n"

/-- Exit codes follow `docs/api.md`: 0 success, 2 usage. -/
def dispatch : List String → Reply
  | ["--version"] => ⟨.stdout, s!"fvapi {version}\n", 0⟩
  | ["help"] | ["--help"] => ⟨.stdout, usage, 0⟩
  | _ => ⟨.stderr, usage, 2⟩

def run (args : List String) : IO UInt32 := do
  if let "dev" :: rest := args then return ← Fvapi.Dev.run rest
  let r := dispatch args
  match r.stream with
  | .stdout => IO.print r.text
  | .stderr => IO.eprint r.text
  return r.code

end Fvapi.Cli
