import FvapiProof.Wire.Response
import FvapiProof.Wire.Tables

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

theorem object_of_record_shape (schema : Schema) (v : Value)
    (hk : FvapiSpec.Wire.isRecord schema = true) (hs : HasShape schema v) :
    ∃ members, v = .obj members := by
  cases schema with
  | scalar _ | array _ _ _ | tagged _ _ => cases hk
  | record _ _ =>
    cases v with
    | obj ms => exact ⟨ms, rfl⟩
    | null | bool _ | int _ | str _ | arr _ => exact False.elim hs

theorem json_not_raw (route : Route) (status : Nat) (table : ResponseTable)
    (ht : FvapiSpec.Wire.responseTable route status = some table) (hm : table.mode = .json) :
    ¬ (route = .bundle ∧ status = 200) := by
  rintro ⟨rfl, rfl⟩
  have he : BodyMode.bytes = table.mode :=
    Option.some.inj (congrArg (Option.map ResponseTable.mode) ht)
  have bad := he.trans hm
  cases bad

theorem response_encode : FvapiSelf.Wire.ResponseEncode := by
  intro route status res h
  cases res with
  | bytes bytes =>
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨rfl, rfl⟩
  | json v =>
    obtain ⟨table, ht, hm, hshape, hrefined, hv, hf⟩ := h
    have hs := (shape_denotation table.schema v).mpr hshape
    have hr := (refinements_denotation table.schema v).mpr hrefined
    have hn := json_not_raw route status table ht hm
    have hk := json_response_record route status table ht hm
    obtain ⟨members, rfl⟩ := object_of_record_shape table.schema v hk hs
    constructor
    · rw [FvapiSpec.Wire.projectResponse, ht]
      dsimp only
      rw [encodeResponse, decideResponse, ite_eq_right hn, FvapiProof.Json.print_decode _ hv]
      dsimp only
      rw [feature_complete hf]
      dsimp only
      rw [response_table, ht]
      dsimp only
      rw [ite_eq_left (And.intro hs hr), projection_denotation]
    · exact FvapiProof.Json.print_exact _

/-- A projection fixed point recovers the normalized round trip as a corollary. -/
theorem response_encode_normalized (route : Route) (status : Nat) (res : Response)
    (h : FvapiSpec.Wire.ResponseAdmissible route status res)
    (hn : FvapiSpec.Wire.projectResponse route status res = res) :
    decideResponse route status (encodeResponse res) = .ok res ∧
      FvapiSpec.Wire.responseBodyLaw res (encodeResponse res) := by
  have result := response_encode route status res h
  rw [hn] at result
  exact result

theorem additive_me_admissible :
    FvapiSpec.Wire.ResponseAdmissible .me 200
      (.json (.obj [("caller_id", .str "a"), ("extra", .int 0)])) := by
  let table := (FvapiSpec.Wire.reviewedTable .me).responses[0]!
  refine ⟨table, rfl, rfl, ?_, ?_, ?_, rfl⟩
  · exact (shape_denotation _ _).mp (by decide +kernel)
  · exact (refinements_denotation _ _).mp (by decide +kernel)
  · unfold FvapiSpec.Json.Valid
    decide +kernel

theorem additive_me_response_encode :
    decideResponse .me 200
      (encodeResponse (.json (.obj [("caller_id", .str "a"), ("extra", .int 0)]))) =
      .ok (.json (.object [("caller_id", .str "a")])) := by
  exact (response_encode .me 200 _ additive_me_admissible).1

#print axioms response_encode
#print axioms response_encode_normalized
#print axioms additive_me_admissible

end FvapiProof.Wire
