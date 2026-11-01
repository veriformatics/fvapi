import FvapiProof.Json.Print.Strings
import FvapiProof.Json.Print.Numbers

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

mutual
theorem lexical_canonical : (v : Value) → (rest : Bytes) → (level top : Nat) → level ≤ top →
    lexicalDepth.go (canonical v ++ rest) false false level top =
      lexicalDepth.go rest false false level (max top (level + depth v))
  | .null, rest, level, top, ht => by
    simp [canonical, lexicalDepth.go, depth, Nat.max_eq_left ht]
  | .bool true, rest, level, top, ht => by
    simp [canonical, lexicalDepth.go, depth, Nat.max_eq_left ht]
  | .bool false, rest, level, top, ht => by
    simp [canonical, lexicalDepth.go, depth, Nat.max_eq_left ht]
  | .int n, rest, level, top, ht => by
    simpa only [canonical, depth, Nat.add_zero, Nat.max_eq_left ht] using
      lexical_intText n rest level top
  | .str s, rest, level, top, ht => by
    simpa only [canonical, depth, Nat.add_zero, Nat.max_eq_left ht] using
      lexical_strText s rest level top
  | .arr xs, rest, level, top, _ => by
    simp only [canonical, List.cons_append, List.append_assoc, List.nil_append]
    change lexicalDepth.go (canonicalList xs ++ 0x5D :: rest) false false (level + 1)
      (max top (level + 1)) = _
    rw [lexical_canonicalList xs (0x5D :: rest) (level + 1) (max top (level + 1))
      (Nat.le_max_right _ _)]
    change lexicalDepth.go rest false false (level + 1 - 1)
      (max (max top (level + 1)) (level + 1 + depthList xs)) = _
    have hm : max (max top (level + 1)) (level + 1 + depthList xs) =
        max top (level + depth (.arr xs)) := by simp only [depth]; omega
    rw [hm, Nat.add_sub_cancel]
  | .obj ms, rest, level, top, _ => by
    simp only [canonical, List.cons_append, List.append_assoc, List.nil_append]
    change lexicalDepth.go (canonicalMembers ms ++ 0x7D :: rest) false false (level + 1)
      (max top (level + 1)) = _
    rw [lexical_canonicalMembers ms (0x7D :: rest) (level + 1) (max top (level + 1))
      (Nat.le_max_right _ _)]
    change lexicalDepth.go rest false false (level + 1 - 1)
      (max (max top (level + 1)) (level + 1 + depthMembers ms)) = _
    have hm : max (max top (level + 1)) (level + 1 + depthMembers ms) =
        max top (level + depth (.obj ms)) := by simp only [depth]; omega
    rw [hm, Nat.add_sub_cancel]
termination_by v => sizeOf v

theorem lexical_canonicalList : (xs : List Value) → (rest : Bytes) →
    (level top : Nat) → level ≤ top →
    lexicalDepth.go (canonicalList xs ++ rest) false false level top =
      lexicalDepth.go rest false false level (max top (level + depthList xs))
  | [], rest, level, top, ht => by
    simp [canonicalList, depthList, Nat.max_eq_left ht]
  | [v], rest, level, top, ht => by
    simpa only [canonicalList, depthList, Nat.max_zero] using
      lexical_canonical v rest level top ht
  | v :: w :: vs, rest, level, top, ht => by
    simp only [canonicalList, List.append_assoc, List.cons_append]
    rw [lexical_canonical v (0x2C :: (canonicalList (w :: vs) ++ rest)) level top ht]
    change lexicalDepth.go (canonicalList (w :: vs) ++ rest) false false level
      (max top (level + depth v)) = _
    have ht' : level ≤ max top (level + depth v) := by omega
    rw [lexical_canonicalList (w :: vs) rest level (max top (level + depth v)) ht']
    have hm : max (max top (level + depth v)) (level + depthList (w :: vs)) =
        max top (level + depthList (v :: w :: vs)) := by simp only [depthList]; omega
    rw [hm]
termination_by xs => sizeOf xs

theorem lexical_canonicalMembers : (ms : List (String × Value)) → (rest : Bytes) →
    (level top : Nat) → level ≤ top →
    lexicalDepth.go (canonicalMembers ms ++ rest) false false level top =
      lexicalDepth.go rest false false level (max top (level + depthMembers ms))
  | [], rest, level, top, ht => by
    simp [canonicalMembers, depthMembers, Nat.max_eq_left ht]
  | [(k, v)], rest, level, top, ht => by
    simp only [canonicalMembers, List.append_assoc, List.cons_append]
    rw [lexical_strText]
    change lexicalDepth.go (canonical v ++ rest) false false level top = _
    have hv := lexical_canonical v rest level top ht
    simpa only [depthMembers, Nat.max_zero] using hv
  | (k, v) :: p :: ms, rest, level, top, ht => by
    simp only [canonicalMembers, List.append_assoc, List.cons_append]
    rw [lexical_strText]
    change lexicalDepth.go (canonical v ++ 0x2C :: (canonicalMembers (p :: ms) ++ rest))
      false false level top = _
    rw [lexical_canonical v (0x2C :: (canonicalMembers (p :: ms) ++ rest)) level top ht]
    change lexicalDepth.go (canonicalMembers (p :: ms) ++ rest) false false level
      (max top (level + depth v)) = _
    have ht' : level ≤ max top (level + depth v) := by omega
    rw [lexical_canonicalMembers (p :: ms) rest level (max top (level + depth v)) ht']
    have hm : max (max top (level + depth v)) (level + depthMembers (p :: ms)) =
        max top (level + depthMembers ((k, v) :: p :: ms)) := by
      simp only [depthMembers]
      omega
    rw [hm]
termination_by ms => sizeOf ms
end

theorem lexicalDepth_canonical (v : Value) : lexicalDepth (canonical v) = depth v := by
  have h := lexical_canonical v [] 0 0 (Nat.le_refl _)
  simpa [lexicalDepth, lexicalDepth.go] using h

end FvapiProof.Json
