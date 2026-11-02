import Fvapi.Json
import Fvapi.Wire.Query

namespace Fvapi.Wire

open Fvapi.Json

/-- Body stage only: never inspect schema names before the complete J3 result. -/
def decideBody (mode : BodyMode) (body : ByteArray) : Except Failure Body :=
  match mode with
  | .none => if body.size = 0 then .ok .none else .error .malformed
  | .bytes => if body.size ≤ 65536 then .ok (.bytes body) else .error .tooLarge
  | .json => match Fvapi.Json.decode body with
    | .error .malformed => .error .malformed
    | .error .duplicateKey => .error .duplicateKey
    | .error .tooLarge => .error .tooLarge
    | .ok (.obj ms) => .ok (.json (.obj ms))
    | .ok _ => .error .malformed

def BodyKnown (s : Schema) : Body → Prop
  | .json v => HasKnown s v
  | _ => True

def BodyShape (s : Schema) : Body → Prop
  | .json v => HasShape s v ∧ HasRefinements s v
  | _ => True

instance (s : Schema) (b : Body) : Decidable (BodyKnown s b) := by
  cases b <;> unfold BodyKnown <;> infer_instance
instance (s : Schema) (b : Body) : Decidable (BodyShape s b) := by
  cases b <;> unfold BodyShape <;> infer_instance

def projectBody (s : Schema) : Body → Body
  | .json v => .json (project s v)
  | other => other

def lookupRule (route : Route) : Body → Option Failure
  | .json v => if route ≠ .lookup then none
      else if (v.asObj?.getD []).isEmpty then some .emptyQuery
      else match (v.get? "statement_digest").bind Value.asStr? with
        | none => none
        | some digest => if (digest.splitOn ":")[0]? = some "sd1" then none
            else some .unsupportedDigest
  | _ => none

/-- The five pure server stages; path, identity and store state are outside this function. -/
def decideRequest (route : Route) (query body : ByteArray) : Except Failure Request :=
  match parseQuery query with
  | .error failure => .error failure
  | .ok pairs =>
    let table := routeTable route
    match decideBody table.requestMode body with
    | .error failure => .error failure
    | .ok rawBody =>
      let normalized := normalizedQuery table.query pairs
      if HasKnown (querySchema table.query) normalized ∧ BodyKnown table.requestSchema rawBody then
        if HasShape (querySchema table.query) normalized ∧
            BodyShape table.requestSchema rawBody then
          match lookupRule route rawBody with
          | some failure => .error failure
          | none => .ok ⟨normalized, projectBody table.requestSchema rawBody⟩
        else .error .malformed
      else .error .unknownKey

/-- Validate the complete declaration before deciding feature support. -/
def featureNames? (v : Value) : Option (List String) :=
  match v.get? "required_features" with
  | none => some []
  | some (.arr xs) =>
      let names := xs.filterMap Value.asStr?
      if HasShape (.array 0 32 (.scalar .ident)) (.arr xs) ∧ names.Nodup then some names
      else none
  | _ => none

def responseTable (route : Route) (status : Nat) : Option ResponseTable :=
  (routeTable route).responses.find? (·.status == status)

/-- Raw bundle success terminates before JSON/features; every other status validates JSON. -/
def decideResponse (route : Route) (status : Nat) (body : ByteArray) : ResponseResult :=
  if route = .bundle ∧ status = 200 then .ok (.bytes body) else
  match Fvapi.Json.decode body with
  | .ok (.obj ms) =>
    let v := Value.obj ms
    match featureNames? v with
    | none => .badResponse
    | some (name :: names) => .unsupported (name :: names)
    | some [] =>
      match responseTable route status with
      | none => .badResponse
      | some table =>
        if HasShape table.schema v ∧ HasRefinements table.schema v then
          .ok (.json (project table.schema v))
        else .badResponse
  | _ => .badResponse

def encodeBody : Body → ByteArray
  | .none => ByteArray.empty
  | .bytes b => b
  | .json v => Fvapi.Json.print v

def encodeRequest (req : Request) : EncodedRequest := ⟨encodeQuery req.query, encodeBody req.body⟩

def encodeResponse : Response → ByteArray
  | .bytes b => b
  | .json v => Fvapi.Json.print v

end Fvapi.Wire
