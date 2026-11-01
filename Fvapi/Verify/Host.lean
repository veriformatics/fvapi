import Fvapi.Verify.Profile

/-! Host identity for a verification profile (`docs/contracts/U2-trust.md` P2): the pinned
executables, the comparator source + its fixed target set, and the toolchain runtime manifest
match what this host would execute. Mirrors `tools/check-profile.sh` (the gate's stage). -/

namespace Fvapi.Verify

open Fvapi.Json

/-- The toolchain root (`lean --print-prefix`): `{lean_prefix}` in a profile. -/
def leanPrefix : IO System.FilePath := do
  let out ← IO.Process.output { cmd := "lean", args := #["--print-prefix"] }
  if out.exitCode != 0 then
    throw <| IO.userError s!"lean --print-prefix failed: {out.stderr.trimAscii}"
  return out.stdout.trimAscii.toString

/-- The installed toolchain as a profile names it: `lean --version` = `Lean (version 4.35.0, …)`
→ `leanprover/lean4:v4.35.0`. -/
def leanToolchain : IO String := do
  let out ← IO.Process.output { cmd := "lean", args := #["--version"] }
  let some rest := (out.stdout.splitOn "version ")[1]?
    | throw (IO.userError s!"lean --version: unexpected output {out.stdout.trimAscii}")
  return "leanprover/lean4:v" ++ String.ofList (rest.toList.takeWhile (· != ','))

def resolve (pre : System.FilePath) (exe : String) : System.FilePath :=
  exe.replace "{lean_prefix}" pre.toString

/-- `field` names the pin's sha256; a missing or unreadable file is a problem too. -/
def checkPinned (pre : System.FilePath) (field : String) (p : Pinned) : IO (List Problem) := do
  let path := resolve pre p.executable
  match ← (Hash.sha256File path).toBaseIO with
  | .error e => return [⟨field, s!"{path}: {e}"⟩]
  | .ok d =>
    let got := Hash.hex d
    return if got == p.sha256 then [] else [⟨field, s!"{path} sha256 {got} != profile {p.sha256}"⟩]

/-- The comparator's fixed targets as `Lake/CLI/Check.lean` lists them: the backquoted names of
`primitiveTargets`, then each ``` ``Quot… ``` name of `builtinTargets` except `Quot.sound` (an
axiom the allowlist decides). Same rule as `tools/check-profile.sh`. -/
def comparatorTargets (source : String) : List String :=
  let lines := source.splitOn "\n"
  let afterDef (name : String) := lines.dropWhile (!·.startsWith s!"def {name}")
  let primitive := (afterDef "primitiveTargets").drop 1
    |>.takeWhile (fun l => !(l.trimAsciiStart.startsWith "]"))
    |>.filterMap fun l =>
      let t := l.trimAsciiStart.toString
      if t.startsWith "``" then some ((t.drop 2).toString.replace "," "" |>.trimAscii.toString)
      else none
  let builtin := (afterDef "builtinTargets").takeWhile (· != "")
    |>.flatMap fun l => (l.splitOn "``").drop 1 |>.filterMap fun piece =>
      let name := String.ofList (piece.toList.takeWhile fun c => c.isAlpha || c == '.')
      if name.startsWith "Quot" && name != "Quot.sound" then some name else none
  (primitive ++ builtin).eraseDups

/-- Regular files under `dir` (lstat: symlinks are neither followed nor listed), as paths
relative to `dir`, sorted by bytes — `find . -type f | LC_ALL=C sort`. -/
partial def regularFiles (dir : System.FilePath) : IO (Array String) := do
  let rec walk (rel : String) (acc : Array String) : IO (Array String) := do
    let mut acc := acc
    for e in ← (dir / rel).readDir do
      let r := if rel.isEmpty then e.fileName else rel ++ "/" ++ e.fileName
      match (← e.path.symlinkMetadata).type with
      | .dir => acc ← walk r acc
      | .file => acc := acc.push r
      | _ => pure ()
    return acc
  return (← walk "" #[]).qsort (· < ·)

/-- The runtime manifest digest: SHA-256 over `sha256sum`'s lines (`<hex>  ./<path>`) for every
regular file of the toolchain, in byte order (`runtime.rule`). -/
def runtimeDigest (pre : System.FilePath) : IO String := do
  let mut s := Hash.Sha256.init
  for rel in ← regularFiles pre do
    let line := s!"{Hash.hex (← Hash.sha256File (pre / rel))}  ./{rel}\n"
    s := Hash.Sha256.update s line.toUTF8
  return Hash.hex (Hash.Sha256.finish s)

/-- Every host-identity problem of `p`: kernel, exporter + comparator bytes, the comparator
source + target set; the runtime manifest when `runtime` (≈ 18k files: callers opt in). -/
def checkHost (pre : System.FilePath) (p : Profile) (runtime : Bool) : IO (List Problem) := do
  let mut problems := []
  let installed ← leanToolchain
  if p.toolchain != installed then
    problems := problems ++ [⟨"toolchain", s!"{p.toolchain} != installed {installed}"⟩]
  for (k, i) in p.kernels.zipIdx do
    problems := problems ++ (← checkPinned pre s!"kernels[{i}].sha256" k.pinned)
  problems := problems ++ (← checkPinned pre "exporter.sha256" p.exporter)
  problems := problems ++ (← checkPinned pre "comparator.sha256" p.comparator)
  let src := pre / p.comparatorSource
  match ← (IO.FS.readFile src).toBaseIO with
  | .error e => problems := problems ++ [⟨"comparator.source", s!"{src}: {e}"⟩]
  | .ok text =>
    let got := Hash.hex (Hash.sha256 text.toUTF8)
    if got != p.comparatorSourceSha256 then
      problems := problems ++
        [⟨"comparator.source_sha256", s!"{src} sha256 {got} != profile {p.comparatorSourceSha256}"⟩]
    let parsed := comparatorTargets text
    let listed := p.comparatorTargets.eraseDups
    unless !parsed.isEmpty && parsed.all listed.contains && listed.all parsed.contains do
      problems := problems ++
        [⟨"comparator.targets", s!"{listed} != installed source {parsed}"⟩]
  if runtime then
    let got ← runtimeDigest pre
    if got != p.runtimeSha256 then
      problems := problems ++ [⟨"runtime.sha256", s!"{got} != profile {p.runtimeSha256}"⟩]
  return problems

end Fvapi.Verify
