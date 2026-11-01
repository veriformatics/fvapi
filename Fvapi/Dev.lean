import Fvapi.Verify.Replay

/-! Developer commands (`fvapi dev …`): fvapi's own verification tooling, outside the public
CLI surface of `docs/api.md`. Exit codes: 0 valid / pass, 1 invalid / fail, 2 usage. -/

namespace Fvapi.Dev

open Fvapi.Json Fvapi.Verify

def usage : String :=
  "usage: fvapi dev profile --profile FILE --scope caller|service [--runtime] [--json]\n" ++
  "       fvapi dev replay --package DIR --inventory FILE --profile FILE " ++
    "--expected-source DIR --axioms a,b,c [--json]\n"

/-- One JSON record (canonical text) or a human line, on stdout. -/
def report (json : Bool) (record : Value) (human : String) : IO Unit :=
  if json then IO.println (String.fromUTF8! (print record)) else IO.println human

/-- `dev profile`: the profile parses (schema 1, id rule), its run set fits `scope`, and its
pinned bytes match this host (`--runtime` adds the ≈ 18k-file runtime manifest). -/
def profile (path : System.FilePath) (scope : Scope) (runtime json : Bool) : IO UInt32 := do
  let fail (problems : List Problem) : IO UInt32 := do
    report json (.object [("valid", .bool false), ("error", .str "profile_mismatch"),
        ("diagnostics", .arr (problems.map Problem.toJson))])
      ("profile invalid:\n" ++ "\n".intercalate (problems.map fun p => s!"  {p.field}: {p.detail}"))
    return 1
  let bytes ← match ← (IO.FS.readBinFile path).toBaseIO with
    | .ok b => pure b
    | .error e => return ← fail [⟨"(file)", s!"{path}: {e}"⟩]
  let v ← match decode bytes with
    | .ok v => pure v
    | .error e => return ← fail [⟨"(file)", s!"not a profile JSON text: {repr e}"⟩]
  match checkProfile scope v with
  | .error p => fail [p]
  | .ok p =>
    let problems ← checkHost (← leanPrefix) p runtime
    unless problems.isEmpty do return ← fail problems
    report json (.object [("valid", .bool true), ("id", .str p.id),
        ("scope", .str (match scope with | .caller => "caller" | .service => "service")),
        ("kernels", .arr (p.kernels.map fun k => .str k.id.name)),
        ("runtime", .str (if runtime then "checked" else "not_checked"))])
      s!"profile valid: {p.id}"
    return 0

/-- Replay takes its challenge and allowlist independently of the package under test. -/
def replayFlags (args : List String) : Option Replay.Options := do
  let rec flags (fields : List (String × String)) (json : Bool) :
      List String → Option (List (String × String) × Bool)
    | [] => some (fields, json)
    | "--json" :: rest => flags fields true rest
    | key :: value :: rest =>
      if ["--package", "--inventory", "--profile", "--expected-source", "--axioms"].contains key &&
          !value.startsWith "--" && !(fields.any (·.1 == key)) then
        flags ((key, value) :: fields) json rest
      else none
    | _ => none
  let (fields, json) ← flags [] false args
  let axioms ← fields.lookup "--axioms"
  let axioms := if axioms.isEmpty then [] else axioms.splitOn ","
  unless axioms.all Replay.safeName do none
  return {
    packagePath := ← fields.lookup "--package"
    inventoryPath := ← fields.lookup "--inventory", profilePath := ← fields.lookup "--profile"
    expectedSource := ← fields.lookup "--expected-source", axioms, json }

/-- Flags in any order; an unrecognized or incomplete invocation exits 2. -/
def run : List String → IO UInt32
  | "replay" :: rest => do
    match replayFlags rest with
    | none => IO.eprint usage; return 2
    | some opts =>
      let cwd ← IO.currentDir
      let absolute (p : System.FilePath) := if p.isAbsolute then p else cwd / p
      Replay.run { opts with
        packagePath := absolute opts.packagePath
        inventoryPath := absolute opts.inventoryPath
        profilePath := absolute opts.profilePath
        expectedSource := absolute opts.expectedSource }
  | "profile" :: rest => do
    let rec flags (file : Option String) (scope : Option Scope) (runtime json : Bool) :
        List String → Option (String × Scope × Bool × Bool)
      | [] => do return (← file, ← scope, runtime, json)
      | "--profile" :: f :: more => flags (some f) scope runtime json more
      | "--scope" :: "caller" :: more => flags file (some .caller) runtime json more
      | "--scope" :: "service" :: more => flags file (some .service) runtime json more
      | "--runtime" :: more => flags file scope true json more
      | "--json" :: more => flags file scope runtime true more
      | _ => none
    match flags none none false false rest with
    | some (file, scope, runtime, json) => profile file scope runtime json
    | none => do IO.eprint usage; return 2
  | _ => do IO.eprint usage; return 2

end Fvapi.Dev
