import FvapiSelf.Json

namespace FvapiProof.Json

open Fvapi.Json

abbrev bytesAt (b : ByteArray) (i : Nat) : List UInt8 := b.data.toList.drop i

theorem bytesAt_cons {b : ByteArray} {i : Nat} (h : i < b.size) :
    bytesAt b i = b[i] :: bytesAt b (i + 1) := by
  exact List.drop_eq_getElem_cons (by simpa using h)

theorem bytesAt_nil {b : ByteArray} {i : Nat} (h : b.size ≤ i) :
    bytesAt b i = [] := by
  exact List.drop_eq_nil_of_le (by simpa using h)

theorem scanDepth_go_eq (b : ByteArray) (i : Nat) (s e : Bool) (level top : Nat) :
    scanDepth.go b i s e level top =
      FvapiSpec.Json.lexicalDepth.go (bytesAt b i) s e level top := by
  rw [scanDepth.go]
  by_cases h : i < b.size
  · simp only [h, dite_true]
    rw [bytesAt_cons h]
    cases s <;> cases e <;> simp only [FvapiSpec.Json.lexicalDepth.go, Bool.false_eq_true,
      ite_false, ite_true]
    all_goals repeat' first | split | exact scanDepth_go_eq b (i + 1) _ _ _ _
  · simp [h, bytesAt_nil (by omega : b.size ≤ i), FvapiSpec.Json.lexicalDepth.go]
termination_by b.size - i

theorem scanDepth_eq (b : ByteArray) :
    scanDepth b = FvapiSpec.Json.lexicalDepth b.data.toList := by
  exact scanDepth_go_eq b 0 false false 0 0

end FvapiProof.Json
