import Fvapi.Verify.Host

/-! Developer commands (`fvapi dev …`): fvapi's own verification tooling, outside the public
CLI surface of `docs/api.md`. Exit codes: 0 valid / pass, 1 invalid / fail, 2 usage. -/

namespace Fvapi.Dev

open Fvapi.Json Fvapi.Verify

def usage : String :=
  "usage: fvapi dev profile --profile FILE --scope caller|service [--runtime] [--json]\n"

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

/-- Flags in any order: `--profile FILE`, `--scope caller|service`, `--runtime`, `--json`. -/
def run : List String → IO UInt32
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
