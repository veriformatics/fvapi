import FvapiSelf.Json
import Init.Data.List.Sort.Lemmas

namespace FvapiProof.Json

open Fvapi.Json

mutual
theorem stringsFit_eq (v : Value) : stringsFit v = FvapiSpec.Json.stringsFit v := by
  cases v with
  | arr xs => exact stringsFitList_eq xs
  | obj ms => exact stringsFitMembers_eq ms
  | _ => rfl

theorem stringsFitList_eq (vs : List Value) :
    stringsFitList vs = FvapiSpec.Json.stringsFitList vs := by
  cases vs with
  | nil => rfl
  | cons v vs =>
    simp only [stringsFitList, FvapiSpec.Json.stringsFitList, stringsFit_eq v,
      stringsFitList_eq vs]

theorem stringsFitMembers_eq (ms : List (String × Value)) :
    stringsFitMembers ms = FvapiSpec.Json.stringsFitMembers ms := by
  cases ms with
  | nil => rfl
  | cons p ms =>
    rcases p with ⟨k, v⟩
    simp only [stringsFitMembers, FvapiSpec.Json.stringsFitMembers, stringsFit_eq v,
      stringsFitMembers_eq ms, maxStringBytes, FvapiSpec.Json.maxStringBytes]
    rfl
end

mutual
theorem canon_eq (v : Value) : canon v = FvapiSpec.Json.canon v := by
  cases v with
  | arr xs =>
    simp only [canon, FvapiSpec.Json.canon, canonList_eq, List.reverse_nil, List.nil_append]
  | obj ms =>
    simp only [canon, FvapiSpec.Json.canon, canonMembers_eq, List.reverse_nil, List.nil_append,
      Value.sortMembers]
  | _ => rfl

theorem canonList_eq (vs acc : List Value) :
    canonList vs acc = acc.reverse ++ FvapiSpec.Json.canonList vs := by
  cases vs with
  | nil => simp [canonList, FvapiSpec.Json.canonList]
  | cons v vs =>
    simp only [canonList, FvapiSpec.Json.canonList, canonList_eq vs, canon_eq v,
      List.reverse_cons, List.append_assoc, List.singleton_append]

theorem canonMembers_eq (ms acc : List (String × Value)) :
    canonMembers ms acc = acc.reverse ++ FvapiSpec.Json.canonMembers ms := by
  cases ms with
  | nil => simp [canonMembers, FvapiSpec.Json.canonMembers]
  | cons p ms =>
    rcases p with ⟨k, v⟩
    simp only [canonMembers, FvapiSpec.Json.canonMembers, canonMembers_eq ms, canon_eq v,
      List.reverse_cons, List.append_assoc, List.singleton_append]
end

theorem adjacentDup_false_iff (xs : List String) (hs : xs.Pairwise (· ≤ ·)) :
    adjacentDup xs = false ↔ xs.Nodup := by
  induction xs with
  | nil => simp [adjacentDup]
  | cons a xs ih =>
    cases xs with
    | nil => simp [adjacentDup]
    | cons b xs =>
      have htail := List.pairwise_cons.mp hs
      have ih := ih htail.2
      simp only [adjacentDup, Bool.or_eq_false_iff, beq_eq_false_iff_ne, ih]
      constructor
      · rintro ⟨hne, hnd⟩
        apply List.nodup_cons.mpr
        refine ⟨?_, hnd⟩
        intro hm
        rcases List.mem_cons.mp hm with he | hm
        · exact hne he
        · have hab := htail.1 b (by simp)
          have hba := (List.pairwise_cons.mp htail.2).1 a hm
          exact hne (Std.le_antisymm hab hba)
      · intro hnd
        have hn := List.nodup_cons.mp hnd
        exact ⟨fun he => hn.1 (by simp [he]), hn.2⟩

theorem adjacentDup_sort_eq (xs : List String) :
    adjacentDup (xs.mergeSort (· ≤ ·)) = !decide xs.Nodup := by
  have hs : (xs.mergeSort (· ≤ ·)).Pairwise (· ≤ ·) := by
    suffices h : (xs.mergeSort (· ≤ ·)).Pairwise (fun a b => decide (a ≤ b) = true) by
      simpa using h
    apply List.pairwise_mergeSort
    · intro a b c hab hbc
      simpa using Std.le_trans (of_decide_eq_true hab) (of_decide_eq_true hbc)
    · intro a b
      simpa using (Std.le_total (a := a) (b := b))
  have he := (adjacentDup_false_iff _ hs).trans (List.mergeSort_perm xs _).nodup_iff
  cases hd : adjacentDup (xs.mergeSort (· ≤ ·)) <;> simp_all

mutual
theorem hasDupKey_eq (v : Value) : hasDupKey v = FvapiSpec.Json.hasDupKey v := by
  cases v with
  | arr xs => exact hasDupKeyList_eq xs
  | obj ms =>
    simp only [hasDupKey, FvapiSpec.Json.hasDupKey, adjacentDup_sort_eq, hasDupKeyMembers_eq]
  | _ => rfl

theorem hasDupKeyList_eq (vs : List Value) :
    hasDupKeyList vs = FvapiSpec.Json.hasDupKeyList vs := by
  cases vs with
  | nil => rfl
  | cons v vs =>
    simp only [hasDupKeyList, FvapiSpec.Json.hasDupKeyList, hasDupKey_eq v,
      hasDupKeyList_eq vs]

theorem hasDupKeyMembers_eq (ms : List (String × Value)) :
    hasDupKeyMembers ms = FvapiSpec.Json.hasDupKeyMembers ms := by
  cases ms with
  | nil => rfl
  | cons p ms =>
    rcases p with ⟨k, v⟩
    simp only [hasDupKeyMembers, FvapiSpec.Json.hasDupKeyMembers, hasDupKey_eq v,
      hasDupKeyMembers_eq ms]
end

theorem stringsFit_eq_spec : Fvapi.Json.stringsFit = FvapiSpec.Json.stringsFit :=
  funext stringsFit_eq

theorem hasDupKey_eq_spec : Fvapi.Json.hasDupKey = FvapiSpec.Json.hasDupKey :=
  funext hasDupKey_eq

theorem canon_eq_spec : Fvapi.Json.canon = FvapiSpec.Json.canon :=
  funext canon_eq

end FvapiProof.Json
