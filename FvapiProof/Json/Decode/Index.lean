import FvapiProof.Json.Decode.Lexical

namespace FvapiProof.Json

open Fvapi.Json

theorem bytesAt_head (b : ByteArray) (i : Nat) : (bytesAt b i).head? = b[i]? := by
  by_cases h : i < b.size
  · rw [bytesAt_cons h]
    simp [h]
  · rw [bytesAt_nil (by omega : b.size ≤ i)]
    simp [h]

theorem bytesAt_tail (b : ByteArray) (i : Nat) :
    (bytesAt b i).tail = bytesAt b (i + 1) := by
  by_cases h : i < b.size
  · rw [bytesAt_cons h]
    rfl
  · rw [bytesAt_nil (by omega : b.size ≤ i), bytesAt_nil (by omega : b.size ≤ i + 1)]
    rfl

theorem bytesAt_cons_iff (b : ByteArray) (i : Nat) (c : UInt8) (rest : List UInt8) :
    bytesAt b i = c :: rest ↔ b[i]? = some c ∧ bytesAt b (i + 1) = rest := by
  constructor
  · intro h
    constructor
    · rw [← bytesAt_head, h]
      rfl
    · rw [← bytesAt_tail, h]
      rfl
  · rintro ⟨h, ht⟩
    have hi : i < b.size := by
      by_cases hi : i < b.size
      · exact hi
      · simp [hi] at h
    rw [bytesAt_cons hi, ht]
    have hc : b[i] = c := by simpa [hi] using h
    rw [hc]

theorem index_lt_of_some {b : ByteArray} {i : Nat} {c : UInt8} (h : b[i]? = some c) :
    i < b.size := by
  by_cases hi : i < b.size
  · exact hi
  · simp [hi] at h

theorem bytesAt_of_some {b : ByteArray} {i : Nat} {c : UInt8} (h : b[i]? = some c) :
    bytesAt b i = c :: bytesAt b (i + 1) :=
  (bytesAt_cons_iff b i c _).mpr ⟨h, rfl⟩

theorem bytesAt_length (b : ByteArray) (i : Nat) : (bytesAt b i).length = b.size - i := by
  simp [bytesAt]

theorem bytesAt_nil_iff {b : ByteArray} {i : Nat} (hi : i ≤ b.size) :
    bytesAt b i = [] ↔ i = b.size := by
  constructor
  · intro he
    have hl := congrArg List.length he
    rw [bytesAt_length] at hl
    simp only [List.length_nil] at hl
    omega
  · intro he
    subst i
    exact bytesAt_nil (by omega)

theorem bytesAt_drop (b : ByteArray) (i n : Nat) :
    (bytesAt b i).drop n = bytesAt b (i + n) := by
  exact List.drop_drop

theorem bytesAt_prefix {b : ByteArray} {i : Nat} {pre rest : List UInt8}
    (h : bytesAt b i = pre ++ rest) : bytesAt b (i + pre.length) = rest := by
  have hd := congrArg (List.drop pre.length) h
  simpa only [bytesAt_drop, List.drop_append, List.drop_length, Nat.sub_self,
    List.drop_zero, List.nil_append] using hd

end FvapiProof.Json
