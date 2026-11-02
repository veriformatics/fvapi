import FvapiProof.Wire.Request
import Std.Data.String.ToNat

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

def QueryString (s : String) : Prop :=
  s.toUTF8.data.toList ≠ [] ∧ s.toUTF8.data.toList.all queryByte = true

theorem query_byte_delimiters (b : UInt8) (h : queryByte b = true) :
    b ≠ 0x26 ∧ b ≠ 0x3d := by
  constructor
  · intro e
    subst b
    cases h
  · intro e
    subst b
    cases h

theorem split_cons (separator b : UInt8) (rest : Bytes) :
    splitBytes separator (b :: rest) =
      if b = separator then [] :: splitBytes separator rest else
        match splitBytes separator rest with
        | [] => [[b]]
        | part :: parts => (b :: part) :: parts := rfl

theorem split_without (separator : UInt8) (bytes : Bytes)
    (h : ∀ b ∈ bytes, b ≠ separator) : splitBytes separator bytes = [bytes] := by
  induction bytes with
  | nil => rfl
  | cons b rest ih =>
    have hi := ih (fun c hc => h c (by simp only [List.mem_cons]; exact Or.inr hc))
    rw [split_cons, ite_eq_right (h b (by simp)), hi]

theorem split_prefix (separator : UInt8) (front suffix : Bytes)
    (h : ∀ b ∈ front, b ≠ separator) :
    splitBytes separator (front ++ separator :: suffix) =
      front :: splitBytes separator suffix := by
  induction front with
  | nil => rw [List.nil_append, split_cons, ite_eq_left rfl]
  | cons b rest ih =>
    have hi := ih (fun c hc => h c (by simp only [List.mem_cons]; exact Or.inr hc))
    rw [List.cons_append, split_cons, ite_eq_right (h b (by simp)), hi]

theorem utf8_round_trip (s : String) : String.fromUTF8! s.toUTF8 = s := by
  unfold String.fromUTF8! String.toUTF8
  rw [dite_eq_left s.isValidUTF8]
  rfl

theorem pair_split (pair : String × String) (hn : QueryString pair.1)
    (hv : QueryString pair.2) :
    splitBytes 0x3d (pairBytes pair) =
      [pair.1.toUTF8.data.toList, pair.2.toUTF8.data.toList] := by
  rw [pairBytes, split_prefix]
  · rw [split_without]
    exact fun b hb => (query_byte_delimiters b (List.all_eq_true.mp hv.2 b hb)).2
  · exact fun b hb => (query_byte_delimiters b (List.all_eq_true.mp hn.2 b hb)).2

theorem pair_no_ampersand (pair : String × String) (hn : QueryString pair.1)
    (hv : QueryString pair.2) : ∀ b ∈ pairBytes pair, b ≠ 0x26 := by
  intro b hb
  simp only [pairBytes, List.mem_append, List.mem_cons] at hb
  rcases hb with hb | rfl | hb
  · exact (query_byte_delimiters b (List.all_eq_true.mp hn.2 b hb)).1
  · decide
  · exact (query_byte_delimiters b (List.all_eq_true.mp hv.2 b hb)).1

theorem query_bytes_split (pairs : List (String × String)) (hne : pairs ≠ [])
    (h : ∀ pair ∈ pairs, QueryString pair.1 ∧ QueryString pair.2) :
    splitBytes 0x26 (queryBytes pairs) = pairs.map pairBytes := by
  induction pairs with
  | nil => contradiction
  | cons pair rest ih =>
    have hp := h pair (by simp)
    cases rest with
    | nil =>
      exact split_without _ _ (pair_no_ampersand pair hp.1 hp.2)
    | cons next rest =>
      rw [queryBytes, split_prefix _ _ _ (pair_no_ampersand pair hp.1 hp.2)]
      rw [ih (by simp) (fun p hp => h p (by simp [hp]))]
      rfl
      all_goals exact List.cons_ne_nil _ _

theorem pair_valid (pair : String × String) (hn : QueryString pair.1)
    (hv : QueryString pair.2) : QueryItem (pairBytes pair) := by
  unfold QueryItem
  rw [pair_split pair hn hv]
  exact ⟨hn.1, hv.1, hn.2, hv.2⟩

theorem pair_bytes_nonempty (pair : String × String) : pairBytes pair ≠ [] := by
  intro he
  have hl := congrArg List.length he
  simp only [pairBytes, List.length_append, List.length_cons, List.length_nil] at hl
  omega

theorem query_bytes_nonempty (pairs : List (String × String)) (hne : pairs ≠ []) :
    queryBytes pairs ≠ [] := by
  cases pairs with
  | nil => contradiction
  | cons pair rest =>
    cases rest with
    | nil => exact pair_bytes_nonempty pair
    | cons _ _ =>
      intro he
      have hl := congrArg List.length he
      simp only [queryBytes, List.length_append, List.length_cons, List.length_nil] at hl
      omega

theorem unpack_pair (pair : String × String) (hn : QueryString pair.1)
    (hv : QueryString pair.2) :
    let parts := splitBytes 0x3d (pairBytes pair)
    (String.fromUTF8! ⟨(parts[0]?.getD []).toArray⟩,
      String.fromUTF8! ⟨(parts[1]?.getD []).toArray⟩) = pair := by
  rw [pair_split pair hn hv]
  dsimp only
  have h1 : (⟨pair.1.toUTF8.data.toList.toArray⟩ : ByteArray) = pair.1.toUTF8 := by simp
  have h2 : (⟨pair.2.toUTF8.data.toList.toArray⟩ : ByteArray) = pair.2.toUTF8 := by simp
  change (String.fromUTF8! ⟨pair.1.toUTF8.data.toList.toArray⟩,
    String.fromUTF8! ⟨pair.2.toUTF8.data.toList.toArray⟩) = pair
  rw [h1, h2, utf8_round_trip, utf8_round_trip]

theorem query_bytes_parse (pairs : List (String × String))
    (h : ∀ pair ∈ pairs, QueryString pair.1 ∧ QueryString pair.2)
    (hn : (pairs.map Prod.fst).Nodup) :
    parseQuery ⟨(queryBytes pairs).toArray⟩ = .ok pairs := by
  let raw : ByteArray := ⟨(queryBytes pairs).toArray⟩
  have hdata : raw.data.toList = queryBytes pairs := by simp [raw]
  have hp : queryPairs raw = pairs := by
    cases pairs with
    | nil => rfl
    | cons pair rest =>
      have hne : pair :: rest ≠ [] := by simp
      have hz : raw.size ≠ 0 := by
        intro hz
        apply query_bytes_nonempty (pair :: rest) hne
        simp only [raw, ByteArray.size, List.size_toArray] at hz
        exact List.eq_nil_of_length_eq_zero hz
      rw [queryPairs, ite_eq_right hz, hdata, query_bytes_split _ hne h]
      simp only [List.map_map]
      have he : ∀ p ∈ pair :: rest,
          (let parts := splitBytes 0x3d (pairBytes p)
           (String.fromUTF8! ⟨(parts[0]?.getD []).toArray⟩,
             String.fromUTF8! ⟨(parts[1]?.getD []).toArray⟩)) = p :=
        fun p hp => unpack_pair p (h p hp).1 (h p hp).2
      calc
        _ = (pair :: rest).map id := List.map_congr_left he
        _ = pair :: rest := List.map_id' _
  have hs : QuerySyntax raw := by
    cases pairs with
    | nil => exact Or.inl rfl
    | cons pair rest =>
      right
      rw [hdata, query_bytes_split _ (by simp) h]
      intro item hm
      obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hm
      exact pair_valid p (h p hp).1 (h p hp).2
  change parseQuery raw = .ok pairs
  rw [parseQuery, ite_eq_left hs]
  dsimp only
  rw [hp, ite_eq_left hn]

end FvapiProof.Wire
