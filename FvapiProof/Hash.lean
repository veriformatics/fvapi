import FvapiSelf.Hash

namespace FvapiProof.Hash

open FvapiSpec.Hash

set_option maxRecDepth 4096 in
private theorem nibble_chars_fin : ∀ i : Fin 256,
    let x := UInt8.ofNat i.val
    [Fvapi.Hash.hexDigit (x >>> 4), Fvapi.Hash.hexDigit (x &&& 15)] =
      [hexAlphabet.getD (x.toNat / 16) '?', hexAlphabet.getD (x.toNat % 16) '?'] := by
  decide

private theorem nibble_chars (x : UInt8) :
    [Fvapi.Hash.hexDigit (x >>> 4), Fvapi.Hash.hexDigit (x &&& 15)] =
      [hexAlphabet.getD (x.toNat / 16) '?', hexAlphabet.getD (x.toNat % 16) '?'] := by
  simpa using nibble_chars_fin ⟨x.toNat, x.toNat_lt⟩

private theorem foldl_loop_eq {α : Type} (f : α → UInt8 → α) (b : ByteArray)
    (n j : Nat) (h : j + n = b.size) (s : α) :
    (ByteArray.foldlM.loop (m := Id) (fun acc x => pure (f acc x)) b b.size
      (Nat.le_refl _) n j s).run = (b.data.toList.drop j).foldl f s := by
  induction n generalizing j s with
  | zero =>
    have hj : j = b.size := by omega
    rw [ByteArray.foldlM.loop]
    simp only [hj, Nat.lt_irrefl, ↓reduceDIte]
    have hz : b.data.toList.drop b.size = [] := List.drop_eq_nil_of_le (by simp)
    rw [hz]
    rfl
  | succ n ih =>
    have hj : j < b.size := by omega
    rw [ByteArray.foldlM.loop]
    simp only [hj, ↓reduceDIte, Id.run, pure, Bind.bind]
    calc
      _ = (b.data.toList.drop (j + 1)).foldl f (f s b[j]) :=
        ih (j + 1) (by omega) _
      _ = _ := by
        rw [List.drop_eq_getElem_cons (i := j) (l := b.data.toList) (by simpa using hj)]
        rfl

private theorem byte_foldl_eq {α : Type} (f : α → UInt8 → α) (b : ByteArray) (s : α) :
    b.foldl f s = b.data.toList.foldl f s := by
  simp only [ByteArray.foldl, ByteArray.foldlM, Nat.le_refl, ↓reduceDIte, Nat.sub_zero]
  simpa using foldl_loop_eq f b b.size 0 (by omega) s

private theorem hex_fold (xs : List UInt8) (s : String) :
    (xs.foldl (fun s x => (s.push (Fvapi.Hash.hexDigit (x >>> 4))).push
      (Fvapi.Hash.hexDigit (x &&& 15))) s).toList = s.toList ++ hexChars xs := by
  induction xs generalizing s with
  | nil => simp [hexChars]
  | cons x xs ih =>
    simpa only [List.foldl_cons, ih, String.toList_push, hexChars, List.flatMap_cons,
      List.append_assoc, List.cons_append, List.nil_append] using
      congrArg (fun t => s.toList ++ t ++ hexChars xs) (nibble_chars x)

theorem hex_exact : FvapiSelf.Hash.HexExact := by
  intro b
  rw [Fvapi.Hash.hex, byte_foldl_eq, hex_fold]
  simp

end FvapiProof.Hash

#print axioms FvapiProof.Hash.hex_exact
