import FvapiProof.Wire.Request
import FvapiProof.Json.Corollaries

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

/-- String-only schemas cannot hide non-string elements in `filterMap`. -/
theorem string_values (xs : List Value)
    (h : ∀ x ∈ xs, HasShape (.scalar .ident) x) :
    ∃ names : List String, xs = names.map Value.str ∧
      ∀ name ∈ names, ScalarAccepts .ident (.str name) := by
  induction xs with
  | nil => exact ⟨[], rfl, by intros name hm; cases hm⟩
  | cons x xs ih =>
    have hx := h x (by simp)
    have ht : ∀ y ∈ xs, HasShape (.scalar .ident) y :=
      fun y hy => h y (by simp only [List.mem_cons]; exact Or.inr hy)
    obtain ⟨names, hn, hi⟩ := ih ht
    have hstr : ∃ name, x = .str name := by
      cases x <;> simp only [HasShape, ScalarAccepts] at hx
      exact ⟨_, rfl⟩
    obtain ⟨name, rfl⟩ := hstr
    refine ⟨name :: names, ?_, ?_⟩
    · simp only [List.map_cons, hn]
    · intro n hm
      cases hm with
      | head => exact hx
      | tail _ hm => exact hi n hm

theorem string_filter_map (names : List String) :
    (names.map Value.str).filterMap Value.asStr? = names := by
  induction names with
  | nil => rfl
  | cons name rest ih => simp only [List.map_cons, List.filterMap_cons, Value.asStr?, ih]

theorem feature_complete {v : Value} {names : List String}
    (h : FvapiSpec.Wire.FeatureDeclaration v names) : featureNames? v = some names := by
  unfold FvapiSpec.Wire.FeatureDeclaration at h
  unfold featureNames?
  cases hv : v.get? "required_features" with
  | none =>
    simp only [hv] at h
    exact congrArg some h.symm
  | some value =>
    simp only [hv] at h
    cases value with
    | arr xs =>
      obtain ⟨hx, hlen, hnodup, hi⟩ := h
      subst xs
      dsimp only
      rw [string_filter_map]
      have hs : HasShape (.array 0 32 (.scalar .ident)) (.arr (names.map Value.str)) := by
        refine ⟨Nat.zero_le _, ?_, ?_⟩
        · simpa only [List.length_map] using hlen
        · intro x hm
          obtain ⟨name, hname, rfl⟩ := List.mem_map.mp hm
          exact (scalar_denotation _ _).mpr (hi name hname)
      rw [ite_eq_left (And.intro hs hnodup)]
    | null | bool _ | int _ | str _ | obj _ => exact False.elim h

theorem feature_sound {v : Value} {names : List String} (h : featureNames? v = some names) :
    FvapiSpec.Wire.FeatureDeclaration v names := by
  unfold featureNames? at h
  cases hv : v.get? "required_features" with
  | none =>
    simp only [hv, Option.some.injEq] at h
    unfold FvapiSpec.Wire.FeatureDeclaration
    rw [hv]
    exact h.symm
  | some value =>
    simp only [hv] at h
    cases value with
    | arr xs =>
      dsimp only at h
      split at h
      · rename_i hs
        obtain ⟨declared, hx, hi⟩ := string_values xs hs.1.2.2
        subst xs
        rw [string_filter_map] at h hs
        have hn := Option.some.inj h
        subst names
        unfold FvapiSpec.Wire.FeatureDeclaration
        rw [hv]
        exact ⟨rfl, by simpa only [HasShape, List.length_map] using hs.1.2.1,
          hs.2, fun n hn => (scalar_denotation _ _).mp (hi n hn)⟩
      · cases h
    | null | bool _ | int _ | str _ | obj _ => cases h

@[simp] theorem response_table (route : Route) (status : Nat) :
    responseTable route status = FvapiSpec.Wire.responseTable route status := by
  unfold responseTable FvapiSpec.Wire.responseTable
  rw [tables_exact]

theorem response_complete {route : Route} {status : Nat} {body : ByteArray}
    {result : ResponseResult} (h : FvapiSpec.Wire.ResponseOutcome route status body result) :
    decideResponse route status body = result := by
  cases h with
  | raw hr hs =>
    rw [decideResponse, ite_eq_left (And.intro hr hs)]
  | jsonBad hn hj =>
    rw [decideResponse, ite_eq_right hn]
    cases hd : Fvapi.Json.decode body with
    | error _ => rfl
    | ok v =>
      cases v with
      | obj ms => exact False.elim (hj ms ((FvapiProof.Json.decode_exact _ _).mp hd))
      | null | bool _ | int _ | str _ | arr _ => rfl
  | @featuresBad ms hn hj hf =>
    rw [decideResponse, ite_eq_right hn, (FvapiProof.Json.decode_exact _ _).mpr hj]
    dsimp only
    have hnone : featureNames? (.obj ms) = none := by
      cases hnames : featureNames? (.obj ms) with
      | none => rfl
      | some names => exact False.elim (hf names (feature_sound hnames))
    rw [hnone]
  | @unsupported ms names hn hj hf hne =>
    rw [decideResponse, ite_eq_right hn, (FvapiProof.Json.decode_exact _ _).mpr hj]
    dsimp only
    rw [feature_complete hf]
    cases names with
    | nil => exact False.elim (hne rfl)
    | cons _ _ => rfl
  | @recordBad ms hn hj hf ht =>
    rw [decideResponse, ite_eq_right hn, (FvapiProof.Json.decode_exact _ _).mpr hj]
    dsimp only
    rw [feature_complete hf]
    dsimp only
    rw [response_table]
    cases hr : FvapiSpec.Wire.responseTable route status with
    | none => rfl
    | some table =>
      have hb := ht table (by simp only [hr, Option.mem_def])
      have hbad : ¬ (HasShape table.schema (.obj ms) ∧ HasRefinements table.schema (.obj ms)) := by
        intro hs
        exact hb ⟨(shape_denotation _ _).mp hs.1, (refinements_denotation _ _).mp hs.2⟩
      dsimp only
      rw [ite_eq_right hbad]
  | @ok ms table hn hj hf ht hs hr =>
    rw [decideResponse, ite_eq_right hn, (FvapiProof.Json.decode_exact _ _).mpr hj]
    dsimp only
    rw [feature_complete hf]
    dsimp only
    rw [response_table, ht]
    dsimp only
    have hgood := And.intro ((shape_denotation _ _).mpr hs) ((refinements_denotation _ _).mpr hr)
    rw [ite_eq_left hgood, projection_denotation]

theorem response_sound (route : Route) (status : Nat) (body : ByteArray) :
    FvapiSpec.Wire.ResponseOutcome route status body (decideResponse route status body) := by
  unfold decideResponse
  split
  · rename_i h
    exact FvapiSpec.Wire.ResponseOutcome.raw h.1 h.2
  · rename_i hn
    cases hd : Fvapi.Json.decode body with
    | error _ =>
      apply FvapiSpec.Wire.ResponseOutcome.jsonBad hn
      intro ms hs
      have he := (FvapiProof.Json.decode_exact _ _).mpr hs
      rw [hd] at he
      cases he
    | ok v =>
      have hj := (FvapiProof.Json.decode_exact _ _).mp hd
      cases v with
      | null | bool _ | int _ | str _ | arr _ =>
        apply FvapiSpec.Wire.ResponseOutcome.jsonBad hn
        intro ms hs
        have he := (FvapiProof.Json.decode_exact _ _).mpr hs
        rw [hd] at he
        cases he
      | obj ms =>
        dsimp only
        cases hf : featureNames? (.obj ms) with
        | none =>
          apply FvapiSpec.Wire.ResponseOutcome.featuresBad hn hj
          intro names hs
          have he := feature_complete hs
          rw [hf] at he
          cases he
        | some names =>
          have hfeatures := feature_sound hf
          cases names with
          | cons name names =>
            exact FvapiSpec.Wire.ResponseOutcome.unsupported hn hj hfeatures (by simp)
          | nil =>
            dsimp only
            cases ht : responseTable route status with
            | none =>
              apply FvapiSpec.Wire.ResponseOutcome.recordBad hn hj hfeatures
              intro table hm
              rw [← response_table, ht] at hm
              cases hm
            | some table =>
              dsimp only
              split
              · rename_i hs
                rw [projection_denotation]
                apply FvapiSpec.Wire.ResponseOutcome.ok hn hj hfeatures
                · simpa only [response_table] using ht
                · exact (shape_denotation _ _).mp hs.1
                · exact (refinements_denotation _ _).mp hs.2
              · rename_i hs
                apply FvapiSpec.Wire.ResponseOutcome.recordBad hn hj hfeatures
                intro other hm
                have he : other = table := by
                  rw [← response_table, ht] at hm
                  exact (Option.some.inj (Option.mem_def.mp hm)).symm
                subst other
                intro hgood
                exact hs ⟨(shape_denotation _ _).mpr hgood.1,
                  (refinements_denotation _ _).mpr hgood.2⟩

theorem response_exact : FvapiSelf.Wire.ResponseExact := by
  intro route status body result
  constructor
  · intro h
    rw [← h]
    exact response_sound route status body
  · exact response_complete

#print axioms response_exact

end FvapiProof.Wire
