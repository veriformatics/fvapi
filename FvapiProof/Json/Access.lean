import FvapiSelf.Json

namespace FvapiProof.Json

open Fvapi.Json

private theorem keyLe_trans (a b c : String × Value)
    (hab : decide (a.1 ≤ b.1) = true) (hbc : decide (b.1 ≤ c.1) = true) :
    decide (a.1 ≤ c.1) = true := by
  simp only [decide_eq_true_eq] at *
  exact String.le_trans hab hbc

private theorem keyLe_total (a b : String × Value) :
    (decide (a.1 ≤ b.1) || decide (b.1 ≤ a.1)) = true := by
  simpa only [Bool.or_eq_true, decide_eq_true_eq] using String.le_total a.1 b.1

theorem object_law : FvapiSelf.Json.ObjectLaw := by
  intro ms
  refine ⟨Value.sortMembers ms, rfl, List.mergeSort_perm _ _, ?_, ?_⟩
  · exact (List.pairwise_mergeSort keyLe_trans keyLe_total ms).imp (by simp)
  · intro k
    have hs : (ms.filter (·.1 == k)).Pairwise (fun a b => decide (a.1 ≤ b.1) = true) := by
      apply List.pairwise_of_forall_mem_list
      intro a ha b hb
      have ha' : a.1 = k := by simpa using (List.mem_filter.mp ha).2
      have hb' : b.1 = k := by simpa using (List.mem_filter.mp hb).2
      simp [ha', hb']
    have hsub := List.sublist_mergeSort keyLe_trans keyLe_total hs List.filter_sublist
    have hf := hsub.filter (·.1 == k)
    simp only [List.filter_filter, Bool.and_self] at hf
    exact (hf.eq_of_length ((List.mergeSort_perm ms _).filter _).length_eq.symm).symm

theorem get_law : FvapiSelf.Json.GetLaw := by
  refine ⟨?_, ?_, ?_⟩
  · intro ms k w
    simp only [Value.get?, Option.map_eq_some_iff, List.find?_eq_some_iff_append]
    constructor
    · rintro ⟨⟨key, val⟩, ⟨hk, pre, post, hm, hn⟩, hv⟩
      have hkey : key = k := by simpa using hk
      subst key
      change val = w at hv
      subst val
      exact ⟨pre, post, hm, by simpa using hn⟩
    · rintro ⟨pre, post, hm, hn⟩
      exact ⟨(k, w), ⟨by simp, pre, post, hm, by simpa using hn⟩, rfl⟩
  · intro ms k
    simp [Value.get?]
  · intro v k h
    cases v <;> simp only [Value.get?]
    exact False.elim (h _ rfl)

theorem as_laws : FvapiSelf.Json.AsLaws := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  all_goals intro v x; cases v <;> simp [Value.asBool?, Value.asInt?, Value.asStr?,
    Value.asArr?, Value.asObj?]

end FvapiProof.Json

#print axioms FvapiProof.Json.object_law
#print axioms FvapiProof.Json.get_law
#print axioms FvapiProof.Json.as_laws
