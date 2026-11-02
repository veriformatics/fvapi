import FvapiProof.Fsync.Properties

namespace FvapiProof.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model Fvapi.Sys.Fsync.Policy
open FvapiSpec.Fsync

theorem retry_prefix_unique {request budget first₁ result₁}
    (h₁ : Retry request budget first₁ result₁) {first₂ result₂}
    (h₂ : Retry request budget first₂ result₂) (tail₁ tail₂ : Trace)
    (same : first₁ ++ tail₁ = first₂ ++ tail₂) :
    first₁ = first₂ ∧ result₁ = result₂ ∧ tail₁ = tail₂ := by
  induction h₁ generalizing first₂ result₂ tail₁ tail₂ with
  | success => cases h₂ <;> simp_all [List.cons_append, Event.mk.injEq]
  | failure => cases h₂ <;> simp_all [List.cons_append, Event.mk.injEq]
  | exhausted => cases h₂ <;> simp_all [List.cons_append, Event.mk.injEq]
  | interrupted first ih =>
    cases h₂ <;> simp_all [List.cons_append, Event.mk.injEq]
    exact ih ‹Retry _ _ _ _› tail₁ tail₂ same

theorem retry_unique {request budget events result₁ result₂}
    (h₁ : Retry request budget events result₁) (h₂ : Retry request budget events result₂) :
    result₁ = result₂ :=
  (retry_prefix_unique h₁ h₂ [] [] rfl).2.1

theorem writes_unique_eq {fd offset remaining events₁ result₁}
    (h₁ : Writes fd offset remaining events₁ result₁) {events₂ result₂}
    (h₂ : Writes fd offset remaining events₂ result₂) (same : events₁ = events₂) :
    result₁ = result₂ := by
  induction h₁ generalizing events₂ result₂ with
  | empty => cases h₂ <;> simp_all
  | progress nonempty attempt positive bounded tail ih =>
    cases h₂ with
    | empty => omega
    | progress _ attempt₂ _ _ tail₂ =>
      obtain ⟨_, result, rest⟩ := retry_prefix_unique attempt attempt₂ _ _ same
      cases result
      exact ih tail₂ rest
    | stalled _ attempt₂ =>
      have result := (retry_prefix_unique attempt attempt₂ _ [] (by simpa using same)).2.1
      cases result
      omega
    | failed _ attempt₂ =>
      have result := (retry_prefix_unique attempt attempt₂ _ [] (by simpa using same)).2.1
      cases result
  | stalled nonempty attempt =>
    cases h₂ with
    | empty => omega
    | progress _ attempt₂ positive₂ _ _ =>
      have result := (retry_prefix_unique attempt attempt₂ [] _ (by simpa using same)).2.1
      cases result
      omega
    | stalled => rfl
    | failed _ attempt₂ =>
      have result := (retry_prefix_unique attempt attempt₂ [] [] (by simpa using same)).2.1
      cases result
  | failed nonempty attempt =>
    cases h₂ with
    | empty => omega
    | progress _ attempt₂ _ _ _ =>
      have result := (retry_prefix_unique attempt attempt₂ [] _ (by simpa using same)).2.1
      cases result
    | stalled _ attempt₂ =>
      have result := (retry_prefix_unique attempt attempt₂ [] [] (by simpa using same)).2.1
      cases result
    | failed _ attempt₂ =>
      have result := (retry_prefix_unique attempt attempt₂ [] [] (by simpa using same)).2.1
      cases result
      rfl

theorem writes_unique {fd offset remaining events result₁ result₂}
    (h₁ : Writes fd offset remaining events result₁)
    (h₂ : Writes fd offset remaining events result₂) : result₁ = result₂ :=
  writes_unique_eq h₁ h₂ rfl

theorem create_unique {path mode events result₁ result₂}
    (h₁ : Create path mode events result₁) (h₂ : Create path mode events result₂) :
    result₁ = result₂ := by
  cases h₁ with
  | accepted a =>
    cases h₂ with
    | accepted b => have h := retry_unique a b; cases h; rfl
    | failed b => have h := retry_unique a b; cases h
  | failed a =>
    cases h₂ with
    | accepted b => have h := retry_unique a b; cases h
    | failed b => have h := retry_unique a b; cases h; rfl

theorem writer_unique {owned action events result₁ result₂}
    (h₁ : WriterOperation owned action events result₁)
    (h₂ : WriterOperation owned action events result₂) : result₁ = result₂ := by
  cases h₁ <;> cases h₂ <;> simp_all <;> try contradiction
  · apply congrArg (FvapiSpec.Fsync.writeResult owned.path)
    apply writes_unique <;> assumption
  · apply congrArg (FvapiSpec.Fsync.unitResult .sync owned.path)
    apply retry_unique <;> assumption

theorem directory_unique_eq {path events₁ result₁} (h₁ : Directory path events₁ result₁)
    {events₂ result₂} (h₂ : Directory path events₂ result₂) (same : events₁ = events₂) :
    result₁ = result₂ := by
  cases h₁ with
  | openFailed failed =>
    cases h₂ with
    | openFailed failed₂ =>
      have result := (retry_prefix_unique failed failed₂ [] [] (by simpa using same)).2.1
      cases result
      rfl
    | opened opened synced =>
      have result := (retry_prefix_unique failed opened [] _
        (by simpa [List.append_assoc] using same)).2.1
      cases result
  | @opened first₁ synced₁ fd₁ primary₁ closed₁ opened synced =>
    cases h₂ with
    | openFailed failed =>
      have result := (retry_prefix_unique opened failed _ []
        (by simpa [List.append_assoc] using same)).2.1
      cases result
    | @opened first₂ synced₂ fd₂ primary₂ closed₂ opened₂ synced₂h =>
      obtain ⟨_, result, rest⟩ := retry_prefix_unique opened opened₂ _ _
        (by simpa [List.append_assoc] using same)
      cases result
      obtain ⟨_, primary, closed⟩ := retry_prefix_unique synced synced₂h _ _ rest
      cases primary
      have hc : closed₁ = closed₂ := by simpa using closed
      cases hc
      rfl

theorem directory_unique {path events result₁ result₂}
    (h₁ : Directory path events result₁) (h₂ : Directory path events result₂) :
    result₁ = result₂ := directory_unique_eq h₁ h₂ rfl

end FvapiProof.Fsync
