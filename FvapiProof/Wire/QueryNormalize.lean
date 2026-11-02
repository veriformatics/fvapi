import FvapiProof.Wire.QueryScalar
import FvapiProof.Json.Access

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

theorem route_query_field (route : Route) (f : QueryField)
    (hf : f ∈ (FvapiSpec.Wire.reviewedTable route).query) :
    QueryString f.name ∧ FvapiSpec.Wire.queryKindEncodable f.kind = true := by
  have h := all_tables_admissible route
  simp only [FvapiSpec.Wire.tableAdmissible, Bool.and_eq_true] at h
  have hp := List.all_eq_true.mp h.1.1.2 f hf
  simp only [Bool.and_eq_true] at hp
  have hn : f.name ≠ "" := by
    intro he
    have hz := hp.1.1
    rw [he] at hz
    cases hz
  exact ⟨⟨string_bytes_nonempty f.name hn, hp.1.2⟩, hp.2⟩

theorem valid_object_keys (ms : List (String × Value)) (h : FvapiSpec.Json.Valid (.obj ms)) :
    (ms.map Prod.fst).Nodup ∧ Value.object ms = .obj ms := by
  have hk := h.2.2.2
  simp only [FvapiSpec.Json.keysAscend, Bool.and_eq_true, decide_eq_true_eq] at hk
  have hn := hk.1.imp String.ne_of_lt
  have hs : ms.Pairwise (fun a b => decide (a.1 ≤ b.1) = true) := by
    apply (List.pairwise_map.mp hk.1).imp
    intro a b hab
    simp only [decide_eq_true_eq]
    exact Std.le_of_lt hab
  exact ⟨hn, congrArg Value.obj (List.mergeSort_of_pairwise hs)⟩

theorem get_of_member (ms : List (String × Value)) (name : String) (v : Value)
    (hn : (ms.map Prod.fst).Nodup) (hm : (name, v) ∈ ms) :
    (Value.obj ms).get? name = some v := by
  induction ms with
  | nil => cases hm
  | cons kv rest ih =>
    obtain ⟨key, value⟩ := kv
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.mem_cons] at hm
    rcases hm with he | hm
    · cases he
      simp [Value.get?]
    · have hk : key ≠ name := by
        intro he
        subst key
        exact hn.1 (List.mem_map.mpr ⟨(name, v), hm, rfl⟩)
      have hi := ih hn.2 hm
      simpa [Value.get?, hk] using hi

theorem query_field_shape (fields : List QueryField) (ms : List (String × Value))
    (f : QueryField) (value : Value) (hf : f ∈ fields)
    (hs : HasShape (querySchema fields) (.obj ms))
    (hg : (Value.obj ms).get? f.name = some value) : ScalarAccepts f.kind value := by
  induction fields with
  | nil => cases hf
  | cons field rest ih =>
    simp only [querySchema, HasShape, List.map_cons, FieldsHasShape] at hs
    simp only [List.mem_cons] at hf
    rcases hf with he | hf
    · subst field
      have hh := hs.1
      rw [hg] at hh
      exact hh
    · exact ih hf hs.2

theorem query_known_names (fields : List QueryField) (ms : List (String × Value))
    (hk : HasKnown (querySchema fields) (.obj ms)) :
    ∀ kv ∈ ms, kv.1 ∈ fields.map QueryField.name := by
  simp only [querySchema, HasKnown, List.map_map, Function.comp_def] at hk
  exact hk.1

theorem find_query_field (fields : List QueryField) (name : String)
    (hn : name ∈ fields.map QueryField.name) :
    ∃ f, fields.find? (·.name == name) = some f ∧ f ∈ fields ∧ f.name = name := by
  induction fields with
  | nil => cases hn
  | cons field rest ih =>
    by_cases he : field.name = name
    · exact ⟨field, by simp [he], by simp, he⟩
    · have ht : name ∈ rest.map QueryField.name := by
        simp only [List.map_cons, List.mem_cons] at hn
        rcases hn with hn | hn
        · exact False.elim (he hn.symm)
        · exact hn
      obtain ⟨f, hfind, hf, hname⟩ := ih ht
      exact ⟨f, by simpa [he] using hfind, by simp [hf], hname⟩

theorem query_member_round_trip (route : Route) (ms : List (String × Value))
    (hs : HasShape (querySchema (FvapiSpec.Wire.reviewedTable route).query) (.obj ms))
    (hk : HasKnown (querySchema (FvapiSpec.Wire.reviewedTable route).query) (.obj ms))
    (hn : (ms.map Prod.fst).Nodup) (name : String) (value : Value) (hm : (name, value) ∈ ms) :
    QueryString name ∧ QueryString (queryText value) ∧
      queryScalar (((((FvapiSpec.Wire.reviewedTable route).query).find?
        (·.name == name)).map (·.kind)).getD .any) (queryText value) = value := by
  have hnames := query_known_names _ _ hk (name, value) hm
  obtain ⟨f, hf, hmem, hname⟩ := find_query_field _ name hnames
  have hget : (Value.obj ms).get? f.name = some value := by
    rw [hname]
    exact get_of_member ms name value hn hm
  have hshape := query_field_shape _ ms f value hmem hs hget
  have hkind := route_query_field route f hmem
  have hv := query_scalar_round_trip f.kind value hkind.2 hshape
  refine ⟨?_, hv.1, ?_⟩
  · rw [← hname]
    exact hkind.1
  · rw [hf]
    exact hv.2

theorem get_some_member (ms : List (String × Value)) (name : String) (value : Value)
    (hg : (Value.obj ms).get? name = some value) : (name, value) ∈ ms := by
  obtain ⟨before, after, h, _⟩ := (FvapiProof.Json.get_law.1 ms name value).mp hg
  rw [h]
  simp

theorem query_defaults_empty (fields : List QueryField) (ms : List (String × Value))
    (h : ∀ f ∈ fields, f.default?.isSome = true → ((Value.obj ms).get? f.name).isSome = true) :
    fields.filterMap (fun f =>
      if (encodedQueryPairs (.obj ms)).any (·.1 == f.name) then none
      else f.default?.map fun text => (f.name, queryScalar f.kind text)) = [] := by
  induction fields with
  | nil => rfl
  | cons field rest ih =>
    have hh : (if (encodedQueryPairs (.obj ms)).any (·.1 == field.name) then none
        else field.default?.map fun text => (field.name, queryScalar field.kind text)) = none := by
      by_cases ha : (encodedQueryPairs (.obj ms)).any (·.1 == field.name) = true
      · rw [ite_eq_left ha]
      · rw [ite_eq_right ha]
        cases hd : field.default? with
        | none => rfl
        | some _ =>
          have hp := h field (by simp) (by rw [hd]; rfl)
          cases hg : (Value.obj ms).get? field.name with
          | none => rw [hg] at hp; cases hp
          | some value =>
            have hm := get_some_member ms field.name value hg
            have hpair : (field.name, queryText value) ∈ encodedQueryPairs (.obj ms) :=
              List.mem_map.mpr ⟨(field.name, value), hm, rfl⟩
            have he : (encodedQueryPairs (.obj ms)).any (·.1 == field.name) = true :=
              List.any_eq_true.mpr ⟨_, hpair, by simp⟩
            exact False.elim (ha he)
    rw [List.filterMap_cons, hh]
    exact ih (fun f hf => h f (by simp [hf]))

theorem normalized_query_encoding (route : Route) (query : Value)
    (hs : HasShape (querySchema (FvapiSpec.Wire.reviewedTable route).query) query)
    (hk : HasKnown (querySchema (FvapiSpec.Wire.reviewedTable route).query) query)
    (hv : FvapiSpec.Json.Valid query)
    (hd : ∀ f ∈ (FvapiSpec.Wire.reviewedTable route).query, f.default?.isSome = true →
      (query.get? f.name).isSome = true) :
    parseQuery (encodeQuery query) = .ok (encodedQueryPairs query) ∧
      normalizedQuery (FvapiSpec.Wire.reviewedTable route).query (encodedQueryPairs query) =
        query := by
  cases query with
  | null | bool _ | int _ | str _ | arr _ => exact False.elim hs
  | obj ms =>
    have hkeys := valid_object_keys ms hv
    have hi := query_member_round_trip route ms hs hk hkeys.1
    have hp : ∀ pair ∈ encodedQueryPairs (.obj ms), QueryString pair.1 ∧ QueryString pair.2 := by
      intro pair hm
      change pair ∈ ms.map (fun (name, value) => (name, queryText value)) at hm
      obtain ⟨⟨name, value⟩, hmember, rfl⟩ := List.mem_map.mp hm
      exact ⟨(hi name value hmember).1, (hi name value hmember).2.1⟩
    have hn : ((encodedQueryPairs (.obj ms)).map Prod.fst).Nodup := by
      simpa only [encodedQueryPairs, Value.asObj?, Option.getD_some,
        List.map_map, Function.comp_def] using hkeys.1
    constructor
    · exact query_bytes_parse _ hp hn
    · unfold normalizedQuery
      dsimp only
      have supplied : ((encodedQueryPairs (.obj ms)).map fun (name, text) =>
          (name, queryScalar
            (((((FvapiSpec.Wire.reviewedTable route).query).find?
              (·.name == name)).map (·.kind)).getD .any) text)) = ms := by
        change (ms.map fun (name, value) => (name, queryText value)).map _ = ms
        rw [List.map_map]
        calc
          _ = ms.map id := List.map_congr_left (by
            rintro ⟨name, value⟩ hm
            dsimp only [Function.comp_def, id_eq]
            rw [(hi name value hm).2.2])
          _ = ms := List.map_id' _
      rw [supplied, query_defaults_empty _ ms hd, List.append_nil]
      exact hkeys.2

end FvapiProof.Wire
