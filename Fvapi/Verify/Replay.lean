import Fvapi.Verify.Replay.Decision
import Fvapi.Verify.Replay.Process

/-! P3: independent frozen challenge → bounded exports → comparator → each pinned kernel.
Only the embedded P4 tooling imports Lean; the shipped runner is Std-only. -/

namespace Fvapi.Verify.Replay

open Fvapi.Json

private def inventoryChecker : String := include_str "../../tools/lean/Inventory.lean"

structure KernelRun where
  result : KernelResult
  process : ProcessResult
  config : Option String := none
  cause : Option String := none

private def statusName : KernelStatus → String
  | .accept => "accept"
  | .reject => "reject"
  | .decline _ => "decline"
  | .crash => "crash"
  | .timeout => "timeout"

private def rcJson (rc : Option Nat) : Value :=
  (rc.map (fun n => Value.int n)).getD .null

private def KernelRun.toJson (k : KernelRun) : Value :=
  .object <| [("name", .str k.result.kernel.name),
    ("lineage", .str (match k.result.kernel.lineage with
      | .lean => "lean" | .nanoda => "nanoda" | .con => "con")),
    ("status", .str (statusName k.result.status)), ("wall_ms", .int k.process.wallMs),
    ("rc", rcJson k.process.rc)] ++
    (match k.result.status with | .decline f => [("feature", .str f)] | _ => []) ++
    (k.config.toList.map fun c => ("config", .str c))

structure Record where
  claim : Claim
  profile : String := ""
  snapshot : String := ""
  snapshotTree : String := ""
  config : String := ""
  exports : Value := .object []
  comparator : Value := .object [("status", .str "not_run"), ("rc", .null)]
  kernels : List KernelRun := []
  facts : Facts := {}
  diagnostics : List String := []

private def Record.toJson (expected : List KernelId) (r : Record) : Value :=
  let (causes, verdict) := judge expected r.facts (r.kernels.map (·.result))
  .object [("claim", .str r.claim.id), ("profile", .str r.profile),
    ("snapshot", .str r.snapshot), ("snapshot_tree", .str r.snapshotTree),
    ("config", .str r.config), ("exports", r.exports), ("comparator", r.comparator),
    ("kernels", .arr (r.kernels.map KernelRun.toJson)),
    ("causes", .arr (causes.map .str)),
    ("verdict", .str (if verdict == .pass then "pass" else "fail")),
    ("diagnostics", .arr (r.diagnostics.map .str))]

private def emit (json : Bool) (v : Value) : IO Unit :=
  if json then IO.println (String.fromUTF8! (print v))
  else IO.println (s!"{(v.get? "claim" >>= Value.asStr?).getD "replay"}: " ++
    s!"{(v.get? "verdict" >>= Value.asStr?).getD "fail"}")

private def invalidInventory (json : Bool) (detail : String) : IO UInt32 := do
  emit json (.object [("error", .str "inventory_invalid"), ("verdict", .str "fail"),
    ("causes", .arr []), ("diagnostics", .arr [.str detail])])
  return 1

private def failure (opts : Options) (inv : Inventory) (cause detail : String)
    (profile : String := "") : IO UInt32 := do
  for claim in inv.claims do
    let r : Record := {
      claim, profile, facts := { setupCauses := [cause] }
      diagnostics := [detail] }
    emit opts.json (r.toJson [])
  return 1

private def stillFrozen (root : System.FilePath) (f : Frozen) (exact : Bool) : IO Bool := do
  try unchanged root f exact catch _ => pure false

private def config (c : Claim) (axioms : List String) : Value :=
  .object [("challenge_module", .str c.proofModule), ("solution_module", .str c.proofModule),
    ("theorem_names", .arr [.str c.proof]), ("definition_names", .arr []),
    ("permitted_axioms", .arr (axioms.map .str))]

private def identity (v : Value) : String := "sha256:" ++ Hash.hex (Hash.sha256 (print v))

private def substitute (exportPath configPath : String) (axioms : List String)
    (s : String) : String :=
  s.replace "{export}" exportPath |>.replace "{config}" configPath
    |>.replace "{axioms}" (",".intercalate axioms)

mutual
private def template (exportPath configPath : String) (axioms : List String) : Value → Value
  | .str "{axioms}" => .arr (axioms.map .str)
  | .str s => .str (substitute exportPath configPath axioms s)
  | .arr xs => .arr (templateList exportPath configPath axioms xs)
  | .obj ms => .obj (templateMembers exportPath configPath axioms ms)
  | v => v
private def templateList (e c : String) (a : List String) : List Value → List Value
  | [] => []
  | v :: vs => template e c a v :: templateList e c a vs
private def templateMembers (e c : String) (a : List String) :
    List (String × Value) → List (String × Value)
  | [] => []
  | (k, v) :: ms => (k, template e c a v) :: templateMembers e c a ms
end

private def digestMatches (path : System.FilePath) (expected : String) : IO Bool := do
  try return Hash.hex (← Hash.sha256File path) == expected catch _ => return false

private def runKernel (opts : Options) (pre directory solution : System.FilePath)
    (p : Profile) (k : KernelSpec) : IO KernelRun := do
  let configPath := directory / (k.id.name ++ ".json")
  let mut configId := none
  if let some v := k.configTemplate then
    let generated := template solution.toString configPath.toString opts.axioms v
    IO.FS.writeBinFile configPath (print generated)
    configId := some (identity generated)
    makeReadOnly configPath
  let args := k.args.flatMap fun arg =>
    if arg == "{axioms}" then opts.axioms
    else [substitute solution.toString configPath.toString opts.axioms arg]
  let process ← runProcess opts.packagePath directory k.id.name k.timeoutMs p.memoryBytes
    (resolve pre k.pinned.executable).toString args.toArray
  let (status, cause) := adaptStatus k process.rc process.timedOut process.stderr
  return ⟨⟨k.id, status⟩, process, configId, cause⟩

private def runClaim (opts : Options) (pre directory challenge : System.FilePath)
    (p : Profile) (snapshotId treeId : String) (claim : Claim) : IO Record := do
  IO.FS.createDirAll directory
  let cfg := config claim opts.axioms
  let configPath := directory / "comparator.json"
  IO.FS.writeBinFile configPath (print cfg)
  makeReadOnly configPath
  let mut record : Record := {
    claim, profile := p.id, snapshot := snapshotId
    snapshotTree := treeId, config := identity cfg }
  let targets := ([claim.proof] ++ opts.axioms ++ p.comparatorTargets).eraseDups
  let args := #["env", (resolve pre p.exporter.executable).toString, claim.proofModule, "--"] ++
    targets.toArray
  let c ← runProcess challenge directory "challenge-export" p.exportMs p.memoryBytes
    (pre / "bin/lake").toString args
  let s ← runProcess opts.packagePath directory "solution-export" p.exportMs p.memoryBytes
    (pre / "bin/lake").toString args
  unless c.ok && s.ok do
    return { record with facts := { exportsOk := false }, diagnostics := [c.stderr, s.stderr] }
  let challengeHash := Hash.hex (← Hash.sha256File c.stdoutPath)
  let solutionHash := Hash.hex (← Hash.sha256File s.stdoutPath)
  if (← c.stdoutPath.metadata).byteSize == 0 || (← s.stdoutPath.metadata).byteSize == 0 then
    return { record with facts := { exportsOk := false }, diagnostics := ["empty export"] }
  makeReadOnly c.stdoutPath
  makeReadOnly s.stdoutPath
  record := { record with exports := .object [("challenge_sha256", .str challengeHash),
    ("solution_sha256", .str solutionHash)] }
  let comp ← runProcess opts.packagePath directory "comparator" p.comparatorMs p.memoryBytes
    (resolve pre p.comparator.executable).toString #["comparator", "--config", configPath.toString,
      "--challenge-from-export", c.stdoutPath.toString,
      "--solution-from-export", s.stdoutPath.toString]
  let cause := comparatorCause comp.rc comp.timedOut comp.stderr
  record := { record with
    comparator := .object [("status", .str (if comp.ok then "accept" else
      if comp.timedOut then "timeout" else "error")), ("rc", rcJson comp.rc),
      ("wall_ms", .int comp.wallMs)]
    facts := { comparatorCause := cause }
    diagnostics := if cause.isSome then [comp.stderr] else [] }
  unless (← digestMatches c.stdoutPath challengeHash) &&
      (← digestMatches s.stdoutPath solutionHash) do
    return { record with facts := { record.facts with exportsOk := false } }
  if cause.isSome then return record
  for k in p.kernels do
    let problems ← checkPinned pre "kernel" k.pinned
    unless problems.isEmpty do
      return { record with
        facts := { record.facts with setupCauses := ["kernel_identity_mismatch"] }
        diagnostics := problems.map (fun x => x.detail) }
    let result ← runKernel opts pre directory s.stdoutPath p k
    record := { record with
      kernels := record.kernels ++ [result]
      facts := { record.facts with
        setupCauses := record.facts.setupCauses ++ result.cause.toList } }
    unless (← digestMatches s.stdoutPath solutionHash) &&
        (← digestMatches c.stdoutPath challengeHash) do
      return { record with facts := { record.facts with exportsOk := false } }
  return record

private def hostCause (pre : System.FilePath) (p : Profile) (problems : List Problem) :
    IO String := do
  for (k, i) in p.kernels.zipIdx do
    if problems.any (fun x => x.field == s!"kernels[{i}].sha256") then
      if !(← (resolve pre k.pinned.executable).pathExists) then return "kernel_missing"
      return "kernel_identity_mismatch"
  return "profile_mismatch"

private def executeWith (opts : Options) (directory : System.FilePath) (inv : Inventory) :
    IO UInt32 := do
  let p ← match ← (readJson opts.profilePath).toBaseIO with
    | .error e => return ← failure opts inv "profile_mismatch" s!"{e}"
    | .ok v => match checkProfile .caller v with
      | .error e => return ← failure opts inv "profile_mismatch" s!"{e.field}: {e.detail}"
      | .ok p => pure p
  unless p.exportMs > 0 && p.comparatorMs > 0 && p.memoryBytes > 0 do
    return ← failure opts inv "profile_mismatch" "caps must be positive" p.id
  let pre ← leanPrefix
  let problems ← checkHost pre p false
  unless problems.isEmpty do
    return ← failure opts inv (← hostCause pre p problems)
      ("\n".intercalate (problems.map fun x => s!"{x.field}: {x.detail}")) p.id
  let (snapshotId, frozen) ← match ← (snapshot opts.expectedSource inv.claims).toBaseIO with
    | .error e => return ← failure opts inv "challenge_mismatch" s!"{e}" p.id
    | .ok x => pure x
  let challenge := directory / "challenge"
  IO.FS.createDirAll challenge
  let challengeFrozen ← materialize opts.expectedSource challenge frozen inv.claims
  let lake := (pre / "bin/lake").toString
  let built ← runProcess opts.packagePath directory "solution-build" p.exportMs p.memoryBytes
    lake (#["build"] ++ inv.roots.toArray)
  unless (← stillFrozen opts.expectedSource frozen true) &&
      (← stillFrozen challenge challengeFrozen false) do
    return ← failure opts inv "challenge_mismatch"
      "frozen inputs changed during solution build" p.id
  unless built.ok do return ← failure opts inv "export_failed" built.stderr p.id
  let checker := directory / "Inventory.lean"
  IO.FS.writeFile checker inventoryChecker
  let checked ← runProcess opts.packagePath directory "inventory" p.exportMs p.memoryBytes
    lake #["env", "lean", "--run", checker.toString, opts.inventoryPath.toString,
      (opts.packagePath / "docs/obligations.md").toString]
  unless checked.ok do return ← invalidInventory opts.json checked.stderr
  let got ← runtimeDigest pre
  unless got == p.runtimeSha256 do
    return ← failure opts inv "profile_mismatch" s!"runtime.sha256: {got} != {p.runtimeSha256}" p.id
  let builtChallenge ← runProcess challenge directory "challenge-build" p.exportMs p.memoryBytes
    lake (#["build"] ++ (inv.claims.map (·.proofRoot)).eraseDups.toArray)
  unless builtChallenge.ok do
    let output ← IO.FS.readFile builtChallenge.stdoutPath
    return ← failure opts inv "export_failed" (builtChallenge.stderr ++ output) p.id
  let mut records := []
  for (claim, i) in inv.claims.zipIdx do
    let r ← try
      runClaim opts pre (directory / s!"claim-{i}") challenge p snapshotId frozen.identity claim
    catch e => pure {
      claim, profile := p.id, snapshot := snapshotId, snapshotTree := frozen.identity
      config := identity (config claim opts.axioms), facts := { exportsOk := false }
      diagnostics := [s!"{e}"] }
    records := records ++ [r]
  let inputsOk := (← stillFrozen opts.expectedSource frozen true) &&
    (← stillFrozen challenge challengeFrozen false)
  let mut allPass := !records.isEmpty && records.length == inv.claims.length
  let expected := p.kernels.map (·.id)
  for r in records do
    let r := { r with facts := { r.facts with snapshotOk := inputsOk } }
    allPass := allPass && (judge expected r.facts (r.kernels.map (·.result))).2 == .pass
    emit opts.json (r.toJson expected)
  return if allPass then 0 else 1

private def execute (opts : Options) (directory : System.FilePath) : IO UInt32 := do
  let raw ← match ← (IO.FS.readBinFile opts.inventoryPath).toBaseIO with
    | .error e => return ← invalidInventory opts.json s!"{e}"
    | .ok raw => pure raw
  let value ← match decode raw with
    | .error e => return ← invalidInventory opts.json s!"{repr e}"
    | .ok value => pure value
  let inv ← match readInventory value with
    | .error e => return ← invalidInventory opts.json s!"{e.field}: {e.detail}"
    | .ok inv => pure inv
  try
    -- Build hooks can rewrite package metadata; P4 checks the exact bytes that supplied our rows.
    let inventoryPath := directory / "inventory.json"
    IO.FS.writeBinFile inventoryPath raw
    makeReadOnly inventoryPath
    executeWith { opts with inventoryPath } directory inv
  catch e => failure opts inv "export_failed" s!"{e}"

/-- Cleanup owns one private tree; every child process is supervised by its own finite deadline. -/
def run (opts : Options) : IO UInt32 := do
  let directory ← temporaryDirectory
  try
    execute opts directory
  catch e =>
    emit opts.json (.object [("error", .str "replay_error"), ("verdict", .str "fail"),
      ("causes", .arr [.str "export_failed"]), ("diagnostics", .arr [.str s!"{e}"])])
    return 1
  finally
    IO.FS.removeDirAll directory

end Fvapi.Verify.Replay
