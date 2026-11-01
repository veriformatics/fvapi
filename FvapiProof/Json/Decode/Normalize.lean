import FvapiProof.Json.Decode.Post
import Init.Data.Bool

namespace FvapiProof.Json

open Fvapi.Json (Value)
open FvapiSpec.Json

theorem intsFitMembers_all (ms : List (String × Value)) :
    intsFitMembers ms = ms.all (fun p => intsFit p.2) := by
  induction ms with
  | nil => rfl
  | cons p ms ih => cases p; simp [intsFitMembers, ih]

theorem stringsFitMembers_all (ms : List (String × Value)) :
    stringsFitMembers ms = ms.all (fun p => decide (p.1.utf8ByteSize ≤ maxStringBytes) &&
      stringsFit p.2) := by
  induction ms with
  | nil => rfl
  | cons p ms ih => cases p; simp [stringsFitMembers, ih]

theorem keysAscendMembers_all (ms : List (String × Value)) :
    keysAscendMembers ms = ms.all (fun p => keysAscend p.2) := by
  induction ms with
  | nil => rfl
  | cons p ms ih => cases p; simp [keysAscendMembers, ih]

theorem depthMembers_foldr (ms : List (String × Value)) :
    depthMembers ms = ms.foldr (fun p n => max (depth p.2) n) 0 := by
  induction ms with
  | nil => rfl
  | cons p ms ih => cases p; simp [depthMembers, ih]

theorem intsFitMembers_perm {ms ns : List (String × Value)} (h : ms.Perm ns) :
    intsFitMembers ms = intsFitMembers ns := by
  rw [intsFitMembers_all, intsFitMembers_all]
  exact List.Perm.all_eq h

theorem stringsFitMembers_perm {ms ns : List (String × Value)} (h : ms.Perm ns) :
    stringsFitMembers ms = stringsFitMembers ns := by
  rw [stringsFitMembers_all, stringsFitMembers_all]
  exact List.Perm.all_eq h

theorem keysAscendMembers_perm {ms ns : List (String × Value)} (h : ms.Perm ns) :
    keysAscendMembers ms = keysAscendMembers ns := by
  rw [keysAscendMembers_all, keysAscendMembers_all]
  exact List.Perm.all_eq h

theorem depthMembers_perm {ms ns : List (String × Value)} (h : ms.Perm ns) :
    depthMembers ms = depthMembers ns := by
  rw [depthMembers_foldr, depthMembers_foldr]
  exact h.foldr_eq' (f := fun p n => max (depth p.2) n)
    (fun _ _ _ _ _ => Nat.max_left_comm _ _ _) 0

mutual
theorem canon_invariants (v : Value) :
    intsFit (canon v) = intsFit v ∧ stringsFit (canon v) = stringsFit v ∧
      depth (canon v) = depth v := by
  cases v with
  | arr xs =>
    rcases canonList_invariants xs with ⟨hi, hs, hd⟩
    simp only [canon, intsFit, stringsFit, depth, hi, hs, hd]
    simp
  | obj ms =>
    rcases canonMembers_invariants ms with ⟨hi, hs, hd⟩
    have hp := List.mergeSort_perm (canonMembers ms) (fun a b => decide (a.1 ≤ b.1))
    simp only [canon, intsFit, stringsFit, depth, intsFitMembers_perm hp,
      stringsFitMembers_perm hp, depthMembers_perm hp, hi, hs, hd]
    simp
  | _ => exact ⟨rfl, rfl, rfl⟩

theorem canonList_invariants (xs : List Value) :
    intsFitList (canonList xs) = intsFitList xs ∧
      stringsFitList (canonList xs) = stringsFitList xs ∧
        depthList (canonList xs) = depthList xs := by
  cases xs with
  | nil => exact ⟨rfl, rfl, rfl⟩
  | cons v vs =>
    rcases canon_invariants v with ⟨hi, hs, hd⟩
    rcases canonList_invariants vs with ⟨hti, hts, htd⟩
    simp only [canonList, intsFitList, stringsFitList, depthList, hi, hs, hd, hti, hts, htd]
    simp

theorem canonMembers_invariants (ms : List (String × Value)) :
    intsFitMembers (canonMembers ms) = intsFitMembers ms ∧
      stringsFitMembers (canonMembers ms) = stringsFitMembers ms ∧
        depthMembers (canonMembers ms) = depthMembers ms := by
  cases ms with
  | nil => exact ⟨rfl, rfl, rfl⟩
  | cons p ms =>
    rcases p with ⟨k, v⟩
    rcases canon_invariants v with ⟨hi, hs, hd⟩
    rcases canonMembers_invariants ms with ⟨hti, hts, htd⟩
    simp only [canonMembers, intsFitMembers, stringsFitMembers, depthMembers,
      hi, hs, hd, hti, hts, htd]
    simp
end

theorem canonMembers_keys (ms : List (String × Value)) :
    (canonMembers ms).map (·.1) = ms.map (·.1) := by
  induction ms with
  | nil => rfl
  | cons p ms ih => cases p; simp [canonMembers, ih]

theorem sortedKeys_strict (ms : List (String × Value)) (hn : (ms.map (·.1)).Nodup) :
    ((ms.mergeSort (fun a b => decide (a.1 ≤ b.1))).map (·.1)).Pairwise (· < ·) := by
  have hs : (ms.mergeSort (fun a b => decide (a.1 ≤ b.1))).Pairwise
      (fun a b => a.1 ≤ b.1) := by
    suffices h : (ms.mergeSort (fun a b => decide (a.1 ≤ b.1))).Pairwise
        (fun a b => decide (a.1 ≤ b.1) = true) by simpa using h
    apply List.pairwise_mergeSort
    · intro a b c hab hbc
      simpa using Std.le_trans (of_decide_eq_true hab) (of_decide_eq_true hbc)
    · intro a b
      simpa using (Std.le_total (a := a.1) (b := b.1))
  have hkeys : ((ms.mergeSort (fun a b => decide (a.1 ≤ b.1))).map (·.1)).Pairwise
      (· ≤ ·) := by simpa only [List.pairwise_map] using hs
  have hp := (List.mergeSort_perm ms (fun a b => decide (a.1 ≤ b.1))).map (fun p => p.1)
  have hnd := hp.nodup_iff.mpr hn
  have hall := List.pairwise_and_iff.mpr (And.intro hkeys hnd)
  exact hall.imp (fun h => Std.lt_of_le_of_ne h.1 h.2)

mutual
theorem canon_keysAscend (v : Value) (hd : hasDupKey v = false) : keysAscend (canon v) = true := by
  cases v with
  | arr xs => exact canonList_keysAscend xs hd
  | obj ms =>
    have hd : (ms.map (·.1)).Nodup ∧ hasDupKeyMembers ms = false := by
      simpa [hasDupKey] using hd
    have hn : ((canonMembers ms).map (·.1)).Nodup := by
      rw [canonMembers_keys]
      exact hd.1
    have hs := sortedKeys_strict (canonMembers ms) hn
    have hc := canonMembers_keysAscend ms hd.2
    have hp := List.mergeSort_perm (canonMembers ms) (fun a b => decide (a.1 ≤ b.1))
    apply Bool.and_eq_true_iff.mpr
    refine ⟨?_, (keysAscendMembers_perm hp).trans hc⟩
    simpa only [decide_eq_true_eq] using hs
  | _ => rfl

theorem canonList_keysAscend (xs : List Value) (hd : hasDupKeyList xs = false) :
    keysAscendList (canonList xs) = true := by
  cases xs with
  | nil => rfl
  | cons v vs =>
    have hd := Bool.or_eq_false_iff.mp hd
    exact Bool.and_eq_true_iff.mpr ⟨canon_keysAscend v hd.1, canonList_keysAscend vs hd.2⟩

theorem canonMembers_keysAscend (ms : List (String × Value))
    (hd : hasDupKeyMembers ms = false) : keysAscendMembers (canonMembers ms) = true := by
  cases ms with
  | nil => rfl
  | cons p ms =>
    rcases p with ⟨k, v⟩
    have hd := Bool.or_eq_false_iff.mp hd
    exact Bool.and_eq_true_iff.mpr ⟨canon_keysAscend v hd.1, canonMembers_keysAscend ms hd.2⟩
end

mutual
theorem valueP_intsFit {cs rest : Bytes} {v : Value} (h : ValueP cs v rest) :
    intsFit v = true := by
  cases h with
  | int hi => cases hi <;> simp_all [intsFit]
  | arr _ he => exact elems_intsFit he
  | obj _ hm => exact members_intsFit hm
  | _ => rfl

theorem elems_intsFit {cs rest : Bytes} {xs : List Value} (h : Elems cs xs rest) :
    intsFitList xs = true := by
  cases h with
  | last hv _ => simp [intsFitList, valueP_intsFit hv]
  | cons hv _ _ he => exact Bool.and_eq_true_iff.mpr ⟨valueP_intsFit hv, elems_intsFit he⟩

theorem members_intsFit {cs rest : Bytes} {ms : List (String × Value)} (h : Members cs ms rest) :
    intsFitMembers ms = true := by
  cases h with
  | last _ _ _ hv _ => simp [intsFitMembers, valueP_intsFit hv]
  | cons _ _ _ hv _ _ hm => exact Bool.and_eq_true_iff.mpr ⟨valueP_intsFit hv, members_intsFit hm⟩
end

theorem text_intsFit {bs : Bytes} {v : Value} (h : Text bs v) : intsFit v = true := by
  rcases h with ⟨_, _, _, hv, _⟩
  exact valueP_intsFit hv

end FvapiProof.Json
