import FvapiProof.Wire.Model
import FvapiProof.Json.Decode

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

@[simp] theorem query_syntax (q : ByteArray) :
    QuerySyntax q ↔ FvapiSpec.Wire.QuerySyntax q := Iff.rfl
@[simp] theorem query_pairs (q : ByteArray) : queryPairs q = FvapiSpec.Wire.queryPairs q := rfl
@[simp] theorem query_schema (qs : List QueryField) :
    querySchema qs = FvapiSpec.Wire.querySchema qs := rfl
@[simp] theorem normalized_query (qs : List QueryField) (pairs : List (String × String)) :
    normalizedQuery qs pairs = FvapiSpec.Wire.normalizedQuery qs pairs := rfl
@[simp] theorem lookup_rule (r : Route) (b : Body) :
    lookupRule r b = FvapiSpec.Wire.lookupRule r b := rfl
@[simp] theorem body_known (s : Schema) (b : Body) :
    BodyKnown s b ↔ FvapiSpec.Wire.BodyKnown s b := by
  cases b <;> simp only [BodyKnown, FvapiSpec.Wire.BodyKnown, known_denotation]
@[simp] theorem body_shape (s : Schema) (b : Body) :
    BodyShape s b ↔ FvapiSpec.Wire.BodyShape s b := by
  cases b <;> simp only [BodyShape, FvapiSpec.Wire.BodyShape,
    shape_denotation, refinements_denotation]
@[simp] theorem projected_body (s : Schema) (b : Body) :
    projectBody s b = FvapiSpec.Wire.projectBody s b := by
  cases b <;> simp only [projectBody, FvapiSpec.Wire.projectBody, projection_denotation]

theorem query_complete {q : ByteArray} {result : Except Failure (List (String × String))}
    (h : FvapiSpec.Wire.QueryStage q result) : parseQuery q = result := by
  cases h with
  | malformed h =>
    change ¬ QuerySyntax q at h
    simp only [parseQuery, ite_eq_right h]
  | duplicate hs hd =>
    change QuerySyntax q at hs
    change ¬ (queryPairs q |>.map Prod.fst).Nodup at hd
    rw [parseQuery, ite_eq_left hs]
    dsimp only
    rw [ite_eq_right hd]
  | ok hs hd =>
    change QuerySyntax q at hs
    change (queryPairs q |>.map Prod.fst).Nodup at hd
    rw [parseQuery, ite_eq_left hs]
    dsimp only
    rw [ite_eq_left hd, query_pairs]

theorem query_sound (q : ByteArray) : FvapiSpec.Wire.QueryStage q (parseQuery q) := by
  by_cases hs : QuerySyntax q
  · by_cases hd : (queryPairs q |>.map Prod.fst).Nodup
    · rw [parseQuery, ite_eq_left hs]
      dsimp only
      rw [ite_eq_left hd, query_pairs]
      exact FvapiSpec.Wire.QueryStage.ok hs hd
    · simpa only [parseQuery, ite_eq_left hs, ite_eq_right hd] using
        (FvapiSpec.Wire.QueryStage.duplicate hs hd)
  · simpa only [parseQuery, ite_eq_right hs] using
      (FvapiSpec.Wire.QueryStage.malformed hs)

theorem body_complete {mode : BodyMode} {b : ByteArray} {result : Except Failure Body}
    (h : FvapiSpec.Wire.BodyStage mode b result) : decideBody mode b = result := by
  cases h with
  | noneOk hz => simp only [decideBody, ite_eq_left hz]
  | noneBad hz => simp only [decideBody, ite_eq_right hz]
  | bytesOk hz => simp only [decideBody, ite_eq_left hz]
  | bytesLong hz => simp only [decideBody, ite_eq_right (by omega : ¬ b.size ≤ 65536)]
  | jsonMalformed hj => simp only [decideBody, (FvapiProof.Json.decode_exact _ _).mpr hj]
  | jsonDuplicate hj => simp only [decideBody, (FvapiProof.Json.decode_exact _ _).mpr hj]
  | jsonLong hj => simp only [decideBody, (FvapiProof.Json.decode_exact _ _).mpr hj]
  | jsonRoot hj hn =>
    rw [decideBody, (FvapiProof.Json.decode_exact _ _).mpr hj]
    rename_i v
    cases v <;> first | rfl | exact False.elim (hn _ rfl)
  | jsonOk hj => simp only [decideBody, (FvapiProof.Json.decode_exact _ _).mpr hj]

theorem body_sound (mode : BodyMode) (b : ByteArray) :
    FvapiSpec.Wire.BodyStage mode b (decideBody mode b) := by
  cases mode with
  | none =>
    by_cases hz : b.size = 0
    · simpa only [decideBody, ite_eq_left hz] using (FvapiSpec.Wire.BodyStage.noneOk hz)
    · simpa only [decideBody, ite_eq_right hz] using (FvapiSpec.Wire.BodyStage.noneBad hz)
  | bytes =>
    by_cases hz : b.size ≤ 65536
    · simpa only [decideBody, ite_eq_left hz] using (FvapiSpec.Wire.BodyStage.bytesOk hz)
    · simpa only [decideBody, ite_eq_right hz] using
        (FvapiSpec.Wire.BodyStage.bytesLong (b := b) (by omega))
  | json =>
    simp only [decideBody]
    cases hj : Fvapi.Json.decode b with
    | error e =>
      cases e with
      | malformed =>
        exact FvapiSpec.Wire.BodyStage.jsonMalformed
          ((FvapiProof.Json.decode_exact _ _).mp hj)
      | duplicateKey =>
        exact FvapiSpec.Wire.BodyStage.jsonDuplicate
          ((FvapiProof.Json.decode_exact _ _).mp hj)
      | tooLarge =>
        exact FvapiSpec.Wire.BodyStage.jsonLong
          ((FvapiProof.Json.decode_exact _ _).mp hj)
    | ok v =>
      have hs := (FvapiProof.Json.decode_exact _ _).mp hj
      cases v with
      | obj ms => exact FvapiSpec.Wire.BodyStage.jsonOk hs
      | null | bool _ | int _ | str _ | arr _ =>
        exact FvapiSpec.Wire.BodyStage.jsonRoot hs (by intros ms h; cases h)

/-- Separate the two byte stages from the schema stages, without changing their order. -/
theorem request_after_body (route : Route) (q body : ByteArray)
    (pairs : List (String × String)) (rawBody : Body)
    (hq : parseQuery q = .ok pairs)
    (hb : decideBody (FvapiSpec.Wire.reviewedTable route).requestMode body = .ok rawBody) :
    decideRequest route q body =
      let table := FvapiSpec.Wire.reviewedTable route
      let normalized := FvapiSpec.Wire.normalizedQuery table.query pairs
      if HasKnown (FvapiSpec.Wire.querySchema table.query) normalized ∧
          BodyKnown table.requestSchema rawBody then
        if HasShape (FvapiSpec.Wire.querySchema table.query) normalized ∧
            BodyShape table.requestSchema rawBody then
          match lookupRule route rawBody with
          | some failure => .error failure
          | none => .ok ⟨normalized, projectBody table.requestSchema rawBody⟩
        else .error .malformed
      else .error .unknownKey := by
  rw [decideRequest, hq]
  dsimp only
  rw [tables_exact, hb]
  dsimp only
  rw [query_schema, normalized_query]
  rfl

theorem request_complete {route : Route} {q body : ByteArray} {result : Except Failure Request}
    (h : FvapiSpec.Wire.RequestOutcome route q body result) :
    decideRequest route q body = result := by
  cases h with
  | queryError hq => simp only [decideRequest, query_complete hq]
  | bodyError hq hb =>
    rw [decideRequest, query_complete hq]
    dsimp only
    rw [tables_exact, body_complete hb]
  | @unknown pairs b hq hb hk =>
    rw [request_after_body route q body pairs b (query_complete hq) (body_complete hb)]
    dsimp only
    have hk' : ¬ (HasKnown (FvapiSpec.Wire.querySchema (FvapiSpec.Wire.reviewedTable route).query)
        (FvapiSpec.Wire.normalizedQuery (FvapiSpec.Wire.reviewedTable route).query pairs) ∧
        BodyKnown (FvapiSpec.Wire.reviewedTable route).requestSchema b) := by
      intro h
      exact hk ⟨(known_denotation _ _).mp h.1, (body_known _ _).mp h.2⟩
    rw [ite_eq_right hk']
  | @malformed pairs b hq hb hk hbk hs =>
    rw [request_after_body route q body pairs b (query_complete hq) (body_complete hb)]
    dsimp only
    have hk' := And.intro ((known_denotation _ _).mpr hk) ((body_known _ _).mpr hbk)
    have hs' : ¬ (HasShape (FvapiSpec.Wire.querySchema (FvapiSpec.Wire.reviewedTable route).query)
        (FvapiSpec.Wire.normalizedQuery (FvapiSpec.Wire.reviewedTable route).query pairs) ∧
        BodyShape (FvapiSpec.Wire.reviewedTable route).requestSchema b) := by
      intro h
      exact hs ⟨(shape_denotation _ _).mp h.1, (body_shape _ _).mp h.2⟩
    rw [ite_eq_left hk', ite_eq_right hs']
  | @rule pairs b f hq hb hk hbk hs hbs hr =>
    rw [request_after_body route q body pairs b (query_complete hq) (body_complete hb)]
    dsimp only
    have hk' := And.intro ((known_denotation _ _).mpr hk) ((body_known _ _).mpr hbk)
    have hs' := And.intro ((shape_denotation _ _).mpr hs) ((body_shape _ _).mpr hbs)
    rw [ite_eq_left hk', ite_eq_left hs', lookup_rule, hr]
  | @ok pairs b hq hb hk hbk hs hbs hr =>
    rw [request_after_body route q body pairs b (query_complete hq) (body_complete hb)]
    dsimp only
    have hk' := And.intro ((known_denotation _ _).mpr hk) ((body_known _ _).mpr hbk)
    have hs' := And.intro ((shape_denotation _ _).mpr hs) ((body_shape _ _).mpr hbs)
    rw [ite_eq_left hk', ite_eq_left hs', lookup_rule, hr, projected_body]

theorem request_sound (route : Route) (q body : ByteArray) :
    FvapiSpec.Wire.RequestOutcome route q body (decideRequest route q body) := by
  cases hq : parseQuery q with
  | error failure =>
    rw [decideRequest, hq]
    exact FvapiSpec.Wire.RequestOutcome.queryError (hq ▸ query_sound q)
  | ok pairs =>
    have hqs := hq ▸ query_sound q
    cases hb : decideBody (FvapiSpec.Wire.reviewedTable route).requestMode body with
    | error failure =>
      rw [decideRequest, hq]
      dsimp only
      rw [tables_exact, hb]
      exact FvapiSpec.Wire.RequestOutcome.bodyError hqs (hb ▸ body_sound _ body)
    | ok rawBody =>
      have hbs := hb ▸ body_sound (FvapiSpec.Wire.reviewedTable route).requestMode body
      rw [request_after_body route q body pairs rawBody hq hb]
      dsimp only
      split
      · rename_i hk
        split
        · rename_i hs
          cases hr : lookupRule route rawBody with
          | none =>
            dsimp only
            rw [projected_body]
            apply FvapiSpec.Wire.RequestOutcome.ok hqs hbs
              ((known_denotation _ _).mp hk.1) ((body_known _ _).mp hk.2)
              ((shape_denotation _ _).mp hs.1) ((body_shape _ _).mp hs.2)
            exact hr
          | some failure =>
            apply FvapiSpec.Wire.RequestOutcome.rule hqs hbs
              ((known_denotation _ _).mp hk.1) ((body_known _ _).mp hk.2)
              ((shape_denotation _ _).mp hs.1) ((body_shape _ _).mp hs.2)
            exact hr
        · rename_i hs
          apply FvapiSpec.Wire.RequestOutcome.malformed hqs hbs
            ((known_denotation _ _).mp hk.1) ((body_known _ _).mp hk.2)
          intro h
          exact hs ⟨(shape_denotation _ _).mpr h.1, (body_shape _ _).mpr h.2⟩
      · rename_i hk
        apply FvapiSpec.Wire.RequestOutcome.unknown hqs hbs
        intro h
        exact hk ⟨(known_denotation _ _).mpr h.1, (body_known _ _).mpr h.2⟩

theorem request_exact : FvapiSelf.Wire.RequestExact := by
  intro route q body result
  constructor
  · intro h
    rw [← h]
    exact request_sound route q body
  · exact request_complete

#print axioms request_exact

end FvapiProof.Wire
