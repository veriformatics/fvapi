import FvapiSelf.Json
import Init.Data.Nat.ToString

namespace FvapiProof.Json

open FvapiSpec.Json

private theorem digit_char_bounds {c : Char} (hc : c.isDigit = true) :
    48 ≤ c.toNat ∧ c.toNat ≤ 57 := by
  simpa using Char.isDigit_iff_toNat.mp hc

private theorem digit_byte_nat {c : Char} (hc : c.isDigit = true) :
    c.toNat.toUInt8.toNat = c.toNat := by
  have h := digit_char_bounds hc
  exact UInt8.toNat_ofNat_of_lt' (by change c.toNat < 256; omega)

theorem digit_byte_bounds {c : Char} (hc : c.isDigit = true) :
    0x30 ≤ c.toNat.toUInt8 ∧ c.toNat.toUInt8 ≤ 0x39 := by
  simpa only [UInt8.le_iff_toNat_le, UInt8.reduceToNat, digit_byte_nat hc] using
    digit_char_bounds hc

private theorem digit_byte_value {c : Char} (hc : c.isDigit = true) :
    (c.toNat.toUInt8 - 0x30).toNat = c.toNat - 48 := by
  rw [UInt8.toNat_sub_of_le _ _ (digit_byte_bounds hc).1, digit_byte_nat hc]
  rfl

private theorem digits_first_nonzero : (n : Nat) → 0 < n →
    ∃ c cs, Nat.toDigits 10 n = c :: cs ∧ 49 ≤ c.toNat ∧ c.toNat ≤ 57
  | n, hn => by
    by_cases h : n < 10
    · refine ⟨n.digitChar, [], Nat.toDigits_of_lt_base h, ?_, ?_⟩
      all_goals rw [Nat.toNat_digitChar_of_lt_ten h]; omega
    · have hq : 0 < n / 10 := Nat.div_pos (by omega) (by decide)
      obtain ⟨c, cs, he, hl, hu⟩ := digits_first_nonzero (n / 10) hq
      refine ⟨c, cs ++ [(n % 10).digitChar], ?_, hl, hu⟩
      rw [Nat.toDigits_of_base_le (by decide) (by omega), he]
      rfl
termination_by n => n

private theorem digits_derivation (cs : List Char) (hne : cs ≠ [])
    (hd : ∀ c ∈ cs, c.isDigit = true) (rest : Bytes)
    (hr : ∀ b ∈ rest.head?, isDigit b = false) (acc : Nat) :
    DigitRun acc (cs.map (fun c => c.toNat.toUInt8) ++ rest)
      (Nat.ofDigitChars 10 cs acc) rest := by
  induction cs generalizing acc with
  | nil => contradiction
  | cons c cs ih =>
    have hc := hd c (by simp)
    have hb : isDigit c.toNat.toUInt8 = true := by
      simp only [isDigit, Bool.and_eq_true, decide_eq_true_eq]
      exact digit_byte_bounds hc
    cases cs with
    | nil =>
      simpa only [List.map_cons, List.map_nil, List.cons_append, List.nil_append,
        Nat.ofDigitChars_cons, Nat.ofDigitChars_nil, digit_byte_value hc,
        ↓Char.isValue, Char.reduceToNat] using
        DigitRun.last (acc := acc) hb hr
    | cons d ds =>
      have hi := ih (by simp) (fun c hm => hd c (by simp [hm]))
        (10 * acc + (c.toNat.toUInt8 - 0x30).toNat)
      simpa only [List.map_cons, List.cons_append, Nat.ofDigitChars_cons,
        digit_byte_value hc, ↓Char.isValue, Char.reduceToNat] using DigitRun.more hb hi

theorem intText_literal (n : Int) (hn : n.natAbs ≤ maxInt) (rest : Bytes)
    (hr : ∀ b ∈ rest.head?, isDigit b = false) : IntLit (intText n ++ rest) n rest := by
  cases n with
  | ofNat n =>
    cases n with
    | zero => simpa [intText] using (IntLit.zero (rest := rest))
    | succ n =>
      obtain ⟨c, cs, he, hl, hu⟩ := digits_first_nonzero (n + 1) (by omega)
      have hc : c.isDigit = true :=
        Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) (by rw [he]; simp)
      have hb := digit_byte_nat hc
      have hd := digits_derivation (Nat.toDigits 10 (n + 1)) Nat.toDigits_ne_nil
        (fun c hm => Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) hm) rest hr 0
      rw [Nat.ofDigitChars_ten_toDigits, he] at hd
      have hlow : 0x31 ≤ c.toNat.toUInt8 := by
        simpa only [UInt8.le_iff_toNat_le, UInt8.reduceToNat, hb] using hl
      have hupp : c.toNat.toUInt8 ≤ 0x39 := (digit_byte_bounds hc).2
      have hneg : ¬(Int.ofNat (n + 1) < 0) := by
        rw [Int.ofNat_eq_natCast]
        exact Int.not_lt.mpr (Int.natCast_nonneg _)
      rw [intText]
      simp only [hneg, ↓reduceIte, Int.natAbs_ofNat', he,
        List.map_cons, List.nil_append, List.cons_append]
      simpa only [List.append_eq, Int.ofNat_eq_natCast] using IntLit.pos hlow hupp hd hn
  | negSucc n =>
    obtain ⟨c, cs, he, hl, hu⟩ := digits_first_nonzero (n + 1) (by omega)
    have hc : c.isDigit = true :=
      Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) (by rw [he]; simp)
    have hb := digit_byte_nat hc
    have hd := digits_derivation (Nat.toDigits 10 (n + 1)) Nat.toDigits_ne_nil
      (fun c hm => Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) hm) rest hr 0
    rw [Nat.ofDigitChars_ten_toDigits, he] at hd
    have hlow : 0x31 ≤ c.toNat.toUInt8 := by
      simpa only [UInt8.le_iff_toNat_le, UInt8.reduceToNat, hb] using hl
    have hupp : c.toNat.toUInt8 ≤ 0x39 := (digit_byte_bounds hc).2
    rw [intText]
    simp only [Int.negSucc_lt_zero, ↓reduceIte, Int.natAbs_negSucc, he,
      List.map_cons, List.cons_append, List.nil_append]
    simpa only [List.append_eq, Int.negSucc_eq, Int.natCast_add_one] using
      IntLit.neg hlow hupp hd hn

theorem intText_first_not_ws (n : Int) (rest : Bytes) :
    ∀ b ∈ (intText n ++ rest).head?, isWs b = false := by
  unfold intText
  split
  · simp [isWs]
  · cases he : Nat.toDigits 10 n.natAbs with
    | nil => exact False.elim (Nat.toDigits_ne_nil he)
    | cons c cs =>
      have hc : c.isDigit = true :=
        Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) (by rw [he]; simp)
      have hb := digit_byte_bounds hc
      simp only [List.nil_append, List.map_cons, List.cons_append, List.head?_cons,
        Option.mem_def, Option.some.injEq]
      intro b rfl
      simp only [isWs, Bool.or_eq_false_iff, beq_eq_false_iff_ne]
      simp only [UInt8.le_iff_toNat_le, UInt8.reduceToNat] at hb
      repeat' constructor
      all_goals
        intro heq
        have heq' := congrArg UInt8.toNat heq
        simp only [UInt8.reduceToNat] at heq'
        omega

private def ScalarByte (b : UInt8) : Prop :=
  b ≠ 0x22 ∧ b ≠ 0x5B ∧ b ≠ 0x7B ∧ b ≠ 0x5D ∧ b ≠ 0x7D

private theorem lexical_scalar_bytes (bs rest : Bytes) (level top : Nat)
    (h : ∀ b ∈ bs, ScalarByte b) :
    lexicalDepth.go (bs ++ rest) false false level top =
      lexicalDepth.go rest false false level top := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
    have hb := h b (by simp)
    simp only [ScalarByte] at hb
    simp only [List.cons_append, lexicalDepth.go, beq_eq_false_iff_ne.mpr hb.1,
      beq_eq_false_iff_ne.mpr hb.2.1, beq_eq_false_iff_ne.mpr hb.2.2.1,
      beq_eq_false_iff_ne.mpr hb.2.2.2.1, beq_eq_false_iff_ne.mpr hb.2.2.2.2,
      Bool.false_or, Bool.false_eq_true, ↓reduceIte]
    exact ih (fun b hb => h b (by simp [hb]))

theorem lexical_intText (n : Int) (rest : Bytes) (level top : Nat) :
    lexicalDepth.go (intText n ++ rest) false false level top =
      lexicalDepth.go rest false false level top := by
  apply lexical_scalar_bytes
  intro b hb
  simp only [intText, List.mem_append, List.mem_map] at hb
  rcases hb with hm | ⟨c, hc, rfl⟩
  · split at hm
    · simp_all [ScalarByte]
    · simp at hm
  · have hr := digit_byte_bounds (Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide) hc)
    simp only [UInt8.le_iff_toNat_le, UInt8.reduceToNat] at hr
    unfold ScalarByte
    repeat' constructor
    all_goals
      intro heq
      have heq' := congrArg UInt8.toNat heq
      simp only [UInt8.reduceToNat] at heq'
      omega

end FvapiProof.Json
