import Lean

/-! Gate stage `inventory` (docs/contracts/U2-trust.md P4): `verify/claims.json` ↔ the elaborated
closed claims of the audit tree. Dev tooling (imports `Lean`), never shipped.
Usage: lake env lean --run tools/lean/Inventory.lean [claims.json] [obligations.md] -/

open Lean

structure Row where
  id : String
  claim : Name
  proof : Name
  claimModule : Name
  callPaths : Array Name

def field (j : Json) (k : String) : Except String String := j.getObjValAs? String k

def readRows (path : System.FilePath) : IO (Array Row) := do
  let j ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  let claims ← IO.ofExcept (j.getObjValAs? (Array Json) "claims")
  claims.mapM fun c => IO.ofExcept do
    let paths ← c.getObjValAs? (Array String) "shipped_call_paths"
    return { id := ← field c "id", claim := (← field c "claim").toName,
             proof := (← field c "proof").toName,
             claimModule := (← field c "claim_module").toName,
             callPaths := paths.map String.toName }

def main (args : List String) : IO UInt32 := do
  let claimsPath := args.getD 0 "verify/claims.json"
  let matrixPath := args.getD 1 "docs/obligations.md"
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `FvapiProofs }, { module := `Fvapi }] {}
  let rows ← readRows claimsPath
  let matrix ← IO.FS.readFile matrixPath
  let mut errors : Array String := #[]
  let moduleOf (n : Name) : Option Name := (env.getModuleIdxFor? n).map (env.header.moduleNames[·]!)
  -- Every Prop-valued definition declared in an FvapiSelf module = one inventory claim.
  let mut declared : Array Name := #[]
  for (n, ci) in env.constants.map₁.toList do
    if let some m := moduleOf n then
      if m.getRoot == `FvapiSelf && !n.isInternal then
        if let .defnInfo d := ci then
          if d.type == .sort .zero then declared := declared.push n
  let listed := rows.map (·.claim)
  for n in declared do
    if (listed.filter (· == n)).size != 1 then
      let k := (listed.filter (· == n)).size
      errors := errors.push s!"{n} is a closed claim with {k} inventory rows (want 1)"
  let ids := rows.map (·.id)
  for r in rows do
    if (ids.filter (· == r.id)).size != 1 then errors := errors.push s!"duplicate id {r.id}"
    unless declared.contains r.claim do
      errors := errors.push s!"{r.id}: {r.claim} is not a Prop definition in an FvapiSelf module"
    if moduleOf r.claim != some r.claimModule then
      errors := errors.push s!"{r.id}: {r.claim} is not declared in {r.claimModule}"
    match env.find? r.proof with
    | some (.thmInfo t) =>
      unless t.type == .const r.claim [] do
        errors := errors.push s!"{r.id}: proof {r.proof} does not have type exactly {r.claim}"
    | _ => errors := errors.push s!"{r.id}: proof {r.proof} is not a theorem"
    for p in r.callPaths do
      match env.find?, moduleOf p with
      | f, some m =>
        if m.getRoot != `Fvapi || !(f p matches some (.defnInfo _)) then
          errors := errors.push
            s!"{r.id}: call path {p} is not a definition in a production module"
      | _, none => errors := errors.push s!"{r.id}: call path {p} does not resolve"
    unless (matrix.splitOn s!"`{r.id}`").length > 1 do
      errors := errors.push s!"{r.id}: no row in {matrixPath}"
  -- Domain locality: a closed-claim module imports no other domain's Self or Proof module.
  for (m, idx) in env.header.moduleNames.zipIdx do
    if m.getRoot == `FvapiSelf then
      for imp in env.header.moduleData[idx]!.imports do
        let r := imp.module.getRoot
        if (r == `FvapiSelf && imp.module != m) || r == `FvapiProof || r == `FvapiProofs then
          errors := errors.push s!"{m} imports {imp.module} (claims stay domain-local)"
  for e in errors do IO.eprintln s!"inventory: {e}"
  IO.println
    s!"inventory: {rows.size} claims, {declared.size} closed claims, {errors.size} problems"
  return if errors.isEmpty then 0 else 1
