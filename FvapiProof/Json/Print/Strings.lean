import FvapiSelf.Json

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

private theorem hexVal_hexDigit_fin : ∀ n : Fin 16,
    hexVal (hexDigit n.val) = some n.val := by decide

private theorem hexVal_hexDigit (n : Nat) (h : n < 16) :
    hexVal (hexDigit n) = some n := hexVal_hexDigit_fin ⟨n, h⟩

theorem escapeChar_body (c : Char) {cs rest : Bytes} {chs : List Char}
    (hb : StrBody cs chs rest) : StrBody (escapeChar c ++ cs) (c :: chs) rest := by
  unfold escapeChar
  split
  · rename_i hc; subst c; exact StrBody.esc Escape.quote hb
  split
  · rename_i hc; subst c; exact StrBody.esc Escape.backslash hb
  split
  · rename_i hc
    have he : c = Char.ofNat 0x08 := Char.ext hc
    subst c
    exact StrBody.esc Escape.backspace hb
  split
  · rename_i hc
    have he : c = Char.ofNat 0x0C := Char.ext hc
    subst c
    exact StrBody.esc Escape.formfeed hb
  split
  · rename_i hc; subst c; exact StrBody.esc Escape.newline hb
  split
  · rename_i hc; subst c; exact StrBody.esc Escape.ret hb
  split
  · rename_i hc; subst c; exact StrBody.esc Escape.tab hb
  split
  · rename_i hc
    have hn : c.toNat < 256 := by
      simp only [UInt32.lt_iff_toNat_lt, ← UInt32.toNat_inj, UInt32.reduceToNat,
        Char.toNat_val] at hc
      omega
    have hh : c.toNat / 16 < 16 := by omega
    have hl : c.toNat % 16 < 16 := Nat.mod_lt _ (by decide)
    have hm : c.toNat / 16 * 16 + c.toNat % 16 = c.toNat := by omega
    have hx := Hex4.mk (rest := cs) (by rfl : hexVal 0x30 = some 0)
      (by rfl : hexVal 0x30 = some 0) (hexVal_hexDigit _ hh) (hexVal_hexDigit _ hl)
    simp only [Nat.zero_mul, Nat.zero_add, hm] at hx
    have he := Escape.unit hx (Or.inl (show c.toNat < 0xD800 by omega))
    simpa only [Char.ofNat_toNat, List.cons_append, List.nil_append] using StrBody.esc he hb
  · rename_i hq hbsl h08 h0C hnl hret htab hc
    apply StrBody.raw ?_ hq hbsl hb
    simp only [not_or, UInt32.not_lt] at hc
    exact hc.1

theorem strText_body (cs : List Char) (rest : Bytes) :
    StrBody (cs.flatMap escapeChar ++ 0x22 :: rest) cs rest := by
  induction cs with
  | nil => exact StrBody.close
  | cons c cs ih =>
    simpa only [List.flatMap_cons, List.append_assoc] using escapeChar_body c ih

theorem strText_literal (s : String) (rest : Bytes) : StrLit (strText s ++ rest) s rest := by
  have h := StrLit.mk (strText_body s.toList rest)
  simpa [strText, List.append_assoc] using h

private def NotStringToken (b : UInt8) : Prop := b ≠ 0x22 ∧ b ≠ 0x5C

set_option maxRecDepth 4096 in
private theorem multibyte_tokens_fin : ∀ i : Fin 256,
    let b := UInt8.ofNat i.val
    NotStringToken (b &&& 0x1F ||| 0xC0) ∧ NotStringToken (b &&& 0x3F ||| 0x80) ∧
      NotStringToken (b &&& 0x0F ||| 0xE0) ∧ NotStringToken (b &&& 0x07 ||| 0xF0) := by
  unfold NotStringToken
  decide

private theorem multibyte_tokens (b : UInt8) :
    NotStringToken (b &&& 0x1F ||| 0xC0) ∧ NotStringToken (b &&& 0x3F ||| 0x80) ∧
      NotStringToken (b &&& 0x0F ||| 0xE0) ∧ NotStringToken (b &&& 0x07 ||| 0xF0) := by
  simpa using multibyte_tokens_fin ⟨b.toNat, b.toNat_lt⟩

private theorem ascii_toUInt8_inj (x : UInt32) (h : x ≤ 127) (d : UInt8)
    (heq : x.toUInt8 = d) : x.toNat = d.toNat := by
  have hn := congrArg UInt8.toNat heq
  simp only [UInt32.toNat_toUInt8] at hn
  simp only [UInt32.le_iff_toNat_le, UInt32.reduceToNat] at h
  omega

private theorem raw_utf8_no_quotes (c : Char) (hq : c ≠ '"') (hb : c ≠ '\\') :
    ∀ b ∈ String.utf8EncodeChar c, b ≠ 0x22 ∧ b ≠ 0x5C := by
  have hqv : c.val ≠ 0x22 := fun h => hq (Char.ext h)
  have hbv : c.val ≠ 0x5C := fun h => hb (Char.ext h)
  intro b hm
  rw [String.utf8EncodeChar_eq_utf8EncodeCharFast] at hm
  simp only [String.utf8EncodeCharFast] at hm
  split at hm
  · rename_i hbound
    simp only [List.mem_singleton] at hm
    subst b
    constructor
    · intro heq
      apply hqv
      apply UInt32.toNat_inj.mp
      simpa only [UInt32.reduceToNat, UInt8.reduceToNat] using
        ascii_toUInt8_inj c.val hbound _ heq
    · intro heq
      apply hbv
      apply UInt32.toNat_inj.mp
      simpa only [UInt32.reduceToNat, UInt8.reduceToNat] using
        ascii_toUInt8_inj c.val hbound _ heq
  · split at hm
    · simp only [List.mem_cons, List.mem_nil_iff, or_false] at hm
      rcases hm with rfl | rfl
      · exact (multibyte_tokens _).1
      · exact (multibyte_tokens _).2.1
    · split at hm
      · simp only [List.mem_cons, List.mem_nil_iff, or_false] at hm
        rcases hm with rfl | rfl | rfl
        · exact (multibyte_tokens _).2.2.1
        · exact (multibyte_tokens _).2.1
        · exact (multibyte_tokens _).2.1
      · simp only [List.mem_cons, List.mem_nil_iff, or_false] at hm
        rcases hm with rfl | rfl | rfl | rfl
        · exact (multibyte_tokens _).2.2.2
        · exact (multibyte_tokens _).2.1
        · exact (multibyte_tokens _).2.1
        · exact (multibyte_tokens _).2.1

theorem lexical_string_bytes (bs rest : Bytes) (level top : Nat)
    (h : ∀ b ∈ bs, b ≠ 0x22 ∧ b ≠ 0x5C) :
    lexicalDepth.go (bs ++ rest) true false level top =
      lexicalDepth.go rest true false level top := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
    have hb := h b (by simp)
    simp only [List.cons_append, lexicalDepth.go, bne_iff_ne.mpr hb.1,
      beq_eq_false_iff_ne.mpr hb.2]
    exact ih (fun b hb => h b (by simp [hb]))

private theorem hex_no_quotes : ∀ n : Fin 16,
    hexDigit n.val ≠ 0x22 ∧ hexDigit n.val ≠ 0x5C := by decide

theorem lexical_escapeChar (c : Char) (rest : Bytes) (level top : Nat) :
    lexicalDepth.go (escapeChar c ++ rest) true false level top =
      lexicalDepth.go rest true false level top := by
  unfold escapeChar
  repeat' split
  all_goals first
    | rfl
    | (apply lexical_string_bytes; exact raw_utf8_no_quotes c (by assumption) (by assumption))
    | (rename_i hc
       have hn : c.toNat < 256 := by
         simp only [UInt32.lt_iff_toNat_lt, ← UInt32.toNat_inj, UInt32.reduceToNat,
           Char.toNat_val] at hc
         omega
       have hh := hex_no_quotes ⟨c.toNat / 16, by omega⟩
       have hl := hex_no_quotes ⟨c.toNat % 16, Nat.mod_lt _ (by decide)⟩
       change lexicalDepth.go
         ([hexDigit (c.toNat / 16), hexDigit (c.toNat % 16)] ++ rest) true false level top = _
       apply lexical_string_bytes
       intro b hb
       simp only [List.mem_cons, List.mem_nil_iff, or_false] at hb
       rcases hb with rfl | rfl
       · exact hh
       · exact hl)

theorem lexical_string_body (cs : List Char) (rest : Bytes) (level top : Nat) :
    lexicalDepth.go (cs.flatMap escapeChar ++ rest) true false level top =
      lexicalDepth.go rest true false level top := by
  induction cs with
  | nil => rfl
  | cons c cs ih =>
    rw [List.flatMap_cons, List.append_assoc, lexical_escapeChar]
    exact ih

theorem lexical_strText (s : String) (rest : Bytes) (level top : Nat) :
    lexicalDepth.go (strText s ++ rest) false false level top =
      lexicalDepth.go rest false false level top := by
  simp only [strText, List.cons_append, List.append_assoc]
  rw [lexicalDepth.go]
  rw [lexical_string_body]
  rfl

end FvapiProof.Json
