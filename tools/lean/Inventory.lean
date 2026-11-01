import Lean

/-! P4 elaboration checker; embedded unchanged in `fvapi dev replay`.
Usage: lake env lean --run Inventory.lean [claims.json] [obligations.md] -/

open Lean

structure Row where
  id : String
  domain : String
  claim : Name
  proof : Name
  specModule : Name
  claimModule : Name
  proofModule : Name
  proofRoot : Name
  subjects : Array Name
  callPaths : Array Name

structure Inventory where
  production : Array Name
  audit : Array Name
  rows : Array Row

def field (j : Json) (k : String) : Except String String := j.getObjValAs? String k

def names (j : Json) (k : String) : Except String (Array Name) :=
  (·.map String.toName) <$> j.getObjValAs? (Array String) k

def readInventory (path : System.FilePath) : IO Inventory := do
  let j ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  IO.ofExcept do
    unless (← j.getObjValAs? Nat "version") == 1 do throw "inventory version is not 1"
    let claims ← j.getObjValAs? (Array Json) "claims"
    let rows ← claims.mapM fun c => do
      let budget ← (c.getObjValAs? Nat "reviewed_surface_budget").mapError
        ("reviewed_surface_budget: " ++ ·)
      unless budget > 0 do throw "reviewed_surface_budget must be a positive integer"
      let snapshot ← field c "expected_snapshot"
      unless snapshot.startsWith "sha256:" && snapshot.length == 71 &&
          (snapshot.drop 7).toString.all (fun ch => ch.isDigit || ('a' ≤ ch && ch ≤ 'f')) do
        throw "expected_snapshot must be sha256: + 64 lowercase hex digits"
      return {
        id := ← field c "id", domain := ← field c "domain"
        claim := (← field c "claim").toName, proof := (← field c "proof").toName
        specModule := (← field c "spec_module").toName
        claimModule := (← field c "claim_module").toName
        proofModule := (← field c "proof_module").toName
        proofRoot := (← field c "proof_root").toName
        subjects := ← names c "audit_subjects", callPaths := ← names c "shipped_call_paths" }
    return { production := ← names j "production_roots", audit := ← names j "audit_roots", rows }

/-- Imports come from elaborated module metadata, including every transitive edge. -/
def closure (env : Environment) (roots : Array Name) : Array Name := Id.run do
  let mut seen := roots
  let mut head := 0
  for _ in [:env.header.moduleNames.size + roots.size] do
    if let some m := seen[head]? then
      head := head + 1
      if let some idx := env.getModuleIdx? m then
        for imp in env.header.moduleData[idx]!.imports do
          unless seen.contains imp.module do seen := seen.push imp.module
  return seen

/-- Source paths, not aggregate imports, determine which closed-claim modules exist. -/
partial def selfModules : IO (Array Name) := do
  let rec walk (path : System.FilePath) (modulePrefix : String) (acc : Array Name) :
      IO (Array Name) := do
    let mut acc := acc
    for entry in ← path.readDir do
      let name := modulePrefix ++ "." ++ entry.fileName
      match (← entry.path.symlinkMetadata).type with
      | .dir => acc ← walk entry.path name acc
      | .file =>
        if entry.path.extension == some "lean" then
          acc := acc.push ((name.dropEnd 5).toString.toName)
      | _ => throw <| IO.userError s!"inventory: non-regular Self input {entry.path}"
    return acc
  return (← walk "FvapiSelf" "FvapiSelf" #[]).qsort (·.toString < ·.toString)

/-- Includes inferred/aliased Prop and Prop-valued functions; the latter are not closed. -/
def propShape (env : Environment) (type : Expr) : IO (Bool × Bool) := do
  let action : MetaM (Bool × Bool) := Meta.forallTelescopeReducing type fun xs body => do
    return ((← Meta.whnf body) == .sort .zero, xs.isEmpty)
  Core.CoreM.toIO' action.run' { fileName := "inventory", fileMap := FileMap.ofString "" }
    { env }

def auditModule (m : Name) : Bool :=
  [`FvapiSpec, `FvapiSelf, `FvapiProof, `FvapiProofs].contains m.getRoot

def main (args : List String) : IO UInt32 := do
  let claimsPath := args.getD 0 "verify/claims.json"
  let matrixPath := args.getD 1 "docs/obligations.md"
  let inv ← readInventory claimsPath
  initSearchPath (← findSysroot)
  let roots := (inv.audit ++ inv.production).toList.eraseDups.toArray
  let self ← selfModules
  let modules := (roots ++ self).toList.eraseDups.toArray
  let env ← importModules (modules.map fun m => { module := m }) {}
  let matrix ← IO.FS.readFile matrixPath
  let table := (matrix.splitOn "\n").filter (·.trimAsciiStart.startsWith "|")
  let body := table.drop 2
  let cells := body.flatMap (·.splitOn "|")
  let namesCell (cell : String) (name : String) :=
    let cell := cell.trimAscii.toString
    cell == name || cell == s!"`{name}`"
  let mut errors : Array String := #[]
  let moduleOf (n : Name) : Option Name :=
    (env.getModuleIdxFor? n).map (env.header.moduleNames[·]!)
  let production := closure env inv.production
  let audit := closure env inv.audit
  if inv.rows.isEmpty then errors := errors.push "inventory is empty"
  if inv.production.isEmpty || inv.audit.isEmpty then
    errors := errors.push "production and audit roots must be nonempty"
  unless inv.production == #[`Fvapi, `Main] do
    errors := errors.push "production_roots must be exactly [Fvapi, Main]"
  unless inv.audit == #[`FvapiProofs] do
    errors := errors.push "audit_roots must be exactly [FvapiProofs]"
  for m in self do
    unless audit.contains m do
      errors := errors.push s!"aggregate proof root does not reach closed-claim module {m}"
  for m in production do
    if auditModule m then
      errors := errors.push s!"production import closure contains audit module {m}"
  for m in roots do
    if (env.getModuleIdx? m).isNone then errors := errors.push s!"unresolved root module {m}"
  let mut declared : Array Name := #[]
  for (n, ci) in env.constants.map₁.toList do
    if let some m := moduleOf n then
      if m.getRoot == `FvapiSelf then
        match ci with
        | .defnInfo d =>
          let (isProp, closed) ← propShape env d.type
          if isProp then
            declared := declared.push n
            if n.isInternal then errors := errors.push s!"{n}: claim declarations must be public"
            unless closed do errors := errors.push s!"{n}: claim is not closed"
            unless d.levelParams.isEmpty do
              errors := errors.push s!"{n}: claim is not universe-free"
          else errors := errors.push s!"{n}: helpers belong in FvapiSpec modules"
        | _ => errors := errors.push s!"{n}: closed-claim modules contain claim definitions alone"
  let listed := inv.rows.map (·.claim)
  for n in declared do
    let count := (listed.filter (· == n)).size
    if count != 1 then
      errors := errors.push s!"{n} is a closed claim with {count} inventory rows (want 1)"
  let ids := inv.rows.map (·.id)
  for r in inv.rows do
    if r.id.isEmpty || (ids.filter (· == r.id)).size != 1 then
      errors := errors.push s!"duplicate or empty id {r.id}"
    unless declared.contains r.claim do
      errors := errors.push s!"{r.id}: {r.claim} is not a Prop definition in an FvapiSelf module"
    if moduleOf r.claim != some r.claimModule then
      errors := errors.push s!"{r.id}: {r.claim} is not declared in {r.claimModule}"
    unless r.claimModule == ("FvapiSelf." ++ r.domain).toName &&
        r.specModule == ("FvapiSpec." ++ r.domain).toName &&
        ("FvapiProof." ++ r.domain).toName.isPrefixOf r.proofModule do
      errors := errors.push s!"{r.id}: domain module identities disagree"
    if (env.getModuleIdx? r.specModule).isNone then
      errors := errors.push s!"{r.id}: helper spec module {r.specModule} does not resolve"
    unless inv.audit.contains r.proofRoot && audit.contains r.proofModule &&
        (closure env #[r.proofRoot]).contains r.proofModule do
      errors := errors.push s!"{r.id}: aggregate proof root omits {r.proofModule}"
    match env.find? r.proof with
    | some (.thmInfo t) =>
      unless t.type == .const r.claim [] && t.levelParams.isEmpty do
        errors := errors.push s!"{r.id}: proof {r.proof} does not have type exactly {r.claim}"
      if moduleOf r.proof != some r.proofModule then
        errors := errors.push s!"{r.id}: proof is not declared in {r.proofModule}"
    | _ => errors := errors.push s!"{r.id}: proof {r.proof} is not a theorem"
    if r.subjects.isEmpty || r.callPaths.isEmpty then
      errors := errors.push s!"{r.id}: subjects and shipped call paths must be nonempty"
    for subject in r.subjects do
      unless (env.getModuleIdx? subject).isSome && production.contains subject &&
          !auditModule subject do
        errors := errors.push s!"{r.id}: audit subject {subject} is not a production module"
    for p in r.callPaths do
      match env.find? p, moduleOf p with
      | some (.defnInfo _), some m =>
        unless production.contains m && !auditModule m do
          errors := errors.push s!"{r.id}: call path {p} is not a definition in a production module"
      | _, _ =>
        errors := errors.push s!"{r.id}: call path {p} is not a definition in a production module"
    unless cells.any (namesCell · r.id) do
      errors := errors.push s!"{r.id}: no row in {matrixPath}"
  for line in body do
    unless (line.splitOn "|").any (fun c => inv.rows.any (fun r => namesCell c r.id)) do
      errors := errors.push s!"matrix row names no inventoried claim: {line}"
  for m in env.header.moduleNames do
    if m.getRoot == `FvapiSelf then
      for imp in closure env #[m] do
        if (imp.getRoot == `FvapiSelf && imp != m) ||
            [`FvapiProof, `FvapiProofs].contains imp.getRoot then
          errors := errors.push s!"{m} imports {imp} (claims stay domain-local)"
  for e in errors do IO.eprintln s!"inventory: {e}"
  IO.println (s!"inventory: {inv.rows.size} claims, {declared.size} closed claims, " ++
    s!"{errors.size} problems")
  return if errors.isEmpty then 0 else 1
