import FvapiProof.Json.Print.Strings
import FvapiProof.Json.Print.Numbers

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

theorem canonical_first_not_ws (v : Value) (rest : Bytes) :
    ∀ b ∈ (canonical v ++ rest).head?, isWs b = false := by
  cases v with
  | null => simp [canonical, isWs]
  | bool b => cases b <;> simp [canonical, isWs]
  | int n => exact intText_first_not_ws n rest
  | str s => simp [canonical, strText, isWs]
  | arr xs => simp [canonical, isWs]
  | obj ms => simp [canonical, isWs]

theorem canonicalList_first_not_ws (xs : List Value) (hne : xs ≠ []) (rest : Bytes) :
    ∀ b ∈ (canonicalList xs ++ rest).head?, isWs b = false := by
  cases xs with
  | nil => contradiction
  | cons v vs =>
    cases vs with
    | nil => exact canonical_first_not_ws v rest
    | cons w ws =>
      simpa only [canonicalList, List.append_assoc] using
        canonical_first_not_ws v (0x2C :: canonicalList (w :: ws) ++ rest)

private theorem canonicalMembers_first_not_ws (ms : List (String × Value))
    (hne : ms ≠ []) (rest : Bytes) :
    ∀ b ∈ (canonicalMembers ms ++ rest).head?, isWs b = false := by
  cases ms with
  | nil => contradiction
  | cons p ms =>
    obtain ⟨k, v⟩ := p
    cases ms <;> simp [canonicalMembers, strText, isWs]

mutual
theorem canonical_value : (v : Value) → intsFit v = true → (rest : Bytes) →
    (∀ b ∈ rest.head?, isDigit b = false) → ValueP (canonical v ++ rest) v rest
  | .null, _, rest, _ => by
    simpa only [canonical, List.cons_append, List.nil_append] using ValueP.nullLit (rest := rest)
  | .bool true, _, rest, _ => by
    simpa only [canonical, List.cons_append, List.nil_append] using ValueP.trueLit (rest := rest)
  | .bool false, _, rest, _ => by
    simpa only [canonical, List.cons_append, List.nil_append] using ValueP.falseLit (rest := rest)
  | .int n, hi, rest, hr =>
    ValueP.int (intText_literal n (of_decide_eq_true hi) rest hr)
  | .str s, _, rest, _ => ValueP.str (strText_literal s rest)
  | .arr [], _, rest, _ => by
    have hw : Ws (0x5D :: rest) (0x5D :: rest) := Ws.stop (by simp [isWs])
    simpa only [canonical, canonicalList, List.cons_append, List.nil_append] using
      ValueP.arrEmpty hw
  | .arr (v :: vs), hi, rest, _ => by
    have he := canonical_elems (v :: vs) (by simp) hi rest
    have hw := Ws.stop (canonicalList_first_not_ws (v :: vs) (by simp) (0x5D :: rest))
    simpa only [canonical, List.cons_append, List.append_eq, List.append_assoc,
      List.singleton_append, List.nil_append] using ValueP.arr hw he
  | .obj [], _, rest, _ => by
    have hw : Ws (0x7D :: rest) (0x7D :: rest) := Ws.stop (by simp [isWs])
    simpa only [canonical, canonicalMembers, List.cons_append, List.nil_append] using
      ValueP.objEmpty hw
  | .obj (p :: ms), hi, rest, _ => by
    have hm := canonical_members (p :: ms) (by simp) hi rest
    have hw := Ws.stop (canonicalMembers_first_not_ws (p :: ms) (by simp) (0x7D :: rest))
    simpa only [canonical, List.cons_append, List.append_eq, List.append_assoc,
      List.singleton_append, List.nil_append] using ValueP.obj hw hm
termination_by v => sizeOf v

theorem canonical_elems : (xs : List Value) → xs ≠ [] → intsFitList xs = true →
    (rest : Bytes) → Elems (canonicalList xs ++ 0x5D :: rest) xs rest
  | [], hne, _, _ => False.elim (hne rfl)
  | [v], _, hi, rest => by
    have hv : intsFit v = true := by simpa only [intsFitList, Bool.and_true] using hi
    exact Elems.last (canonical_value v hv (0x5D :: rest) (by simp [isDigit]))
      (Ws.stop (by simp [isWs]))
  | v :: w :: vs, _, hi, rest => by
    simp only [intsFitList, Bool.and_eq_true] at hi
    have hr : intsFitList (w :: vs) = true := by
      simpa only [intsFitList, Bool.and_eq_true] using hi.2
    have hv := canonical_value v hi.1
      (0x2C :: (canonicalList (w :: vs) ++ 0x5D :: rest)) (by simp [isDigit])
    have he := canonical_elems (w :: vs) (by simp) hr rest
    have ha := Elems.cons hv (Ws.stop (by simp [isWs]))
      (Ws.stop (canonicalList_first_not_ws _ (by simp) _)) he
    simpa only [canonicalList, List.append_assoc, List.cons_append] using ha
termination_by xs => sizeOf xs

theorem canonical_members : (ms : List (String × Value)) → ms ≠ [] →
    intsFitMembers ms = true → (rest : Bytes) →
    Members (canonicalMembers ms ++ 0x7D :: rest) ms rest
  | [], hne, _, _ => False.elim (hne rfl)
  | [(k, v)], _, hi, rest => by
    have hv : intsFit v = true := by simpa only [intsFitMembers, Bool.and_true] using hi
    have hk := strText_literal k (0x3A :: (canonical v ++ 0x7D :: rest))
    have hvp := canonical_value v hv (0x7D :: rest) (by simp [isDigit])
    have hm := Members.last hk (Ws.stop (by simp [isWs]))
      (Ws.stop (canonical_first_not_ws _ _)) hvp (Ws.stop (by simp [isWs]))
    simpa only [canonicalMembers, List.append_assoc, List.cons_append] using hm
  | (k, v) :: p :: ms, _, hi, rest => by
    simp only [intsFitMembers, Bool.and_eq_true] at hi
    have hr : intsFitMembers (p :: ms) = true := by
      simpa only [intsFitMembers, Bool.and_eq_true] using hi.2
    have hk := strText_literal k
      (0x3A :: (canonical v ++ 0x2C :: (canonicalMembers (p :: ms) ++ 0x7D :: rest)))
    have hvp := canonical_value v hi.1
      (0x2C :: (canonicalMembers (p :: ms) ++ 0x7D :: rest)) (by simp [isDigit])
    have hms := canonical_members (p :: ms) (by simp) hr rest
    have hm := Members.cons hk (Ws.stop (by simp [isWs]))
      (Ws.stop (canonical_first_not_ws _ _)) hvp (Ws.stop (by simp [isWs]))
      (Ws.stop (canonicalMembers_first_not_ws _ (by simp) _)) hms
    simpa only [canonicalMembers, List.append_assoc, List.cons_append] using hm
termination_by ms => sizeOf ms
end

theorem canonical_text (v : Value) (hi : intsFit v = true) : Text (canonical v) v := by
  refine ⟨canonical v, [], ?_, ?_, Ws.stop (by simp)⟩
  · exact Ws.stop (by simpa only [List.append_nil] using canonical_first_not_ws v [])
  · simpa only [List.append_nil] using canonical_value v hi [] (by simp)

end FvapiProof.Json
