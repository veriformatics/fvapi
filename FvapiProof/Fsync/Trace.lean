import FvapiSelf.Fsync

namespace FvapiProof.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model Fvapi.Sys.Fsync.Policy
open FvapiSpec.Fsync

@[simp] theorem run_pure {α : Type} (a : α) (script : Script) :
    ((pure a : ScriptIO α).run script) = ⟨a, [], 0⟩ := rfl

@[simp] theorem run_bind {α β : Type} (a : ScriptIO α) (f : α → ScriptIO β)
    (script : Script) :
    ((a >>= f).run script) =
      let first := a.run script
      let rest := (f first.result).run (fun n => script (n + first.consumed))
      ⟨rest.result, first.events ++ rest.events, first.consumed + rest.consumed⟩ := rfl

@[simp] theorem run_call (request : Request) (script : Script) :
    ((scripted.call request).run script) = ⟨script 0, [⟨request, script 0⟩], 1⟩ := rfl

theorem retry_sound (request : Request) (budget : Nat) (script : Script) :
    Retry request budget ((retry scripted request budget).run script).events
      ((retry scripted request budget).run script).result := by
  induction budget generalizing script with
  | zero =>
    cases h : script 0 with
    | ok n => simpa [retry, h] using Retry.success (request := request) 0 n
    | error n =>
      by_cases hn : n = 4
      · subst n
        simpa [retry, h, eintr] using Retry.exhausted (request := request)
      · simpa [retry, h, eintr, hn] using Retry.failure (request := request) 0 n hn
  | succ budget ih =>
    cases h : script 0 with
    | ok n => simpa [retry, h] using Retry.success (request := request) (budget + 1) n
    | error n =>
      by_cases hn : n = 4
      · subst n
        simpa [retry, h, eintr] using
          Retry.interrupted (ih (fun n => script (n + 1)))
      · simpa [retry, h, eintr, hn] using Retry.failure (request := request) (budget + 1) n hn

theorem retry_length {request budget events result}
    (h : Retry request budget events result) : events.length ≤ budget + 1 := by
  induction h with
  | success => simp
  | failure => simp
  | exhausted => simp
  | interrupted _ ih => simp only [List.length_cons]; omega

theorem retry_requests {request budget events result}
    (h : Retry request budget events result) : ∀ e ∈ events, e.request = request := by
  induction h with
  | success => simp
  | failure => simp
  | exhausted => simp
  | interrupted _ ih =>
    intro e he
    rcases List.mem_cons.mp he with he | he
    · subst e; rfl
    · exact ih e he

theorem retry_exhaustion (request : Request) (budget : Nat) :
    Retry request budget (List.replicate (budget + 1) ⟨request, .error 4⟩)
      (.error .retryExhausted) := by
  induction budget with
  | zero => simpa using Retry.exhausted (request := request)
  | succ budget ih => simpa [List.replicate_succ] using Retry.interrupted ih

theorem retry_limit : RetryLimit :=
  ⟨fun _ _ _ _ h => retry_length h, fun request => retry_exhaustion request 64,
    fun _ _ _ _ h => retry_requests h⟩

theorem consistent_append (xs ys : Trace) :
    Consistent (xs ++ ys) ↔ Consistent xs ∧ Consistent ys := by
  simp only [Consistent, List.mem_append, or_imp, forall_and]

theorem retry_success_event {request budget events n}
    (h : Retry request budget events (.ok n)) : ⟨request, .ok n⟩ ∈ events := by
  generalize hr : Except.ok n = result at h
  induction h with
  | success => cases hr; simp
  | failure => cases hr
  | exhausted => cases hr
  | interrupted _ ih => exact List.mem_cons_of_mem _ (ih hr)

theorem retry_error_no_success {request budget events cause}
    (h : Retry request budget events (.error cause)) :
    ∀ e ∈ events, ∀ n, e.response ≠ .ok n := by
  generalize hr : Except.error cause = result at h
  induction h with
  | success => cases hr
  | failure => intro e he n; have he := List.mem_singleton.mp he; subst e; simp
  | exhausted => intro e he n; have he := List.mem_singleton.mp he; subst e; simp
  | interrupted _ ih =>
    intro e he n
    rcases List.mem_cons.mp he with he | he
    · subst e; simp
    · exact ih hr e he n

theorem retry_write_bound {fd offset count budget events n}
    (h : Retry (.write fd offset count) budget events (.ok n))
    (hc : Consistent events) : n ≤ count :=
  hc _ (retry_success_event h)

theorem retry_no_close {request budget events result}
    (h : Retry request budget events result)
    (hn : ∀ fd, request ≠ .close fd) : closeCount events = 0 := by
  unfold closeCount
  apply List.length_eq_zero_iff.mpr
  apply List.filter_eq_nil_iff.mpr
  intro e he
  have req := retry_requests h e he
  cases hd : e.request <;> simp_all
  exact hn _ req.symm

theorem unit_result_eq (op : Op) (path : Path) (r : Except Cause Nat) :
    Policy.unitResult op path r = FvapiSpec.Fsync.unitResult op path r := by cases r <;> rfl

theorem write_result_eq (path : Path) (r : Except Cause Unit) :
    Policy.writeResult path r = FvapiSpec.Fsync.writeResult path r := by cases r <;> rfl

theorem close_result_eq (op : Op) (path : Path) (r : Response) :
    Policy.closeResult op path r = FvapiSpec.Fsync.closeResult op path r := by cases r <;> rfl

theorem directory_result_eq (path : Path) (r : Except Cause Nat) (c : Response) :
    Policy.directoryResult path r c = FvapiSpec.Fsync.directoryResult path r c := by
  cases r <;> cases c <;> rfl

end FvapiProof.Fsync
