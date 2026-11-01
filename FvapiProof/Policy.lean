import FvapiSelf.Policy

namespace FvapiProof.Policy

open Fvapi.Verify FvapiSpec.Policy

theorem accepted_iff (r : KernelResult) : accepted r = true ↔ r.status = .accept := by
  simp [accepted]

theorem independent_iff (k : KernelId) : k.lineage ≠ .lean ↔ Independent k := by
  cases k <;> simp [KernelId.lineage, Independent]

theorem admissible_iff (s : KernelStatus) :
    s.admissible = true ↔ (s ≠ .reject ∧ s ≠ .crash ∧ s ≠ .timeout ∧
      ∀ feature, s = .decline feature → feature.trimAscii.isEmpty = false) := by
  cases s <;> simp [KernelStatus.admissible]

theorem ite_pass (b : Bool) :
    (if b = true then Verdict.pass else Verdict.fail) = .pass ↔ b = true := by
  cases b <;> simp

theorem policy_exact : FvapiSelf.Policy.PolicyExact := by
  intro rs
  rw [verdict, ite_pass]
  simp only [Bool.and_eq_true, List.any_eq_true, List.all_eq_true, accepted_iff, beq_iff_eq,
    bne_iff_ne, ne_eq, independent_iff, admissible_iff, Pass]
  constructor
  · rintro ⟨⟨h1, h2⟩, h3⟩
    exact ⟨h1, h2, h3⟩
  · rintro ⟨h1, h2, h3⟩
    exact ⟨⟨h1, h2⟩, h3⟩

theorem accepting_exact : FvapiSelf.Policy.AcceptingExact := by
  intro order rs k
  simp [accepting, List.mem_filter, List.mem_eraseDups, List.any_eq_true, accepted_iff]

end FvapiProof.Policy
