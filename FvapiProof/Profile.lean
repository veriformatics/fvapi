import FvapiSelf.Profile

namespace FvapiProof.Profile

open Fvapi.Verify FvapiSpec.Policy

theorem mem_all (k : KernelId) : k ∈ KernelId.all := by
  cases k <;> simp [KernelId.all]

theorem independent_iff (k : KernelId) : (k.lineage != .lean) = true ↔ Independent k := by
  cases k <;> simp [KernelId.lineage, Independent]

theorem run_set_exact : FvapiSelf.Profile.RunSetExact := by
  intro s ks
  cases s
  · simp only [runSetOk, FvapiSpec.Profile.RunSetOk, Bool.and_eq_true, decide_eq_true_eq,
      List.contains_iff_mem, List.any_eq_true, independent_iff, and_assoc]
  · simp only [runSetOk, FvapiSpec.Profile.RunSetOk, Bool.and_eq_true, decide_eq_true_eq,
      List.all_eq_true]
    constructor
    · rintro ⟨h, h'⟩
      exact ⟨h, fun k => h' k (mem_all k)⟩
    · rintro ⟨h, h'⟩
      exact ⟨h, fun k _ => h' k⟩

end FvapiProof.Profile
