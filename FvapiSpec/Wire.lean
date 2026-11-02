import FvapiSpec.Wire.Tables
import FvapiSpec.Wire.Denotation

/-! Five pure server stages + four client stages. Routing, authentication, collection membership,
expiry and store transitions belong to their owning units, outside this byte relation. -/
namespace FvapiSpec.Wire

open Fvapi.Wire Fvapi.Json

abbrev Bytes := List UInt8

/-- Delimiters are literal bytes; no percent decoding or plus conversion. -/
def splitBytes (delimiter : UInt8) (bytes : Bytes) : List Bytes :=
  bytes.foldr (fun b parts => if b = delimiter then [] :: parts else
    match parts with | [] => [[b]] | part :: rest => (b :: part) :: rest) [[]]

def queryByte (b : UInt8) : Bool :=
  (0x41 ≤ b && b ≤ 0x5a) || (0x61 ≤ b && b ≤ 0x7a) || (0x30 ≤ b && b ≤ 0x39) ||
    b == 0x2e || b == 0x5f || b == 0x7e || b == 0x2d

def QueryItem (bytes : Bytes) : Prop :=
  match splitBytes 0x3d bytes with
  | [name, value] => name ≠ [] ∧ value ≠ [] ∧
      name.all queryByte = true ∧ value.all queryByte = true
  | _ => False

def QuerySyntax (raw : ByteArray) : Prop :=
  raw.size = 0 ∨ ∀ item ∈ splitBytes 0x26 raw.data.toList, QueryItem item

def queryPairs (raw : ByteArray) : List (String × String) :=
  if raw.size = 0 then [] else (splitBytes 0x26 raw.data.toList).map fun item =>
    let pair := splitBytes 0x3d item
    (String.fromUTF8! ⟨(pair[0]?.getD []).toArray⟩,
      String.fromUTF8! ⟨(pair[1]?.getD []).toArray⟩)

inductive QueryStage (raw : ByteArray) : Except Failure (List (String × String)) → Prop
  | malformed : ¬ QuerySyntax raw → QueryStage raw (.error .malformed)
  | duplicate : QuerySyntax raw → ¬ ((queryPairs raw).map Prod.fst).Nodup →
      QueryStage raw (.error .duplicateKey)
  | ok : QuerySyntax raw → ((queryPairs raw).map Prod.fst).Nodup →
      QueryStage raw (.ok (queryPairs raw))

def querySchema (fields : List QueryField) : Schema :=
  .record (fields.map fun f => (f.name, f.required, .scalar f.kind)) []

def numeric : Scalar → Bool
  | .nat | .pos | .boundedNat _ _ => true
  | _ => false

/-- Numeric spelling belongs to stage 4; `.null` cannot inhabit a numeric query field. -/
def queryScalar (kind : Scalar) (text : String) : Value :=
  if numeric kind then
    match text.toNat? with
    | some n => if text = toString n then .int n else .null
    | none => .null
  else .str text

def normalizedQuery (fields : List QueryField) (pairs : List (String × String)) : Value :=
  let supplied := pairs.map fun (name, text) =>
    let kind := ((fields.find? (·.name == name)).map (·.kind)).getD .any
    (name, queryScalar kind text)
  let defaults := fields.filterMap fun f =>
    if pairs.any (·.1 == f.name) then none
    else f.default?.map fun text => (f.name, queryScalar f.kind text)
  .object (supplied ++ defaults)

inductive BodyStage : BodyMode → ByteArray → Except Failure Body → Prop
  | noneOk {b : ByteArray} : b.size = 0 → BodyStage .none b (.ok .none)
  | noneBad {b : ByteArray} : b.size ≠ 0 → BodyStage .none b (.error .malformed)
  | bytesOk {b : ByteArray} : b.size ≤ 65536 → BodyStage .bytes b (.ok (.bytes b))
  | bytesLong {b : ByteArray} : 65536 < b.size → BodyStage .bytes b (.error .tooLarge)
  | jsonMalformed {b : ByteArray} : FvapiSpec.Json.Outcome b.data.toList (.error .malformed) →
      BodyStage .json b (.error .malformed)
  | jsonDuplicate {b : ByteArray} :
      FvapiSpec.Json.Outcome b.data.toList (.error .duplicateKey) →
      BodyStage .json b (.error .duplicateKey)
  | jsonLong {b : ByteArray} : FvapiSpec.Json.Outcome b.data.toList (.error .tooLarge) →
      BodyStage .json b (.error .tooLarge)
  | jsonRoot {b : ByteArray} {v : Value} :
      FvapiSpec.Json.Outcome b.data.toList (.ok v) → (∀ ms, v ≠ .obj ms) →
      BodyStage .json b (.error .malformed)
  | jsonOk {b : ByteArray} {ms : List (String × Value)} :
      FvapiSpec.Json.Outcome b.data.toList (.ok (.obj ms)) →
      BodyStage .json b (.ok (.json (.obj ms)))

def BodyKnown (s : Schema) : Body → Prop
  | .json v => Known s v
  | _ => True

def BodyShape (s : Schema) : Body → Prop
  | .json v => Shape s v ∧ Refined s v
  | _ => True

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

/-- Ordered stages: query syntax, body mode/J3, unknown names, types, lookup rules. -/
inductive RequestOutcome (route : Route) (rawQuery body : ByteArray) :
    Except Failure Request → Prop
  | queryError {f : Failure} : QueryStage rawQuery (.error f) →
      RequestOutcome route rawQuery body (.error f)
  | bodyError {pairs : List (String × String)} {f : Failure} :
      QueryStage rawQuery (.ok pairs) →
      BodyStage (reviewedTable route).requestMode body (.error f) →
      RequestOutcome route rawQuery body (.error f)
  | unknown {pairs : List (String × String)} {b : Body} :
      QueryStage rawQuery (.ok pairs) →
      BodyStage (reviewedTable route).requestMode body (.ok b) →
      ¬ (Known (querySchema (reviewedTable route).query)
          (normalizedQuery (reviewedTable route).query pairs) ∧
        BodyKnown (reviewedTable route).requestSchema b) →
      RequestOutcome route rawQuery body (.error .unknownKey)
  | malformed {pairs : List (String × String)} {b : Body} :
      QueryStage rawQuery (.ok pairs) →
      BodyStage (reviewedTable route).requestMode body (.ok b) →
      Known (querySchema (reviewedTable route).query)
        (normalizedQuery (reviewedTable route).query pairs) →
      BodyKnown (reviewedTable route).requestSchema b →
      ¬ (Shape (querySchema (reviewedTable route).query)
          (normalizedQuery (reviewedTable route).query pairs) ∧
        BodyShape (reviewedTable route).requestSchema b) →
      RequestOutcome route rawQuery body (.error .malformed)
  | rule {pairs : List (String × String)} {b : Body} {f : Failure} :
      QueryStage rawQuery (.ok pairs) →
      BodyStage (reviewedTable route).requestMode body (.ok b) →
      Known (querySchema (reviewedTable route).query)
        (normalizedQuery (reviewedTable route).query pairs) →
      BodyKnown (reviewedTable route).requestSchema b →
      Shape (querySchema (reviewedTable route).query)
        (normalizedQuery (reviewedTable route).query pairs) →
      BodyShape (reviewedTable route).requestSchema b → lookupRule route b = some f →
      RequestOutcome route rawQuery body (.error f)
  | ok {pairs : List (String × String)} {b : Body} :
      QueryStage rawQuery (.ok pairs) →
      BodyStage (reviewedTable route).requestMode body (.ok b) →
      Known (querySchema (reviewedTable route).query)
        (normalizedQuery (reviewedTable route).query pairs) →
      BodyKnown (reviewedTable route).requestSchema b →
      Shape (querySchema (reviewedTable route).query)
        (normalizedQuery (reviewedTable route).query pairs) →
      BodyShape (reviewedTable route).requestSchema b → lookupRule route b = none →
      RequestOutcome route rawQuery body (.ok
        ⟨normalizedQuery (reviewedTable route).query pairs,
          projectBody (reviewedTable route).requestSchema b⟩)

/-- Complete declaration first; clients currently know no feature names. -/
def FeatureDeclaration (v : Value) (names : List String) : Prop :=
  match v.get? "required_features" with
  | none => names = []
  | some (.arr xs) => xs = names.map Value.str ∧ names.length ≤ 32 ∧ names.Nodup ∧
      ∀ name ∈ names, ScalarDenotes .ident (.str name)
  | _ => False

def responseTable (route : Route) (status : Nat) : Option ResponseTable :=
  ((reviewedTable route).responses.find? (·.status == status))

/-- Admissibility supplies the JSON schema; raw response bytes retain their identity. -/
def projectResponse (route : Route) (status : Nat) : Response → Response
  | .bytes bytes => .bytes bytes
  | .json value => match responseTable route status with
    | some table => .json (project table.schema value)
    | none => .json value

inductive ResponseOutcome (route : Route) (status : Nat) (body : ByteArray) :
    ResponseResult → Prop
  | raw : route = .bundle → status = 200 →
      ResponseOutcome route status body (.ok (.bytes body))
  | jsonBad : ¬ (route = .bundle ∧ status = 200) →
      (∀ ms, ¬ FvapiSpec.Json.Outcome body.data.toList (.ok (.obj ms))) →
      ResponseOutcome route status body .badResponse
  | featuresBad {ms : List (String × Value)} : ¬ (route = .bundle ∧ status = 200) →
      FvapiSpec.Json.Outcome body.data.toList (.ok (.obj ms)) →
      (∀ names, ¬ FeatureDeclaration (.obj ms) names) →
      ResponseOutcome route status body .badResponse
  | unsupported {ms : List (String × Value)} {names : List String} :
      ¬ (route = .bundle ∧ status = 200) →
      FvapiSpec.Json.Outcome body.data.toList (.ok (.obj ms)) →
      FeatureDeclaration (.obj ms) names → names ≠ [] →
      ResponseOutcome route status body (.unsupported names)
  | recordBad {ms : List (String × Value)} : ¬ (route = .bundle ∧ status = 200) →
      FvapiSpec.Json.Outcome body.data.toList (.ok (.obj ms)) →
      FeatureDeclaration (.obj ms) [] →
      (∀ table ∈ responseTable route status,
        ¬ (Shape table.schema (.obj ms) ∧ Refined table.schema (.obj ms))) →
      ResponseOutcome route status body .badResponse
  | ok {ms : List (String × Value)} {table : ResponseTable} :
      ¬ (route = .bundle ∧ status = 200) →
      FvapiSpec.Json.Outcome body.data.toList (.ok (.obj ms)) →
      FeatureDeclaration (.obj ms) [] → responseTable route status = some table →
      Shape table.schema (.obj ms) → Refined table.schema (.obj ms) →
      ResponseOutcome route status body (.ok (.json (project table.schema (.obj ms))))

/-- Complete normalized requests include their typed query defaults. -/
def RequestAdmissible (route : Route) (req : Request) : Prop :=
  Shape (querySchema (reviewedTable route).query) req.query ∧
  Known (querySchema (reviewedTable route).query) req.query ∧
  project (querySchema (reviewedTable route).query) req.query = req.query ∧
  (∀ f ∈ (reviewedTable route).query, f.default?.isSome = true →
    (req.query.get? f.name).isSome = true) ∧
  FvapiSpec.Json.Valid req.query ∧ lookupRule route req.body = none ∧
  match (reviewedTable route).requestMode, req.body with
  | .none, .none => True
  | .bytes, .bytes b => b.size ≤ 65536
  | .json, .json v => Denotes (reviewedTable route).requestSchema v v ∧
      Known (reviewedTable route).requestSchema v ∧ FvapiSpec.Json.Valid v
  | _, _ => False

/-- Complete response inputs may carry additive members at every record level. -/
def ResponseAdmissible (route : Route) (status : Nat) (res : Response) : Prop :=
  match res with
  | .bytes _ => route = .bundle ∧ status = 200
  | .json v => ∃ table, responseTable route status = some table ∧ table.mode = .json ∧
      Shape table.schema v ∧ Refined table.schema v ∧
      FvapiSpec.Json.Valid v ∧ FeatureDeclaration v []

/-- Mode-specific byte laws stay in the spec so closed claims contain no matcher helpers. -/
def requestBodyLaw (body : Body) (encoded : EncodedRequest) : Prop :=
  match body with
  | .none => encoded.body.size = 0
  | .bytes bytes => encoded.body = bytes
  | .json value => encoded.body.data.toList = FvapiSpec.Json.canonical value

def responseBodyLaw (response : Response) (encoded : ByteArray) : Prop :=
  match response with
  | .bytes bytes => encoded = bytes
  | .json value => encoded.data.toList = FvapiSpec.Json.canonical value

end FvapiSpec.Wire
