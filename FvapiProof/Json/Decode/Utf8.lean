import FvapiProof.Json.Decode.Index

namespace FvapiProof.Json

open Fvapi.Json

private theorem or_byte_safe (x k : UInt8) (h : 0x80 ≤ k) :
    x ||| k ≠ 0x22 ∧ x ||| k ≠ 0x5C := by
  have hl : k.toNat ≤ (x ||| k).toNat := by
    rw [UInt8.toNat_or]
    exact Nat.right_le_or
  change 128 ≤ k.toNat at h
  constructor <;> intro he <;> rw [he] at hl
  all_goals simp only [UInt8.reduceToNat] at hl; omega

/-- Encoded string content cannot change the scanner's quote/escape state. -/
theorem utf8EncodeChar_safe {c : Char} (hq : c ≠ '"') (hb : c ≠ '\\') :
    ∀ b ∈ String.utf8EncodeChar c, b ≠ 0x22 ∧ b ≠ 0x5C := by
  have hqv : c.val ≠ 0x22 := fun h => hq (Char.ext h)
  have hbv : c.val ≠ 0x5C := fun h => hb (Char.ext h)
  have hqn : c.val.toNat ≠ 0x22 := fun h => hqv (UInt32.toNat.inj h)
  have hbn : c.val.toNat ≠ 0x5C := fun h => hbv (UInt32.toNat.inj h)
  rw [String.utf8EncodeChar_eq_utf8EncodeCharFast]
  unfold String.utf8EncodeCharFast
  dsimp only
  intro b hm
  split at hm
  · rename_i hascii
    change c.val.toNat ≤ 127 at hascii
    simp only [List.mem_singleton] at hm
    subst b
    constructor <;> intro he
    all_goals
      have hn := congrArg UInt8.toNat he
      simp only [UInt32.toNat_toUInt8, UInt8.reduceToNat] at hn
      omega
  · split at hm
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
      rcases hm with rfl | rfl <;> exact or_byte_safe _ _ (by decide)
    · split at hm
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl <;> exact or_byte_safe _ _ (by decide)
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl | rfl <;> exact or_byte_safe _ _ (by decide)

theorem bytesAt_extract (b : ByteArray) (i : Nat) :
    (b.extract i b.size).data.toList = bytesAt b i := by
  simp only [ByteArray.data_extract, Array.toList_extract, List.extract, bytesAt]
  apply List.take_of_length_le
  simp

theorem or_byte_ge (x k : UInt8) : k ≤ x ||| k := by
  change k.toNat ≤ (x ||| k).toNat
  rw [UInt8.toNat_or]
  exact Nat.right_le_or

theorem utf8EncodeChar_byte_cases {c : Char} {b : UInt8}
    (hm : b ∈ String.utf8EncodeChar c) :
    (c.val ≤ 0x7F ∧ b = c.val.toUInt8) ∨ (0x80 ≤ c.val ∧ 0x80 ≤ b) := by
  rw [String.utf8EncodeChar_eq_utf8EncodeCharFast] at hm
  unfold String.utf8EncodeCharFast at hm
  dsimp only at hm
  by_cases ha : c.val ≤ 0x7F
  · simp only [ha, ite_true, List.mem_singleton] at hm
    exact .inl ⟨ha, hm⟩
  · have hc : 0x80 ≤ c.val := by
      change ¬c.val.toNat ≤ 127 at ha
      change 128 ≤ c.val.toNat
      omega
    simp only [ha, ite_false] at hm
    split at hm
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
      rcases hm with rfl | rfl
      all_goals exact .inr ⟨hc, Std.le_trans (by decide) (or_byte_ge _ _)⟩
    · split at hm
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl
        all_goals exact .inr ⟨hc, Std.le_trans (by decide) (or_byte_ge _ _)⟩
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl | rfl
        all_goals exact .inr ⟨hc, Std.le_trans (by decide) (or_byte_ge _ _)⟩

theorem utf8EncodeChar_control_iff {c : Char} {b : UInt8}
    (hm : b ∈ String.utf8EncodeChar c) : 0x20 ≤ c.val ↔ 0x20 ≤ b := by
  rcases utf8EncodeChar_byte_cases hm with ⟨hc, rfl⟩ | ⟨hc, hb⟩
  · change 32 ≤ c.val.toNat ↔ 32 ≤ c.val.toUInt8.toNat
    have hb : c.val.toUInt8.toNat = c.val.toNat := by
      rw [UInt32.toNat_toUInt8]
      change c.val.toNat ≤ 127 at hc
      omega
    rw [hb]
  · exact ⟨fun _ => Std.le_trans (by decide) hb, fun _ => Std.le_trans (by decide) hc⟩

theorem utf8DecodeChar_bytesAt {b : ByteArray} {i : Nat} {c : Char}
    (h : b.utf8DecodeChar? i = some c) :
    bytesAt b i = String.utf8EncodeChar c ++ bytesAt b (i + c.utf8Size) := by
  rw [ByteArray.utf8DecodeChar?_eq_utf8DecodeChar?_extract] at h
  have he := congrArg (fun a : ByteArray => a.data.toList)
    (ByteArray.eq_of_utf8DecodeChar?_eq_some h)
  simp only [bytesAt_extract, ByteArray.toList_data_append,
    List.toList_data_toByteArray] at he
  have hd := congrArg (List.drop c.utf8Size) he
  simp only [bytesAt, List.drop_drop, List.drop_append, String.length_utf8EncodeChar,
    Nat.sub_self] at hd
  simp only [← String.length_utf8EncodeChar c, List.drop_length, List.nil_append,
    Nat.add_zero] at hd
  simp only [String.length_utf8EncodeChar] at hd
  change bytesAt b i = String.utf8EncodeChar c ++
    (b.extract i b.size).data.toList.drop c.utf8Size at he
  rw [← hd] at he
  exact he

theorem utf8DecodeChar_iff {b : ByteArray} {i : Nat} {c : Char} :
    b.utf8DecodeChar? i = some c ↔
      bytesAt b i = String.utf8EncodeChar c ++ bytesAt b (i + c.utf8Size) := by
  constructor
  · exact utf8DecodeChar_bytesAt
  · intro h
    rw [ByteArray.utf8DecodeChar?_eq_utf8DecodeChar?_extract]
    have he : b.extract i b.size =
        (String.utf8EncodeChar c).toByteArray ++ (bytesAt b (i + c.utf8Size)).toByteArray := by
      apply ByteArray.ext
      apply Array.toList_inj.mp
      simpa only [bytesAt_extract, ByteArray.toList_data_append,
        List.toList_data_toByteArray] using h
    rw [he]
    exact ByteArray.utf8DecodeChar?_utf8EncodeChar_append

theorem utf8DecodeChar_first_mem {b : ByteArray} {i : Nat} {c : Char}
    (h : b.utf8DecodeChar? i = some c) :
    b[i]'(ByteArray.lt_size_of_isSome_utf8DecodeChar? (by simp [h])) ∈ String.utf8EncodeChar c := by
  have hi : i < b.size := ByteArray.lt_size_of_isSome_utf8DecodeChar? (by simp [h])
  have hp := utf8DecodeChar_bytesAt h
  cases he : String.utf8EncodeChar c with
  | nil =>
    have hl := String.length_utf8EncodeChar c
    rw [he] at hl
    have := c.utf8Size_pos
    simp only [List.length_nil] at hl
    omega
  | cons d ds =>
    rw [he, bytesAt_cons hi] at hp
    have hh : b[i] = d := (List.cons.inj hp).1
    rw [hh]
    simp

end FvapiProof.Json
