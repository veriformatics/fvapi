import Fvapi.Wire.Model
import Fvapi.Wire.Tables

namespace Fvapi.Wire

open Fvapi.Json

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

instance (bytes : Bytes) : Decidable (QueryItem bytes) := by
  unfold QueryItem
  split <;> infer_instance

instance (raw : ByteArray) : Decidable (QuerySyntax raw) := by
  unfold QuerySyntax
  infer_instance

def parseQuery (raw : ByteArray) : Except Failure (List (String × String)) :=
  if QuerySyntax raw then
    let pairs := queryPairs raw
    if (pairs.map Prod.fst).Nodup then .ok pairs else .error .duplicateKey
  else .error .malformed

def queryText : Value → String
  | .str s => s
  | .int n => toString n
  | _ => ""

def pairBytes (pair : String × String) : Bytes :=
  pair.1.toUTF8.data.toList ++ 0x3d :: pair.2.toUTF8.data.toList

def queryBytes : List (String × String) → Bytes
  | [] => []
  | [pair] => pairBytes pair
  | pair :: rest => pairBytes pair ++ 0x26 :: queryBytes rest

def encodedQueryPairs (query : Value) : List (String × String) :=
  (query.asObj?.getD []).map fun (name, value) => (name, queryText value)

/-- Canonical query: normalized known keys in UTF-8 order; no escaping is needed. -/
def encodeQuery (query : Value) : ByteArray :=
  ⟨(queryBytes (encodedQueryPairs query)).toArray⟩

end Fvapi.Wire
