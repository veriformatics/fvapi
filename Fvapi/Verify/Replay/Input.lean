import Fvapi.Verify.Host

namespace Fvapi.Verify.Replay

open Fvapi.Json

structure Options where
  packagePath : System.FilePath
  inventoryPath : System.FilePath
  profilePath : System.FilePath
  expectedSource : System.FilePath
  axioms : List String
  json : Bool := false

structure Claim where
  id : String
  name : String
  proof : String
  proofModule : String
  claimModule : String
  proofRoot : String
  expectedSnapshot : String

structure Inventory where
  claims : List Claim
  roots : List String

def readJson (path : System.FilePath) : IO Value := do
  match decode (← IO.FS.readBinFile path) with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{path}: {repr e}"

/-- Names cross both a module path and generated Lean source; quote each validated component. -/
def safeName (s : String) : Bool :=
  !s.isEmpty && (s.splitOn ".").all fun part =>
    !part.isEmpty && part.all (fun c => c.isAlphanum || c == '_' || c == '\'') &&
      !(part.toList.head?.getD '0').isDigit

def quotedName (s : String) : String :=
  ".".intercalate ((s.splitOn ".").map fun part => "«" ++ part ++ "»")

def modulePath (s : String) : String := s.replace "." "/" ++ ".lean"

def readInventory (v : Value) : Read Inventory := do
  let ms ← Read.members "inventory" v
  unless (← Read.nat "inventory.version" (← Read.get "inventory" ms "version")) == 1 do
    throw ⟨"inventory.version", "not schema 1"⟩
  let roots ← Read.strs "production_roots" (← Read.get "inventory" ms "production_roots")
  let audit ← Read.strs "audit_roots" (← Read.get "inventory" ms "audit_roots")
  unless !roots.isEmpty && !audit.isEmpty && (roots ++ audit).all safeName do
    throw ⟨"inventory.roots", "need nonempty module names"⟩
  let .arr rows ← Read.get "inventory" ms "claims" |
    throw ⟨"inventory.claims", "not an array"⟩
  unless !rows.isEmpty do throw ⟨"inventory.claims", "inventory is empty"⟩
  let claims ← rows.mapM fun row => do
    let ms ← Read.members "claim" row
    let get (key : String) : Read String := do Read.str key (← Read.get "claim" ms key)
    let c : Claim := {
      id := ← get "id", name := ← get "claim", proof := ← get "proof"
      proofModule := ← get "proof_module", claimModule := ← get "claim_module"
      proofRoot := ← get "proof_root", expectedSnapshot := ← get "expected_snapshot" }
    unless !c.id.isEmpty && [c.name, c.proof, c.proofModule, c.claimModule, c.proofRoot].all
        safeName do throw ⟨"inventory.claim", "invalid claim or module name"⟩
    return c
  return ⟨claims, (roots ++ audit).eraseDups⟩

structure Frozen where
  files : List (String × String)
  identity : String

/-- Snapshot files are regular source inputs; links cannot add a second mutable tree. -/
partial def sourceFiles (root : System.FilePath) : IO (List String) := do
  let rec walk (rel : String) (files : List String) : IO (List String) := do
    let mut files := files
    for e in ← (root / rel).readDir do
      let r := if rel.isEmpty then e.fileName else rel ++ "/" ++ e.fileName
      match (← e.path.symlinkMetadata).type with
      | .dir => files ← walk r files
      | .file => files := r :: files
      | _ => throw <| IO.userError s!"snapshot contains a non-regular input: {r}"
    return files
  return (← walk "" []).mergeSort (· < ·)

def freeze (root : System.FilePath) : IO Frozen := do
  let files ← (← sourceFiles root).mapM fun (rel : String) => do
    return (rel, Hash.hex (← Hash.sha256File (root / rel)))
  let text := String.join (files.map fun (rel, hash) => s!"{hash}  {rel}\n")
  return ⟨files, "sha256:" ++ Hash.hex (Hash.sha256 text.toUTF8)⟩

def unchanged (root : System.FilePath) (frozen : Frozen) (exact : Bool) : IO Bool := do
  if exact && (← sourceFiles root) != frozen.files.map (·.1) then return false
  for (rel, hash) in frozen.files do
    if Hash.hex (← Hash.sha256File (root / rel)) != hash then return false
  return true

private def safeRelative (rel : String) : Bool :=
  !rel.isEmpty && !(rel.startsWith "/") && !rel.contains '\\' && !rel.contains '\x00' &&
    (rel.splitOn "/").all (fun p => !p.isEmpty && p != "." && p != "..")

/-- The caller supplied this directory independently; validate its manifest before any build. -/
def snapshot (root : System.FilePath) (claims : List Claim) : IO (String × Frozen) := do
  let raw ← IO.FS.readBinFile (root / "snapshot.json")
  let identity := "sha256:" ++ Hash.hex (Hash.sha256 raw)
  unless claims.all (·.expectedSnapshot == identity) do
    throw <| IO.userError "expected_snapshot does not name the supplied snapshot"
  let manifest ← readJson (root / "snapshot.json")
  let ms ← IO.ofExcept <| (Read.members "snapshot" manifest).mapError reprStr
  let version ← IO.ofExcept <|
    (Read.nat "snapshot.version" (← IO.ofExcept <|
      (Read.get "snapshot" ms "version").mapError reprStr)).mapError reprStr
  unless version == 1 do throw <| IO.userError "snapshot version is not 1"
  let files ← IO.ofExcept <|
    (Read.get "snapshot" ms "files" >>= Read.members "snapshot.files").mapError reprStr
  unless !files.isEmpty do throw <| IO.userError "snapshot has no files"
  for (rel, value) in files do
    unless safeRelative rel do throw <| IO.userError s!"invalid snapshot path: {rel}"
    let hash ← IO.ofExcept <| (Read.sha256 s!"snapshot.files.{rel}" value).mapError reprStr
    unless Hash.hex (← Hash.sha256File (root / rel)) == hash do
      throw <| IO.userError s!"snapshot byte mismatch: {rel}"
  let frozen ← freeze root
  for (rel, _) in frozen.files do
    if rel.startsWith "FvapiProof/" || rel == "FvapiProofs.lean" then
      throw <| IO.userError "expected-source holds proof implementations"
  return (identity, frozen)

def materialize (source target : System.FilePath) (frozen : Frozen)
    (claims : List Claim) : IO Frozen := do
  for (rel, _) in frozen.files do
    let dest := target / rel
    if let some parent := dest.parent then IO.FS.createDirAll parent
    IO.FS.writeBinFile dest (← IO.FS.readBinFile (source / rel))
  let modules := (claims.map (·.proofModule)).eraseDups
  for module in modules do
    let group := claims.filter (·.proofModule == module)
    let imports := (group.map (·.claimModule)).eraseDups.map fun m =>
      "import " ++ quotedName m ++ "\n"
    let stubs := group.map fun c =>
      s!"set_option warningAsError false in\ntheorem {quotedName c.proof} : " ++
        s!"{quotedName c.name} := by sorry\n"
    let dest := target / modulePath module
    if let some parent := dest.parent then IO.FS.createDirAll parent
    IO.FS.writeFile dest (String.join imports ++ "\n" ++ String.join stubs)
  for root in (claims.map (·.proofRoot)).eraseDups do
    let imports := (claims.filter (·.proofRoot == root)).map (·.proofModule) |>.eraseDups
    IO.FS.writeFile (target / modulePath root)
      (String.join (imports.map fun m => "import " ++ quotedName m ++ "\n"))
  freeze target

end Fvapi.Verify.Replay
