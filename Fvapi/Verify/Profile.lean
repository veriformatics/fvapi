import Fvapi.Hash.Sha256
import Fvapi.Json
import Fvapi.Verify.Policy

/-! The verification profile (`docs/contracts/U2-trust.md` P2, schema 1): parsed from its JSON
with every problem named by its field path, the run-set rule per scope, and the id rule. Host
identity checks (executables, comparator source, runtime) live in `Fvapi.Verify.Host`. -/

namespace Fvapi.Verify

open Fvapi.Json

/-- Every kernel id, in profile-schema order. -/
def KernelId.all : List KernelId :=
  [.leanchecker, .leancheckerParanoid, .lean4lean, .nanoda, .conLeche, .conRon]

def KernelId.ofName? (s : String) : Option KernelId :=
  KernelId.all.find? (·.name == s)

/-- Whose profile: fvapi's own (all six kernels) or a caller-held one. -/
inductive Scope where
  | caller
  | service
  deriving DecidableEq, Repr

/-- P2 run set: fvapi's own profile names the six kernels once each; a caller-held one names
kernels without repeats that include leanchecker + a kernel of another lineage. -/
def runSetOk : Scope → List KernelId → Bool
  | .service, ks => decide ks.Nodup && KernelId.all.all (· ∈ ks)
  | .caller, ks => decide ks.Nodup && ks.contains .leanchecker && ks.any (·.lineage != .lean)

/-- An executable the profile pins by its bytes (`{lean_prefix}` = the toolchain root). -/
structure Pinned where
  executable : String
  sha256 : String
  deriving Repr

inductive Mapped where
  | accept
  | reject
  | decline
  deriving DecidableEq, Repr

structure KernelSpec where
  id : KernelId
  pinned : Pinned
  args : List String
  timeoutMs : Nat
  /-- Exit code → status; an unmapped exit is a crash. -/
  statusMap : List (Nat × Mapped)
  declinePattern : Option String
  crashPattern : Option String
  configTemplate : Option Value
  deriving Repr

structure Profile where
  id : String
  toolchain : String
  runtimeSha256 : String
  exportFormat : String
  exporter : Pinned
  comparator : Pinned
  comparatorSource : String
  comparatorSourceSha256 : String
  comparatorTargets : List String
  canaries : Value
  policyVersion : Nat
  exportMs : Nat
  comparatorMs : Nat
  memoryBytes : Nat
  kernels : List KernelSpec
  deriving Repr

/-- A failed check: the field path (e.g. `kernels[2].sha256`) + what was wrong. -/
structure Problem where
  field : String
  detail : String
  deriving Repr

def Problem.toJson (p : Problem) : Value :=
  .object [("field", .str p.field), ("detail", .str p.detail)]

abbrev Read := Except Problem

namespace Read

def join (path key : String) : String := if path.isEmpty then key else path ++ "." ++ key

def members (path : String) : Value → Read (List (String × Value))
  | .obj ms => pure ms
  | _ => throw ⟨path, "not an object"⟩

/-- The object's keys are exactly `required` plus some of `optional`. -/
def keys (path : String) (ms : List (String × Value)) (required optional : List String) :
    Read Unit := do
  for (k, _) in ms do
    unless required.contains k || optional.contains k do
      throw ⟨join path k, "unknown field"⟩
  for k in required do
    unless ms.any (·.1 == k) do throw ⟨join path k, "missing"⟩

def get (path : String) (ms : List (String × Value)) (key : String) : Read Value :=
  match (Value.obj ms).get? key with
  | some v => pure v
  | none => throw ⟨join path key, "missing"⟩

def str (path : String) : Value → Read String
  | .str s => pure s
  | _ => throw ⟨path, "not a string"⟩

def nat (path : String) : Value → Read Nat
  | .int n => if 0 ≤ n then pure n.toNat else throw ⟨path, "negative"⟩
  | _ => throw ⟨path, "not an integer"⟩

def strs (path : String) : Value → Read (List String)
  | .arr xs => xs.mapIdxM fun i v => str s!"{path}[{i}]" v
  | _ => throw ⟨path, "not an array"⟩

/-- 64 lowercase hex digits. -/
def sha256 (path : String) (v : Value) : Read String := do
  let s ← str path v
  unless s.length == 64 && s.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')) do
    throw ⟨path, "not 64 lowercase hex digits"⟩
  return s

def pinned (path : String) (v : Value) (optional : List String := []) : Read Pinned := do
  let ms ← members path v
  keys path ms ["executable", "sha256"] optional
  return ⟨← str (join path "executable") (← get path ms "executable"),
    ← sha256 (join path "sha256") (← get path ms "sha256")⟩

def mapped (path : String) : Value → Read Mapped
  | .str "accept" => pure .accept
  | .str "reject" => pure .reject
  | .str "decline" => pure .decline
  | _ => throw ⟨path, "not accept, reject or decline"⟩

def statusMap (path : String) (v : Value) : Read (List (Nat × Mapped)) := do
  let ms ← members path v
  ms.mapM fun (k, m) => do
    let some code := k.toNat? | throw ⟨join path k, "not an exit code"⟩
    unless code ≤ 255 && toString code == k do throw ⟨join path k, "not an exit code"⟩
    return (code, ← mapped (join path k) m)

def kernel (path : String) (v : Value) : Read KernelSpec := do
  let ms ← members path v
  keys path ms ["name", "executable", "sha256", "args", "timeout_ms", "status_map"]
    ["decline_pattern", "crash_pattern", "config_template"]
  let name ← str (join path "name") (← get path ms "name")
  let some id := KernelId.ofName? name | throw ⟨join path "name", s!"{name} is not a kernel id"⟩
  let opt (key : String) : Read (Option String) :=
    match (Value.obj ms).get? key with
    | some s => some <$> str (join path key) s
    | none => pure none
  return {
    id
    pinned := ← pinned path (.obj (ms.filter fun m => m.1 == "executable" || m.1 == "sha256"))
    args := ← strs (join path "args") (← get path ms "args")
    timeoutMs := ← nat (join path "timeout_ms") (← get path ms "timeout_ms")
    statusMap := ← statusMap (join path "status_map") (← get path ms "status_map")
    declinePattern := ← opt "decline_pattern"
    crashPattern := ← opt "crash_pattern"
    configTemplate := (Value.obj ms).get? "config_template" }

end Read

/-- The id rule: `"sha256:"` + the SHA-256 of the canonical text of the profile without its
root `id` (= jq `-S -c 'del(.id)'` without the final LF; U2 P2). -/
def profileId (v : Value) : String :=
  let rest := match v with
    | .obj ms => Value.obj (ms.filter (·.1 != "id"))
    | other => other
  "sha256:" ++ Hash.hex (Hash.sha256 (print rest))

/-- The schema-1 profile `v` (a decoded JSON value), or the first problem found. -/
def parseProfile (v : Value) : Read Profile := do
  let ms ← Read.members "" v
  Read.keys "" ms ["id", "version", "toolchain", "runtime", "export_format", "exporter",
    "comparator", "canaries", "policy_version", "caps", "kernels"] []
  let version ← Read.nat "version" (← Read.get "" ms "version")
  unless version == 1 do throw ⟨"version", s!"{version} is not schema 1"⟩
  let id ← Read.str "id" (← Read.get "" ms "id")
  unless id == profileId v do throw ⟨"id", s!"{id} != recomputed {profileId v}"⟩
  let runtime ← Read.members "runtime" (← Read.get "" ms "runtime")
  let comparator ← Read.get "" ms "comparator"
  let cms ← Read.members "comparator" comparator
  Read.keys "comparator" cms ["executable", "sha256", "source", "source_sha256", "targets"] []
  let caps ← Read.members "caps" (← Read.get "" ms "caps")
  Read.keys "caps" caps ["export_ms", "comparator_ms", "memory_bytes"] []
  let kernels ← match ← Read.get "" ms "kernels" with
    | .arr xs => xs.mapIdxM fun i k => Read.kernel s!"kernels[{i}]" k
    | _ => throw ⟨"kernels", "not an array"⟩
  return {
    id
    toolchain := ← Read.str "toolchain" (← Read.get "" ms "toolchain")
    runtimeSha256 := ← Read.sha256 "runtime.sha256" (← Read.get "runtime" runtime "sha256")
    exportFormat := ← Read.str "export_format" (← Read.get "" ms "export_format")
    exporter := ← Read.pinned "exporter" (← Read.get "" ms "exporter")
    comparator := ← Read.pinned "comparator"
      (.obj (cms.filter fun m => m.1 == "executable" || m.1 == "sha256"))
    comparatorSource := ← Read.str "comparator.source" (← Read.get "comparator" cms "source")
    comparatorSourceSha256 :=
      ← Read.sha256 "comparator.source_sha256" (← Read.get "comparator" cms "source_sha256")
    comparatorTargets := ← Read.strs "comparator.targets" (← Read.get "comparator" cms "targets")
    canaries := ← Read.get "" ms "canaries"
    policyVersion := ← Read.nat "policy_version" (← Read.get "" ms "policy_version")
    exportMs := ← Read.nat "caps.export_ms" (← Read.get "caps" caps "export_ms")
    comparatorMs := ← Read.nat "caps.comparator_ms" (← Read.get "caps" caps "comparator_ms")
    memoryBytes := ← Read.nat "caps.memory_bytes" (← Read.get "caps" caps "memory_bytes")
    kernels }

/-- Parses the profile and checks its run set for `scope`. -/
def checkProfile (scope : Scope) (v : Value) : Read Profile := do
  let p ← parseProfile v
  unless runSetOk scope (p.kernels.map (·.id)) do
    throw ⟨"kernels", match scope with
      | .service => "fvapi's own profile names the six kernels, once each"
      | .caller => "a caller profile names kernels once each, incl. leanchecker + one of " ++
          "another lineage (nanoda, con-leche, con-ron)"⟩
  return p

end Fvapi.Verify
