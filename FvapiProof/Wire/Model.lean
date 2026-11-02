import FvapiSelf.Wire
import Fvapi.Wire.Records

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

theorem scalar_denotation (k : Scalar) (v : Value) :
    ScalarAccepts k v ↔ FvapiSpec.Wire.ScalarDenotes k v := Iff.rfl

theorem rule_denotation (r : Rule) (v : Value) :
    RuleAccepts r v ↔ FvapiSpec.Wire.RuleDenotes r v := Iff.rfl

mutual
theorem shape_denotation (s : Schema) (v : Value) :
    HasShape s v ↔ FvapiSpec.Wire.Shape s v := by
  cases s with
  | scalar k => exact scalar_denotation k v
  | array lo hi item =>
    cases v <;> simp only [HasShape, FvapiSpec.Wire.Shape]
    rename_i xs
    exact and_congr Iff.rfl (and_congr Iff.rfl
      (forall_congr' fun x => imp_congr_right fun _ => shape_denotation item x))
  | record fields rules =>
    cases v <;> simp only [HasShape, FvapiSpec.Wire.Shape]
    exact fields_shape_denotation fields _
  | tagged tag branches => exact branch_shape_denotation _ branches v
theorem fields_shape_denotation (fields : List Field) (v : Value) :
    FieldsHasShape fields v ↔ FvapiSpec.Wire.FieldsShape fields v := by
  cases fields with
  | nil => rfl
  | cons f rest =>
    obtain ⟨name, required, schema⟩ := f
    simp only [FieldsHasShape, FvapiSpec.Wire.FieldsShape]
    apply and_congr _ (fields_shape_denotation rest v)
    cases v.get? name with
    | none => rfl
    | some child => exact shape_denotation schema child
theorem branch_shape_denotation (tag : String) (branches : List (String × Schema)) (v : Value) :
    BranchHasShape tag branches v ↔ FvapiSpec.Wire.BranchShape tag branches v := by
  cases branches with
  | nil => rfl
  | cons b rest =>
    obtain ⟨name, schema⟩ := b
    simp only [BranchHasShape, FvapiSpec.Wire.BranchShape]
    split
    · exact shape_denotation schema v
    · exact branch_shape_denotation tag rest v
end

mutual
theorem known_denotation (s : Schema) (v : Value) :
    HasKnown s v ↔ FvapiSpec.Wire.Known s v := by
  cases s with
  | scalar _ => rfl
  | array lo hi item =>
    cases v <;> simp only [HasKnown, FvapiSpec.Wire.Known]
    exact forall_congr' fun x => imp_congr_right fun _ => known_denotation item x
  | record fields rules =>
    cases v <;> simp only [HasKnown, FvapiSpec.Wire.Known]
    exact and_congr Iff.rfl (fields_known_denotation fields _)
  | tagged tag branches => exact branch_known_denotation _ branches v
theorem fields_known_denotation (fields : List Field) (v : Value) :
    FieldsHasKnown fields v ↔ FvapiSpec.Wire.FieldsKnown fields v := by
  cases fields with
  | nil => rfl
  | cons f rest =>
    obtain ⟨name, required, schema⟩ := f
    simp only [FieldsHasKnown, FvapiSpec.Wire.FieldsKnown]
    exact and_congr
      (forall_congr' fun child => imp_congr_right fun _ => known_denotation schema child)
      (fields_known_denotation rest v)
theorem branch_known_denotation (tag : String) (branches : List (String × Schema)) (v : Value) :
    BranchHasKnown tag branches v ↔ FvapiSpec.Wire.BranchKnown tag branches v := by
  cases branches with
  | nil => rfl
  | cons b rest =>
    obtain ⟨name, schema⟩ := b
    simp only [BranchHasKnown, FvapiSpec.Wire.BranchKnown]
    split
    · exact known_denotation schema v
    · exact branch_known_denotation tag rest v
end

mutual
theorem refinements_denotation (s : Schema) (v : Value) :
    HasRefinements s v ↔ FvapiSpec.Wire.Refined s v := by
  cases s with
  | scalar _ => rfl
  | array lo hi item =>
    cases v <;> simp only [HasRefinements, FvapiSpec.Wire.Refined]
    exact forall_congr' fun x => imp_congr_right fun _ => refinements_denotation item x
  | record fields rules =>
    simp only [HasRefinements, FvapiSpec.Wire.Refined]
    exact and_congr Iff.rfl (fields_refinements_denotation fields v)
  | tagged tag branches => exact branch_refinements_denotation _ branches v
theorem fields_refinements_denotation (fields : List Field) (v : Value) :
    FieldsHasRefinements fields v ↔ FvapiSpec.Wire.FieldsRefined fields v := by
  cases fields with
  | nil => rfl
  | cons f rest =>
    obtain ⟨name, required, schema⟩ := f
    simp only [FieldsHasRefinements, FvapiSpec.Wire.FieldsRefined]
    exact and_congr
      (forall_congr' fun child => imp_congr_right fun _ => refinements_denotation schema child)
      (fields_refinements_denotation rest v)
theorem branch_refinements_denotation (tag : String)
    (branches : List (String × Schema)) (v : Value) :
    BranchHasRefinements tag branches v ↔ FvapiSpec.Wire.BranchRefined tag branches v := by
  cases branches with
  | nil => rfl
  | cons b rest =>
    obtain ⟨name, schema⟩ := b
    simp only [BranchHasRefinements, FvapiSpec.Wire.BranchRefined]
    split
    · exact refinements_denotation schema v
    · exact branch_refinements_denotation tag rest v
end

mutual
theorem projection_denotation (s : Schema) (v : Value) :
    project s v = FvapiSpec.Wire.project s v := by
  cases s with
  | scalar _ => rfl
  | array lo hi item =>
    cases v <;> simp only [project, FvapiSpec.Wire.project]
    rename_i xs
    exact congrArg (fun f => Value.arr (xs.map f))
      (funext fun child => projection_denotation item child)
  | record fields rules =>
    cases v <;> simp only [project, FvapiSpec.Wire.project]
    exact congrArg Value.object (fields_projection_denotation fields _)
  | tagged tag branches => exact branch_projection_denotation _ branches v
theorem fields_projection_denotation (fields : List Field) (v : Value) :
    projectFields fields v = FvapiSpec.Wire.projectFields fields v := by
  cases fields with
  | nil => rfl
  | cons f rest =>
    obtain ⟨name, required, schema⟩ := f
    simp only [projectFields, FvapiSpec.Wire.projectFields]
    rw [fields_projection_denotation rest v]
    cases v.get? name with
    | none => rfl
    | some child => simp only [projection_denotation schema child]
theorem branch_projection_denotation (tag : String) (branches : List (String × Schema))
    (v : Value) : projectBranch tag branches v = FvapiSpec.Wire.projectBranch tag branches v := by
  cases branches with
  | nil => rfl
  | cons b rest =>
    obtain ⟨name, schema⟩ := b
    simp only [projectBranch, FvapiSpec.Wire.projectBranch]
    split
    · exact projection_denotation schema v
    · exact branch_projection_denotation tag rest v
end

theorem tables_exact (route : Route) : routeTable route = FvapiSpec.Wire.reviewedTable route := by
  cases route <;> rfl

theorem status_exact : FvapiSelf.Wire.StatusExact := by
  intro route failure
  rfl

theorem decode_value_exact (s : Schema) (v out : Value) (strict : Bool) :
    decodeValue s v strict = some out ↔
      (strict = false ∨ FvapiSpec.Wire.Known s v) ∧ FvapiSpec.Wire.Denotes s v out := by
  simp only [decodeValue]
  split
  · rename_i h
    simp only [Option.some.injEq]
    constructor
    · intro e
      exact ⟨h.1.imp id ((known_denotation s v).mp), (shape_denotation s v).mp h.2.1,
        (refinements_denotation s v).mp h.2.2, e.symm.trans (projection_denotation s v)⟩
    · rintro ⟨_, _, _, e⟩
      exact (projection_denotation s v).trans e.symm
  · rename_i h
    simp only [reduceCtorEq, false_iff]
    rintro ⟨known, shape, refined, _⟩
    exact h ⟨known.imp id ((known_denotation s v).mpr), (shape_denotation s v).mpr shape,
      (refinements_denotation s v).mpr refined⟩

theorem record_round_trip {s : Schema} (record : Record s) :
    Record.ofValue? s record.toValue = some record := by
  have h : HasShape s record.value ∧ HasRefinements s record.value ∧
      project s record.value = record.value :=
    ⟨record.shape, record.refinements, record.normalized⟩
  unfold Record.ofValue? Record.toValue
  rw [dite_eq_left h]

theorem record_denotation {s : Schema} (record : Record s) :
    FvapiSpec.Wire.Denotes s record.toValue record.toValue :=
  ⟨(shape_denotation s record.value).mp record.shape,
    (refinements_denotation s record.value).mp record.refinements,
    record.normalized.symm.trans (projection_denotation s record.value)⟩

theorem record_of_denotation (s : Schema) (v : Value)
    (h : FvapiSpec.Wire.Denotes s v v) :
    ∃ record : Record s, record.toValue = v ∧ Record.ofValue? s v = some record := by
  let record : Record s := ⟨v, (shape_denotation s v).mpr h.1,
    (refinements_denotation s v).mpr h.2.1,
    (projection_denotation s v).trans h.2.2.symm⟩
  exact ⟨record, rfl, record_round_trip record⟩

#print axioms status_exact
#print axioms tables_exact
#print axioms record_round_trip

end FvapiProof.Wire
