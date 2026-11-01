import FvapiProof.Json.Decode.Utf8

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

local notation "scan" => FvapiSpec.Json.lexicalDepth.go

theorem scan_inside_byte {b : UInt8} (h : b ≠ 0x22 ∧ b ≠ 0x5C)
    (cs : Bytes) (level top : Nat) :
    scan (b :: cs) true false level top = scan cs true false level top := by
  rw [lexicalDepth.go, bne_iff_ne.mpr h.1, beq_eq_false_iff_ne.mpr h.2]

theorem scan_inside_bytes (bs rest : Bytes) (level top : Nat)
    (h : ∀ b ∈ bs, b ≠ 0x22 ∧ b ≠ 0x5C) :
    scan (bs ++ rest) true false level top = scan rest true false level top := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
    have hb := h b (by simp)
    have ht : ∀ b ∈ bs, b ≠ 0x22 ∧ b ≠ 0x5C := fun b hm => h b (by simp [hm])
    rw [List.cons_append, scan_inside_byte hb]
    exact ih ht

theorem hexVal_safe {b : UInt8} {n : Nat} (h : hexVal b = some n) :
    b ≠ 0x22 ∧ b ≠ 0x5C := by
  constructor <;> intro he <;> subst b <;> simp [hexVal] at h

theorem hex4_scan {cs rest : Bytes} {n : Nat} (h : Hex4 cs n rest)
    (level top : Nat) : scan cs true false level top = scan rest true false level top := by
  cases h with
  | mk ha hb hc hd =>
    rw [scan_inside_byte (hexVal_safe ha), scan_inside_byte (hexVal_safe hb),
      scan_inside_byte (hexVal_safe hc), scan_inside_byte (hexVal_safe hd)]

theorem escape_scan {cs rest : Bytes} {c : Char} (h : Escape cs c rest)
    (level top : Nat) : scan cs true true level top = scan rest true false level top := by
  cases h with
  | unit hh _ => simpa only [lexicalDepth.go] using hex4_scan hh level top
  | pair hh hl _ _ _ _ =>
    simp [lexicalDepth.go]
    rw [hex4_scan hh]
    exact hex4_scan hl level top
  | _ => rfl

theorem strBody_scan {cs rest : Bytes} {chs : List Char} (h : StrBody cs chs rest)
    (level top : Nat) : scan cs true false level top = scan rest false false level top := by
  induction h with
  | close => simp [lexicalDepth.go]
  | raw _ hq hb _ ih =>
    rw [scan_inside_bytes _ _ _ _ (utf8EncodeChar_safe hq hb)]
    exact ih
  | esc he _ ih =>
    change scan _ true true level top = _
    rw [escape_scan he]
    exact ih

theorem strLit_scan {cs rest : Bytes} {s : String} (h : StrLit cs s rest)
    (level top : Nat) : scan cs false false level top = scan rest false false level top := by
  cases h with
  | mk hb => simpa [lexicalDepth.go] using strBody_scan hb level top

theorem ws_scan {cs rest : Bytes} (h : Ws cs rest) (level top : Nat) :
    scan cs false false level top = scan rest false false level top := by
  induction h with
  | stop => rfl
  | skip hw _ ih =>
    simp only [isWs, Bool.or_eq_true, beq_iff_eq] at hw
    rcases hw with ((rfl | rfl) | rfl) | rfl <;> simpa [lexicalDepth.go] using ih

theorem digit_scan {b : UInt8} (hd : isDigit b = true) (cs : Bytes) (level top : Nat) :
    scan (b :: cs) false false level top = scan cs false false level top := by
  have hn : 48 ≤ b.toNat ∧ b.toNat ≤ 57 := by
    simpa only [isDigit, Bool.and_eq_true, decide_eq_true_eq, UInt8.le_iff_toNat_le,
      UInt8.reduceToNat] using hd
  have h22 : b ≠ 0x22 := by intro he; subst b; simp at hn
  have h5b : b ≠ 0x5B := by intro he; subst b; simp at hn
  have h7b : b ≠ 0x7B := by intro he; subst b; simp at hn
  have h5d : b ≠ 0x5D := by intro he; subst b; simp at hn
  have h7d : b ≠ 0x7D := by intro he; subst b; simp at hn
  simp [lexicalDepth.go, h22, h5b, h7b, h5d, h7d]

theorem digitRun_scan {cs rest : Bytes} {acc n : Nat} (h : DigitRun acc cs n rest)
    (level top : Nat) : scan cs false false level top = scan rest false false level top := by
  induction h with
  | last hd _ => exact digit_scan hd _ _ _
  | more hd _ ih => rw [digit_scan hd]; exact ih

theorem intLit_scan {cs rest : Bytes} {n : Int} (h : IntLit cs n rest)
    (level top : Nat) : scan cs false false level top = scan rest false false level top := by
  cases h with
  | zero => simp [lexicalDepth.go]
  | pos _ _ hd _ => exact digitRun_scan hd level top
  | neg _ _ hd _ => simpa [lexicalDepth.go] using digitRun_scan hd level top

mutual
/-- `level ≤ top` is needed even for a scalar: the accumulated maximum already includes level. -/
theorem value_scan {cs rest : Bytes} {v : Value} (h : ValueP cs v rest)
    (level top : Nat) (ht : level ≤ top) :
    scan cs false false level top =
      scan rest false false level (max top (level + depth v)) := by
  cases h with
  | nullLit => simp [lexicalDepth.go, depth, Nat.max_eq_left ht]
  | trueLit => simp [lexicalDepth.go, depth, Nat.max_eq_left ht]
  | falseLit => simp [lexicalDepth.go, depth, Nat.max_eq_left ht]
  | int hi => simpa [depth, Nat.max_eq_left ht] using intLit_scan hi level top
  | str hs => simpa [depth, Nat.max_eq_left ht] using strLit_scan hs level top
  | arrEmpty hw =>
    simp [lexicalDepth.go]
    rw [ws_scan hw]
    simp [lexicalDepth.go, depth, depthList]
  | arr hw he =>
    simp [lexicalDepth.go]
    rw [ws_scan hw, elems_scan he (level + 1) (max top (level + 1)) (by omega)]
    simp only [depth]
    congr 1 <;> omega
  | objEmpty hw =>
    simp [lexicalDepth.go]
    rw [ws_scan hw]
    simp [lexicalDepth.go, depth, depthMembers]
  | obj hw hm =>
    simp [lexicalDepth.go]
    rw [ws_scan hw, members_scan hm (level + 1) (max top (level + 1)) (by omega)]
    simp only [depth]
    congr 1 <;> omega

theorem elems_scan {cs rest : Bytes} {xs : List Value} (h : Elems cs xs rest)
    (level top : Nat) (ht : level ≤ top) :
    scan cs false false level top =
      scan rest false false (level - 1) (max top (level + depthList xs)) := by
  cases h with
  | last hv hw =>
    rw [value_scan hv level top ht, ws_scan hw]
    simp [lexicalDepth.go, depthList]
  | cons hv hw hw' he =>
    rw [value_scan hv level top ht, ws_scan hw]
    simp [lexicalDepth.go]
    rw [ws_scan hw', elems_scan he]
    · simp only [depthList]
      congr 1 <;> omega
    · omega

theorem members_scan {cs rest : Bytes} {ms : List (String × Value)} (h : Members cs ms rest)
    (level top : Nat) (ht : level ≤ top) :
    scan cs false false level top =
      scan rest false false (level - 1) (max top (level + depthMembers ms)) := by
  cases h with
  | last hk hw₁ hw₂ hv hw₃ =>
    rw [strLit_scan hk, ws_scan hw₁]
    simp [lexicalDepth.go]
    rw [ws_scan hw₂, value_scan hv level top ht, ws_scan hw₃]
    simp [lexicalDepth.go, depthMembers]
  | cons hk hw₁ hw₂ hv hw₃ hw₄ hm =>
    rw [strLit_scan hk, ws_scan hw₁]
    simp [lexicalDepth.go]
    rw [ws_scan hw₂, value_scan hv level top ht, ws_scan hw₃]
    simp [lexicalDepth.go]
    rw [ws_scan hw₄, members_scan hm]
    · simp only [depthMembers]
      congr 1 <;> omega
    · omega
end

theorem lexicalDepth_text {bs : Bytes} {v : Value} (h : Text bs v) :
    lexicalDepth bs = depth v := by
  rcases h with ⟨r₁, r₂, hw₁, hv, hw₂⟩
  unfold lexicalDepth
  rw [ws_scan hw₁, value_scan hv 0 0 (by omega), ws_scan hw₂]
  simp [lexicalDepth.go]

#print axioms lexicalDepth_text

end FvapiProof.Json
