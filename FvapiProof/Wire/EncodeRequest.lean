import FvapiProof.Wire.QueryNormalize
import FvapiProof.Wire.EncodeResponse

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

theorem admissible_body_encoding (mode : BodyMode) (schema : Schema) (b : Body)
    (h : match mode, b with
      | .none, .none => True
      | .bytes, .bytes bytes => bytes.size ≤ 65536
      | .json, .json v => FvapiSpec.Wire.Denotes schema v v ∧
          FvapiSpec.Wire.Known schema v ∧ FvapiSpec.Json.Valid v
      | _, _ => False)
    (hk : mode = .json → FvapiSpec.Wire.isRecord schema = true) :
    decideBody mode (encodeBody b) = .ok b ∧ BodyKnown schema b ∧ BodyShape schema b ∧
      projectBody schema b = b := by
  cases mode <;> cases b
  all_goals try exact False.elim h
  · exact ⟨rfl, True.intro, True.intro, rfl⟩
  · obtain ⟨hd, hn, hv⟩ := h
    have hs := (shape_denotation schema _).mpr hd.1
    have hr := (refinements_denotation schema _).mpr hd.2.1
    obtain ⟨members, rfl⟩ := object_of_record_shape schema _ (hk rfl) hs
    refine ⟨?_, (known_denotation _ _).mpr hn, ⟨hs, hr⟩, ?_⟩
    · rw [encodeBody, decideBody, FvapiProof.Json.print_decode _ hv]
    · unfold projectBody
      dsimp only
      rw [projection_denotation, hd.2.2.symm]
  · exact ⟨by rw [encodeBody, decideBody, ite_eq_left h], True.intro, True.intro, rfl⟩

theorem request_encode : FvapiSelf.Wire.RequestEncode := by
  intro route req h
  obtain ⟨query, body⟩ := req
  obtain ⟨hs, hk, _, hd, hv, hrule, hb⟩ := h
  have hs' : HasShape (querySchema (FvapiSpec.Wire.reviewedTable route).query) query := by
    rw [query_schema]
    exact (shape_denotation _ _).mpr hs
  have hk' : HasKnown (querySchema (FvapiSpec.Wire.reviewedTable route).query) query := by
    rw [query_schema]
    exact (known_denotation _ _).mpr hk
  have hquery := normalized_query_encoding route query hs' hk' hv hd
  have hbody := admissible_body_encoding (FvapiSpec.Wire.reviewedTable route).requestMode
    (FvapiSpec.Wire.reviewedTable route).requestSchema body hb (json_request_record route)
  have hnormalized : FvapiSpec.Wire.normalizedQuery (FvapiSpec.Wire.reviewedTable route).query
      (encodedQueryPairs query) = query :=
    (normalized_query _ _).symm.trans hquery.2
  dsimp only [encodeRequest]
  constructor
  · rw [request_after_body route _ _ (encodedQueryPairs query) body hquery.1 hbody.1]
    dsimp only
    rw [hnormalized]
    rw [query_schema] at hs' hk'
    rw [ite_eq_left (And.intro hk' hbody.2.1),
      ite_eq_left (And.intro hs' hbody.2.2.1), lookup_rule, hrule, hbody.2.2.2]
  · cases body with
    | none => rfl
    | bytes _ => rfl
    | json _ => exact FvapiProof.Json.print_exact _

#print axioms request_encode

end FvapiProof.Wire
