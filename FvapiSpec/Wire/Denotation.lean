import Std
import Fvapi.Wire.Schema
import FvapiSpec.Json

namespace FvapiSpec.Wire

open Fvapi.Wire Fvapi.Json

private def lowerDigit (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9')
private def hexDigit (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')
private def unreserved (c : Char) : Bool :=
  lowerDigit c || ('A' ≤ c && c ≤ 'Z') || c == '.' || c == '_' || c == '~' || c == '-'
private def bytesBetween (lo hi : Nat) (s : String) : Prop :=
  lo ≤ s.utf8ByteSize ∧ s.utf8ByteSize ≤ hi
private def hex64 (s : String) : Prop := s.utf8ByteSize = 64 ∧ s.toList.all hexDigit = true

def ScalarDenotes : Scalar → Value → Prop
  | .any, _ => True
  | .bool, .bool _ => True
  | .nat, .int n => 0 ≤ n ∧ n ≤ 9007199254740991
  | .pos, .int n => 1 ≤ n ∧ n ≤ 9007199254740991
  | .boundedNat lo hi, .int n => (lo : Int) ≤ n ∧ n ≤ (hi : Int)
  | .ident, .str t => bytesBetween 1 128 t ∧
      t.toList.all (fun c => lowerDigit c || c == '.' || c == '_' || c == '-') = true ∧
      ((t.toList.head?.map lowerDigit).getD false) = true ∧
      ((t.toList.getLast?.map lowerDigit).getD false) = true
  | .sha256, .str t => hex64 t
  | .profileId, .str t => match t.splitOn ":" with
      | ["sha256", h] => hex64 h
      | _ => False
  | .digest, .str t => match t.splitOn ":" with
      | [tag, hash] => bytesBetween 1 16 tag ∧ tag.toList.all lowerDigit = true ∧ hex64 hash
      | _ => False
  | .token, .str t => bytesBetween 1 128 t ∧ t.toList.all unreserved = true
  | .cursor, .str t => bytesBetween 1 1024 t ∧ t.toList.all
      (fun c => lowerDigit c || ('A' ≤ c && c ≤ 'Z') || c == '_' || c == '-') = true
  | .label, .str t => bytesBetween 1 256 t ∧
      t.toList.all (fun c => 0x21 ≤ c.toNat && c.toNat ≤ 0x7e) = true
  | .spdx, .str t => bytesBetween 1 256 t ∧
      t.toList.all (fun c => 0x20 ≤ c.toNat && c.toNat ≤ 0x7e) = true ∧
      t.toList.head? ≠ some ' ' ∧ t.toList.getLast? ≠ some ' '
  | .text lo hi, .str t => bytesBetween lo hi t
  | .source, .str t => bytesBetween 1 65536 t ∧ '\x00' ∉ t.toList ∧
      ∃ c ∈ t.toList, c ≠ ' ' ∧ c ≠ '\t' ∧ c ≠ '\n' ∧ c ≠ '\r'
  | .leanName, .str t => bytesBetween 1 1024 t ∧
      ∀ c ∈ t.toList, 0x20 ≤ c.toNat ∧ c.toNat ≠ 0x7f
  | .absPath, .str t => bytesBetween 1 4096 t ∧ t.toList.head? = some '/' ∧
      '\x00' ∉ t.toList
  | .oneOf xs, .str t => t ∈ xs
  | _, _ => False

private def present (v : Value) (k : String) : Bool := (v.get? k).isSome
private def text (v : Value) (k : String) : String :=
  ((v.get? k).bind Value.asStr?).getD ""
private def number (v : Value) (k : String) : Int :=
  ((v.get? k).bind Value.asInt?).getD (-1)
private def items (v : Value) (k : String) : List Value :=
  ((v.get? k).bind Value.asArr?).getD []

def RuleDenotes (rule : Rule) (v : Value) : Prop :=
  match rule with
  | .path hash path => text v path = "/v1/bundles/" ++ text v hash
  | .presenceBool member flag =>
      present v member = (((v.get? flag).bind Value.asBool?).getD false)
  | .presenceString member tag value equal =>
      present v member = (if equal then text v tag == value else text v tag != value)
  | .page count members cursor first =>
      ((items v members).length : Int) ≤ number v count ∧
      (present v cursor = true → items v members ≠ [] ∧
        ((items v members).length : Int) < number v count) ∧
      (first = true → (present v cursor = true ↔
        ((items v members).length : Int) < number v count))
  | .keyValue => ScalarDenotes
      (if text v "key" = "spec_id" then .ident
       else if text v "key" = "artifact_sha256" then .sha256 else .digest)
      ((v.get? "value").getD .null)
  | .rowOrigin =>
      if text v "origin" = "request" then
        present v "statement" = true ∧ number v "count" = 1 ∧
        ((v.get? "keys").getD .null).get? "spec_id" = none ∧
        ((v.get? "keys").getD .null).get? "statement_digest" = none
      else
        let keys := (v.get? "keys").getD .null
        present keys "spec_id" = true ∨ present keys "artifact_sha256" = true ∨
          present keys "statement_digest" = true
  | .lineage => text v "lineage" =
      if text v "name" = "nanoda" then "nanoda"
      else if text v "name" = "con-leche" ∨ text v "name" = "con-ron" then "con" else "lean"
  | .keysNonempty member =>
      let keys := (v.get? member).getD .null
      present keys "spec_id" = true ∨ present keys "artifact_sha256" = true ∨
        present keys "statement_digest" = true
  | .uniqueStrings member =>
      ((items v member).filterMap Value.asStr?).Nodup
  | .uniqueField member field =>
      ((items v member).filterMap fun item => (item.get? field).bind Value.asStr?).Nodup
  | .changes =>
      (((v.get? "more").bind Value.asBool?).getD false = true → items v "rows" ≠ []) ∧
      (items v "rows").Pairwise (fun a b => number a "seq" < number b "seq") ∧
      (∀ last ∈ (items v "rows").getLast?, number last "seq" = number v "last_seq")

mutual
/-- Types alone; cross-member refinements have their own client stage. -/
def Shape : Schema → Value → Prop
  | .scalar k, v => ScalarDenotes k v
  | .array lo hi item, .arr xs => lo ≤ xs.length ∧ xs.length ≤ hi ∧
      ∀ x ∈ xs, Shape item x
  | .record fs _, .obj ms => FieldsShape fs (.obj ms)
  | .tagged tag bs, v => BranchShape (text v tag) bs v
  | _, _ => False
def FieldsShape : List Field → Value → Prop
  | [], _ => True
  | (name, required, schema) :: fs, v =>
      (match v.get? name with
       | none => required = false
       | some child => Shape schema child) ∧ FieldsShape fs v
def BranchShape (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => False
  | (name, schema) :: rest, v =>
      if tag = name then Shape schema v else BranchShape tag rest v
end

mutual
/-- Stage 3 follows expected kinds; an object in a scalar slot is not a record. -/
def Known : Schema → Value → Prop
  | .scalar _, _ => True
  | .array _ _ item, .arr xs => ∀ x ∈ xs, Known item x
  | .record fs _, .obj ms =>
      (∀ kv ∈ ms, kv.1 ∈ fs.map Prod.fst) ∧ FieldsKnown fs (.obj ms)
  | .tagged tag bs, v => BranchKnown (text v tag) bs v
  | _, _ => True
def FieldsKnown : List Field → Value → Prop
  | [], _ => True
  | (name, _, schema) :: fs, v =>
      (∀ child ∈ v.get? name, Known schema child) ∧ FieldsKnown fs v
def BranchKnown (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => True
  | (name, schema) :: rest, v =>
      if tag = name then Known schema v else BranchKnown tag rest v
end

mutual
def Refined : Schema → Value → Prop
  | .scalar _, _ => True
  | .array _ _ item, .arr xs => ∀ x ∈ xs, Refined item x
  | .record fs rules, v => (∀ rule ∈ rules, RuleDenotes rule v) ∧ FieldsRefined fs v
  | .tagged tag bs, v => BranchRefined (text v tag) bs v
  | _, _ => True
def FieldsRefined : List Field → Value → Prop
  | [], _ => True
  | (name, _, schema) :: fs, v =>
      (∀ child ∈ v.get? name, Refined schema child) ∧ FieldsRefined fs v
def BranchRefined (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => True
  | (name, schema) :: rest, v =>
      if tag = name then Refined schema v else BranchRefined tag rest v
end

mutual
/-- Known-field denotation, with canonical member order at every retained record. -/
def project : Schema → Value → Value
  | .scalar _, v => v
  | .array _ _ item, .arr xs => .arr (xs.map (project item))
  | .record fs _, .obj ms => .object (projectFields fs (.obj ms))
  | .tagged tag bs, v => projectBranch (text v tag) bs v
  | _, v => v
def projectFields : List Field → Value → List (String × Value)
  | [], _ => []
  | (name, _, schema) :: fs, v =>
      (match v.get? name with
       | none => []
       | some child => [(name, project schema child)]) ++ projectFields fs v
def projectBranch (tag : String) : List (String × Schema) → Value → Value
  | [], v => v
  | (name, schema) :: rest, v =>
      if tag = name then project schema v else projectBranch tag rest v
end

/-- Responses ignore additive members; strict request acceptance adds `Known`. -/
def Denotes (schema : Schema) (input output : Value) : Prop :=
  Shape schema input ∧ Refined schema input ∧ output = project schema input

end FvapiSpec.Wire
