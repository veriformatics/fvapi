import FvapiProof.Fsync.Sound

namespace FvapiProof.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model Fvapi.Sys.Fsync.Policy
open FvapiSpec.Fsync

@[simp] theorem close_count_nil : closeCount [] = 0 := rfl

@[simp] theorem close_count_append (xs ys : Trace) :
    closeCount (xs ++ ys) = closeCount xs + closeCount ys := by
  simp [closeCount, List.filter_append]

@[simp] theorem acknowledged_append (xs ys : Trace) :
    acknowledged (xs ++ ys) = acknowledged xs + acknowledged ys := by
  simp [acknowledged, List.map_append, List.sum_append]

theorem retry_acknowledged {fd offset count budget events result}
    (h : Retry (.write fd offset count) budget events result) :
    acknowledged events = successfulCount result := by
  induction h with
  | success => simp [acknowledged, successfulCount]
  | failure => simp [acknowledged, successfulCount]
  | exhausted => simp [acknowledged, successfulCount]
  | interrupted _ ih => simpa [acknowledged] using ih

theorem writes_acknowledged {fd offset remaining events}
    (h : Writes fd offset remaining events (.ok ())) : acknowledged events = remaining := by
  generalize hr : Except.ok () = result at h
  induction h with
  | empty => simp [acknowledged]
  | progress nonempty attempt positive bounded tail ih =>
    have ht := ih hr
    rw [acknowledged_append, retry_acknowledged attempt, ht]
    simp only [successfulCount]
    have hn : _ ≤ _ := Nat.le_trans bounded (Nat.min_le_left _ _)
    omega
  | stalled => cases hr
  | failed => cases hr

theorem operation_write_acknowledged {owned size events result n}
    (h : WriterOperation owned (.write size) events result) (ok : result = .ok n) :
    acknowledged events = size := by
  cases h with
  | alreadyClosed => cases ok
  | @written size events outcome opened steps =>
    cases outcome with
    | ok value => cases value; exact writes_acknowledged steps
    | error cause => cases ok

theorem writes_no_close {fd offset remaining events result}
    (h : Writes fd offset remaining events result) : closeCount events = 0 := by
  induction h with
  | empty => rfl
  | progress _ attempt _ _ _ ih =>
    rw [close_count_append, retry_no_close attempt (by intro; simp), ih]
  | stalled _ attempt => exact retry_no_close attempt (by intro; simp)
  | failed _ attempt => exact retry_no_close attempt (by intro; simp)

theorem writes_owned {fd offset remaining events result}
    (h : Writes fd offset remaining events result) : writerOnly fd events := by
  induction h with
  | empty => simp [writerOnly]
  | progress _ attempt _ _ _ ih =>
    intro e he
    rcases List.mem_append.mp he with he | he
    · rw [show e.request = .write fd _ _ from retry_requests attempt e he]
      exact ⟨rfl, Nat.min_le_right _ _⟩
    · exact ih e he
  | stalled _ attempt =>
    intro e he
    rw [show e.request = .write fd _ _ from retry_requests attempt e he]
    exact ⟨rfl, Nat.min_le_right _ _⟩
  | failed _ attempt =>
    intro e he
    rw [show e.request = .write fd _ _ from retry_requests attempt e he]
    exact ⟨rfl, Nat.min_le_right _ _⟩

theorem operation_closed_empty {owned action events result}
    (h : WriterOperation owned action events result) (closed : owned.closed = true) :
    events = [] := by
  cases h <;> simp_all

theorem operation_owned {owned action events result}
    (h : WriterOperation owned action events result) : writerOnly owned.fd events := by
  cases h with
  | alreadyClosed => simp [writerOnly]
  | finalizedClosed => simp [writerOnly]
  | written _ steps => exact writes_owned steps
  | synced _ attempt =>
    intro e he
    rw [show e.request = .fsync owned.fd from retry_requests attempt e he]
  | closed => simp [writerOnly]
  | finalized => simp [writerOnly]

theorem operation_close_count {owned action events result}
    (h : WriterOperation owned action events result) :
    closeCount events ≤ if owned.closed then 0 else 1 := by
  cases h with
  | alreadyClosed => simp
  | finalizedClosed => simp
  | written opened steps => simp [writes_no_close steps]
  | synced opened attempt => simp [retry_no_close attempt (by intro; simp)]
  | closed opened => simp [closeCount, opened]
  | finalized opened => simp [closeCount, opened]

theorem operation_count_when_not_closing {owned action events result}
    (h : WriterOperation owned action events result)
    (hc : action ≠ .close) (hf : action ≠ .finalize) : closeCount events = 0 := by
  cases h with
  | alreadyClosed => rfl
  | finalizedClosed => contradiction
  | written _ steps => exact writes_no_close steps
  | synced _ attempt => exact retry_no_close attempt (by intro; simp)
  | closed => contradiction
  | finalized => contradiction

theorem writer_trace_close_count {owned actions events results}
    (h : WriterTrace owned actions events results) :
    closeCount events ≤ if owned.closed then 0 else 1 := by
  induction h with
  | nil => simp
  | @cons owned action actions first rest result results head tail ih =>
    rw [close_count_append]
    cases action with
    | close =>
      have hr : closeCount rest = 0 := by
        simpa [FvapiSpec.Fsync.after] using ih
      simpa [hr] using operation_close_count head
    | finalize =>
      have hr : closeCount rest = 0 := by
        simpa [FvapiSpec.Fsync.after] using ih
      simpa [hr] using operation_close_count head
    | write size =>
      rw [operation_count_when_not_closing head (by simp) (by simp), Nat.zero_add]
      exact ih
    | sync =>
      rw [operation_count_when_not_closing head (by simp) (by simp), Nat.zero_add]
      exact ih

theorem actions_sound (owned : WriterState) (as : List WriterAction) (script : Script)
    (hc : Consistent (scriptActions owned as script).events) :
    WriterTrace owned as (scriptActions owned as script).events
      (scriptActions owned as script).result := by
  induction as generalizing owned script with
  | nil => exact WriterTrace.nil owned
  | cons action rest ih =>
    simp only [scriptActions, actions, run_bind, run_pure, List.append_nil, Nat.add_zero] at hc ⊢
    have first := writer_sound owned action script ((consistent_append _ _).mp hc).1
    have tail := ih (Policy.after owned action)
      (fun n => script (n + ((writer scripted owned action).run script).consumed))
      ((consistent_append _ _).mp hc).2
    exact WriterTrace.cons first tail

theorem directory_close_count {path events result} (h : Directory path events result) :
    closeCount events ≤ 1 := by
  cases h with
  | openFailed attempt => simp [retry_no_close attempt (by intro; simp)]
  | opened opened synced =>
    rw [close_count_append, close_count_append, retry_no_close opened (by intro; simp),
      retry_no_close synced (by intro; simp)]
    simp [closeCount]

theorem directory_opened_close {path events result} (h : Directory path events result)
    (ho : ∃ e ∈ events, ∃ fd, e.request = .openDir path ∧ e.response = .ok fd) :
    closeCount events = 1 := by
  cases h with
  | openFailed attempt =>
    obtain ⟨e, he, fd, req, response⟩ := ho
    exact False.elim (retry_error_no_success attempt e he fd response)
  | opened opened synced =>
    rw [close_count_append, close_count_append, retry_no_close opened (by intro; simp),
      retry_no_close synced (by intro; simp)]
    simp [closeCount]

end FvapiProof.Fsync
