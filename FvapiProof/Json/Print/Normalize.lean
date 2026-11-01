import FvapiSelf.Json

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

mutual
theorem canonical_invariants : (v : Value) → keysAscend v = true →
    canon v = v ∧ hasDupKey v = false
  | .null, _ => by simp [canon, hasDupKey]
  | .bool b, _ => by simp [canon, hasDupKey]
  | .int n, _ => by simp [canon, hasDupKey]
  | .str s, _ => by simp [canon, hasDupKey]
  | .arr xs, h => by
    have hi := canonicalList_invariants xs h
    simp [canon, hasDupKey, hi.1, hi.2]
  | .obj ms, h => by
    simp only [keysAscend, Bool.and_eq_true, decide_eq_true_eq] at h
    have hi := canonicalMembers_invariants ms h.2
    have hn : (ms.map (·.1)).Nodup := h.1.imp String.ne_of_lt
    have hs : ms.Pairwise (fun a b => decide (a.1 ≤ b.1) = true) := by
      apply (List.pairwise_map.mp h.1).imp
      intro a b hab
      simp only [decide_eq_true_eq]
      exact Std.le_of_lt hab
    simp [canon, hi.1, List.mergeSort_of_pairwise hs, hasDupKey, hn, hi.2]
termination_by v => sizeOf v

theorem canonicalList_invariants : (xs : List Value) → keysAscendList xs = true →
    canonList xs = xs ∧ hasDupKeyList xs = false
  | [], _ => by simp [canonList, hasDupKeyList]
  | v :: vs, h => by
    simp only [keysAscendList, Bool.and_eq_true] at h
    have hv := canonical_invariants v h.1
    have hs := canonicalList_invariants vs h.2
    simp [canonList, hasDupKeyList, hv.1, hv.2, hs.1, hs.2]
termination_by xs => sizeOf xs

theorem canonicalMembers_invariants : (ms : List (String × Value)) →
    keysAscendMembers ms = true → canonMembers ms = ms ∧ hasDupKeyMembers ms = false
  | [], _ => by simp [canonMembers, hasDupKeyMembers]
  | (k, v) :: ms, h => by
    simp only [keysAscendMembers, Bool.and_eq_true] at h
    have hv := canonical_invariants v h.1
    have hs := canonicalMembers_invariants ms h.2
    simp [canonMembers, hasDupKeyMembers, hv.1, hv.2, hs.1, hs.2]
termination_by ms => sizeOf ms
end

end FvapiProof.Json
