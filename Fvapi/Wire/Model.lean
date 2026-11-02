import Std
import Fvapi.Wire.Equality

namespace Fvapi.Wire

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

def ScalarAccepts : Scalar → Value → Prop
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

def RuleAccepts (rule : Rule) (v : Value) : Prop :=
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
  | .keyValue => ScalarAccepts
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
def HasShape : Schema → Value → Prop
  | .scalar k, v => ScalarAccepts k v
  | .array lo hi item, .arr xs => lo ≤ xs.length ∧ xs.length ≤ hi ∧
      ∀ x ∈ xs, HasShape item x
  | .record fs _, .obj ms => FieldsHasShape fs (.obj ms)
  | .tagged tag bs, v => BranchHasShape (text v tag) bs v
  | _, _ => False
def FieldsHasShape : List Field → Value → Prop
  | [], _ => True
  | (name, required, schema) :: fs, v =>
      (match v.get? name with
       | none => required = false
       | some child => HasShape schema child) ∧ FieldsHasShape fs v
def BranchHasShape (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => False
  | (name, schema) :: rest, v =>
      if tag = name then HasShape schema v else BranchHasShape tag rest v
end

mutual
/-- Stage 3 follows expected kinds; an object in a scalar slot is not a record. -/
def HasKnown : Schema → Value → Prop
  | .scalar _, _ => True
  | .array _ _ item, .arr xs => ∀ x ∈ xs, HasKnown item x
  | .record fs _, .obj ms =>
      (∀ kv ∈ ms, kv.1 ∈ fs.map Prod.fst) ∧ FieldsHasKnown fs (.obj ms)
  | .tagged tag bs, v => BranchHasKnown (text v tag) bs v
  | _, _ => True
def FieldsHasKnown : List Field → Value → Prop
  | [], _ => True
  | (name, _, schema) :: fs, v =>
      (∀ child ∈ v.get? name, HasKnown schema child) ∧ FieldsHasKnown fs v
def BranchHasKnown (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => True
  | (name, schema) :: rest, v =>
      if tag = name then HasKnown schema v else BranchHasKnown tag rest v
end

mutual
def HasRefinements : Schema → Value → Prop
  | .scalar _, _ => True
  | .array _ _ item, .arr xs => ∀ x ∈ xs, HasRefinements item x
  | .record fs rules, v => (∀ rule ∈ rules, RuleAccepts rule v) ∧ FieldsHasRefinements fs v
  | .tagged tag bs, v => BranchHasRefinements (text v tag) bs v
  | _, _ => True
def FieldsHasRefinements : List Field → Value → Prop
  | [], _ => True
  | (name, _, schema) :: fs, v =>
      (∀ child ∈ v.get? name, HasRefinements schema child) ∧ FieldsHasRefinements fs v
def BranchHasRefinements (tag : String) : List (String × Schema) → Value → Prop
  | [], _ => True
  | (name, schema) :: rest, v =>
      if tag = name then HasRefinements schema v else BranchHasRefinements tag rest v
end

mutual
/-- Known-field projection, with canonical member order at every retained record. -/
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

instance scalarDecidable (kind : Scalar) (v : Value) : Decidable (ScalarAccepts kind v) := by
  cases kind <;> cases v <;> simp only [ScalarAccepts, bytesBetween, hex64]
  all_goals first | infer_instance | (split <;> infer_instance)

instance ruleDecidable (rule : Rule) (v : Value) : Decidable (RuleAccepts rule v) := by
  cases rule <;> simp only [RuleAccepts]
  all_goals repeat' first | infer_instance | split

mutual
def shapeDecidable (schema : Schema) (v : Value) : Decidable (HasShape schema v) := by
  cases schema with
  | scalar k => exact scalarDecidable k v
  | array lo hi item =>
    letI : DecidablePred (HasShape item) := fun x => shapeDecidable item x
    cases v <;> simp only [HasShape] <;> infer_instance
  | record fields rules =>
    cases v <;> simp only [HasShape]
    all_goals first | exact fieldsShapeDecidable fields _ | infer_instance
  | tagged tag branches => exact branchShapeDecidable (text v tag) branches v
def fieldsShapeDecidable (fields : List Field) (v : Value) : Decidable (FieldsHasShape fields v) :=
  match fields with
  | [] => inferInstanceAs (Decidable True)
  | (name, required, schema) :: rest => by
    simp only [FieldsHasShape]
    letI := fieldsShapeDecidable rest v
    match v.get? name with
    | none => infer_instance
    | some child => letI := shapeDecidable schema child; infer_instance
def branchShapeDecidable (tag : String) (branches : List (String × Schema)) (v : Value) :
    Decidable (BranchHasShape tag branches v) :=
  match branches with
  | [] => inferInstanceAs (Decidable False)
  | (name, schema) :: rest => by
    simp only [BranchHasShape]
    split
    · exact shapeDecidable schema v
    · exact branchShapeDecidable tag rest v
end

mutual
def knownDecidable (schema : Schema) (v : Value) : Decidable (HasKnown schema v) := by
  cases schema with
  | scalar _ => exact inferInstanceAs (Decidable True)
  | array lo hi item =>
    letI : DecidablePred (HasKnown item) := fun x => knownDecidable item x
    cases v <;> simp only [HasKnown] <;> infer_instance
  | record fields rules =>
    cases v with
    | obj ms =>
      letI := fieldsKnownDecidable fields (.obj ms)
      exact inferInstanceAs (Decidable
        ((∀ kv ∈ ms, kv.1 ∈ fields.map Prod.fst) ∧ FieldsHasKnown fields (.obj ms)))
    | null | bool _ | int _ | str _ | arr _ => exact inferInstanceAs (Decidable True)
  | tagged tag branches => exact branchKnownDecidable (text v tag) branches v
def fieldsKnownDecidable (fields : List Field) (v : Value) : Decidable (FieldsHasKnown fields v) :=
  match fields with
  | [] => inferInstanceAs (Decidable True)
  | (name, _, schema) :: rest => by
    simp only [FieldsHasKnown]
    letI := fieldsKnownDecidable rest v
    letI : DecidablePred (HasKnown schema) := fun x => knownDecidable schema x
    infer_instance
def branchKnownDecidable (tag : String) (branches : List (String × Schema)) (v : Value) :
    Decidable (BranchHasKnown tag branches v) :=
  match branches with
  | [] => inferInstanceAs (Decidable True)
  | (name, schema) :: rest => by
    simp only [BranchHasKnown]
    split
    · exact knownDecidable schema v
    · exact branchKnownDecidable tag rest v
end

mutual
def refinementsDecidable (schema : Schema) (v : Value) :
    Decidable (HasRefinements schema v) := by
  cases schema with
  | scalar _ => exact inferInstanceAs (Decidable True)
  | array lo hi item =>
    letI : DecidablePred (HasRefinements item) := fun x => refinementsDecidable item x
    cases v <;> simp only [HasRefinements] <;> infer_instance
  | record fields rules =>
    letI := fieldsRefinementsDecidable fields v
    exact inferInstanceAs (Decidable ((∀ rule ∈ rules, RuleAccepts rule v) ∧
      FieldsHasRefinements fields v))
  | tagged tag branches => exact branchRefinementsDecidable (text v tag) branches v
def fieldsRefinementsDecidable (fields : List Field) (v : Value) :
    Decidable (FieldsHasRefinements fields v) :=
  match fields with
  | [] => inferInstanceAs (Decidable True)
  | (name, _, schema) :: rest => by
    simp only [FieldsHasRefinements]
    letI := fieldsRefinementsDecidable rest v
    letI : DecidablePred (HasRefinements schema) := fun x => refinementsDecidable schema x
    infer_instance
def branchRefinementsDecidable (tag : String) (branches : List (String × Schema)) (v : Value) :
    Decidable (BranchHasRefinements tag branches v) :=
  match branches with
  | [] => inferInstanceAs (Decidable True)
  | (name, schema) :: rest => by
    simp only [BranchHasRefinements]
    split
    · exact refinementsDecidable schema v
    · exact branchRefinementsDecidable tag rest v
end

instance (s : Schema) (v : Value) : Decidable (HasShape s v) := shapeDecidable s v
instance (s : Schema) (v : Value) : Decidable (HasKnown s v) := knownDecidable s v
instance (s : Schema) (v : Value) : Decidable (HasRefinements s v) := refinementsDecidable s v

/-- Generic structural validator; every record conversion uses this one interpreter. -/
def decodeValue (schema : Schema) (v : Value) (strict : Bool := false) : Option Value :=
  if (strict = false ∨ HasKnown schema v) ∧ HasShape schema v ∧ HasRefinements schema v then
    some (project schema v)
  else none

/-- Schema-indexed records retain their typed shape and exact known-field encoding. -/
structure Record (schema : Schema) where
  value : Value
  shape : HasShape schema value
  refinements : HasRefinements schema value
  normalized : project schema value = value

end Fvapi.Wire
