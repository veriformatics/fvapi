import FvapiProof.Wire.QueryBytes
import FvapiProof.Wire.Tables

namespace FvapiProof.Wire

open Fvapi.Wire Fvapi.Json

def QueryChar (c : Char) : Prop :=
  ('A' ≤ c ∧ c ≤ 'Z') ∨ ('a' ≤ c ∧ c ≤ 'z') ∨ ('0' ≤ c ∧ c ≤ '9') ∨
    c = '.' ∨ c = '_' ∨ c = '~' ∨ c = '-'

theorem query_char_codes (c : Char) (h : QueryChar c) :
    (65 ≤ c.toNat ∧ c.toNat ≤ 90) ∨ (97 ≤ c.toNat ∧ c.toNat ≤ 122) ∨
      (48 ≤ c.toNat ∧ c.toNat ≤ 57) ∨ c.toNat = 46 ∨ c.toNat = 95 ∨
      c.toNat = 126 ∨ c.toNat = 45 := by
  rcases h with h | h | h | rfl | rfl | rfl | rfl
  · left
    change 65 ≤ c.toNat ∧ c.toNat ≤ 90 at h
    exact h
  · right; left
    change 97 ≤ c.toNat ∧ c.toNat ≤ 122 at h
    exact h
  · right; right; left
    change 48 ≤ c.toNat ∧ c.toNat ≤ 57 at h
    exact h
  all_goals decide

theorem query_char_bytes (c : Char) (h : QueryChar c) :
    (String.utf8EncodeChar c).all queryByte = true := by
  have hc := query_char_codes c h
  have ha : c.val ≤ 0x7f := by change c.toNat ≤ 127; omega
  have hb : c.val.toUInt8.toNat = c.toNat := by
    rw [UInt32.toNat_toUInt8]
    change c.toNat % 256 = c.toNat
    exact Nat.mod_eq_of_lt (by omega)
  have dot : c.toNat = 46 → c.val.toUInt8 = 0x2e := fun e => UInt8.toNat.inj (hb.trans e)
  have under : c.toNat = 95 → c.val.toUInt8 = 0x5f := fun e => UInt8.toNat.inj (hb.trans e)
  have tilde : c.toNat = 126 → c.val.toUInt8 = 0x7e := fun e => UInt8.toNat.inj (hb.trans e)
  have dash : c.toNat = 45 → c.val.toUInt8 = 0x2d := fun e => UInt8.toNat.inj (hb.trans e)
  rw [String.utf8EncodeChar_eq_utf8EncodeCharFast]
  unfold String.utf8EncodeCharFast
  dsimp only
  rw [ite_eq_left ha]
  simp only [List.all_cons, List.all_nil, Bool.and_true, queryByte, Bool.or_eq_true,
    Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq, UInt8.le_iff_toNat_le,
    UInt8.reduceToNat, hb]
  rcases hc with hu | hl | hd | he | he | he | he
  · exact Or.inl (Or.inl (Or.inl (Or.inl (Or.inl (Or.inl hu)))))
  · exact Or.inl (Or.inl (Or.inl (Or.inl (Or.inl (Or.inr hl)))))
  · exact Or.inl (Or.inl (Or.inl (Or.inl (Or.inr hd))))
  · exact Or.inl (Or.inl (Or.inl (Or.inr (dot he))))
  · exact Or.inl (Or.inl (Or.inr (under he)))
  · exact Or.inl (Or.inr (tilde he))
  · exact Or.inr (dash he)

theorem query_list_bytes (chars : List Char) (h : ∀ c ∈ chars, QueryChar c) :
    chars.utf8Encode.data.toList.all queryByte = true := by
  induction chars with
  | nil => rfl
  | cons c rest ih =>
    rw [List.utf8Encode_cons, List.utf8Encode_singleton, ByteArray.toList_data_append]
    simp only [List.all_append, Bool.and_eq_true]
    constructor
    · simpa using query_char_bytes c (h c (by simp))
    · exact ih (fun d hd => h d (by simp [hd]))

theorem string_bytes_nonempty (s : String) (hne : s ≠ "") : s.toUTF8.data.toList ≠ [] := by
  intro he
  have ha : s.toUTF8.data = #[] := Array.toList_inj.mp he
  have hb : s.toUTF8 = ByteArray.empty := congrArg ByteArray.mk ha
  exact hne (String.toByteArray_inj.mp hb)

theorem query_string_chars (s : String) (hne : s ≠ "")
    (h : ∀ c ∈ s.toList, QueryChar c) : QueryString s := by
  refine ⟨string_bytes_nonempty s hne, ?_⟩
  rw [String.toUTF8_eq_toByteArray, ← String.utf8Encode_toList]
  exact query_list_bytes s.toList h

theorem nat_query_string (n : Nat) : QueryString (toString n) := by
  rw [Nat.toString_eq_repr]
  apply query_string_chars _ Nat.repr_ne_empty
  intro c hc
  rw [Nat.toList_repr] at hc
  have hd := Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) hc
  have hnum := Char.isDigit_iff_toNat.mp hd
  right; right; left
  change 48 ≤ c.toNat ∧ c.toNat ≤ 57 at hnum
  change 48 ≤ c.toNat ∧ c.toNat ≤ 57
  exact hnum

theorem nonnegative_query_scalar (kind : Scalar) (n : Int) (hn : 0 ≤ n)
    (hk : numeric kind = true) :
    QueryString (queryText (.int n)) ∧ queryScalar kind (queryText (.int n)) = .int n := by
  cases n with
  | negSucc n => omega
  | ofNat n =>
    have ht : toString (Int.ofNat n) = toString n := rfl
    constructor
    · simpa only [queryText, ht] using nat_query_string n
    · simp only [queryText, ht, queryScalar, hk, ite_true, Nat.toString_eq_repr,
        Nat.toNat?_repr]
      rfl

theorem query_scalar_round_trip (kind : Scalar) (v : Value)
    (hk : FvapiSpec.Wire.queryKindEncodable kind = true) (hs : ScalarAccepts kind v) :
    QueryString (queryText v) ∧ queryScalar kind (queryText v) = v := by
  cases kind with
  | nat =>
    cases v <;> simp only [ScalarAccepts] at hs
    exact nonnegative_query_scalar _ _ hs.1 rfl
  | pos =>
    cases v <;> simp only [ScalarAccepts] at hs
    exact nonnegative_query_scalar _ _ (by omega) rfl
  | boundedNat lo hi =>
    cases v <;> simp only [ScalarAccepts] at hs
    exact nonnegative_query_scalar _ _ (by omega) rfl
  | oneOf values =>
    cases v <;> simp only [ScalarAccepts] at hs
    rename_i text
    have hall := List.all_eq_true.mp hk text hs
    simp only [Bool.and_eq_true] at hall
    have hn : text ≠ "" := by intro he; subst text; cases hall.1
    exact ⟨⟨string_bytes_nonempty text hn, hall.2⟩, rfl⟩
  | ident =>
    cases v <;> simp only [ScalarAccepts] at hs
    rename_i text
    have hn : text ≠ "" := by
      intro he
      subst text
      have hsize := hs.1.1
      change 1 ≤ 0 at hsize
      omega
    refine ⟨query_string_chars text hn ?_, rfl⟩
    intro c hc
    have h := List.all_eq_true.mp hs.2.1 c hc
    change (('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') || c == '.' ||
      c == '_' || c == '-') = true at h
    simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
    rcases h with (((hl | hd) | he) | he) | he
    · exact Or.inr (Or.inl hl)
    · exact Or.inr (Or.inr (Or.inl hd))
    all_goals subst c; unfold QueryChar; decide
  | token =>
    cases v <;> simp only [ScalarAccepts] at hs
    rename_i text
    have hn : text ≠ "" := by
      intro he
      subst text
      have hsize := hs.1.1
      change 1 ≤ 0 at hsize
      omega
    refine ⟨query_string_chars text hn ?_, rfl⟩
    intro c hc
    have h := List.all_eq_true.mp hs.2 c hc
    change (('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') ||
      ('A' ≤ c && c ≤ 'Z') || c == '.' || c == '_' || c == '~' || c == '-') = true at h
    simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
    rcases h with (((((hl | hd) | hu) | he) | he) | he) | he
    · exact Or.inr (Or.inl hl)
    · exact Or.inr (Or.inr (Or.inl hd))
    · exact Or.inl hu
    all_goals subst c; unfold QueryChar; decide
  | cursor =>
    cases v <;> simp only [ScalarAccepts] at hs
    rename_i text
    have hn : text ≠ "" := by
      intro he
      subst text
      have hsize := hs.1.1
      change 1 ≤ 0 at hsize
      omega
    refine ⟨query_string_chars text hn ?_, rfl⟩
    intro c hc
    have h := List.all_eq_true.mp hs.2 c hc
    change (('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') ||
      ('A' ≤ c && c ≤ 'Z') || c == '_' || c == '-') = true at h
    simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
    rcases h with (((hl | hd) | hu) | he) | he
    · exact Or.inr (Or.inl hl)
    · exact Or.inr (Or.inr (Or.inl hd))
    · exact Or.inl hu
    all_goals subst c; unfold QueryChar; decide
  | bool | sha256 | profileId | digest | label | spdx | text _ _ | source | leanName | absPath
  | any => cases hk

end FvapiProof.Wire
