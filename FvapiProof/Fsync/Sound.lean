import FvapiProof.Fsync.Trace

namespace FvapiProof.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model Fvapi.Sys.Fsync.Policy
open FvapiSpec.Fsync

private theorem consistent_left {xs ys : Trace} (h : Consistent (xs ++ ys)) :
    Consistent xs := (consistent_append xs ys).mp h |>.1

private theorem consistent_right {xs ys : Trace} (h : Consistent (xs ++ ys)) :
    Consistent ys := (consistent_append xs ys).mp h |>.2

theorem writes_sound (fd offset remaining : Nat) (script : Script)
    (hc : Consistent ((writes scripted fd offset remaining).run script).events) :
    Writes fd offset remaining ((writes scripted fd offset remaining).run script).events
      ((writes scripted fd offset remaining).run script).result := by
  induction remaining using Nat.strongRecOn generalizing offset script with
  | ind remaining ih =>
    generalize hw : (writes scripted fd offset remaining).run script = run at *
    rw [writes] at hw
    by_cases hz : remaining = 0
    · subst remaining
      simp at hw
      subst run
      exact Writes.empty offset
    · simp only [hz, ite_false, run_bind] at hw
      let first :=
        (retry scripted (.write fd offset (min remaining maxWrite)) retryBudget).run script
      have hs := retry_sound (.write fd offset (min remaining maxWrite)) retryBudget script
      change Retry _ _ first.events first.result at hs
      let continuation : Except Cause Nat → ScriptIO (Except Cause Unit) := fun result =>
        match result with
        | .error cause => pure (.error cause)
        | .ok 0 => pure (.error .noProgress)
        | .ok (n + 1) => if n + 1 ≤ min remaining maxWrite then
            writes scripted fd (offset + (n + 1)) (remaining - (n + 1))
          else pure (.error (.errno 5))
      let tailScript : Script := fun n => script (n + first.consumed)
      change (let rest := (continuation first.result).run tailScript;
        { result := rest.result, events := first.events ++ rest.events,
          consumed := first.consumed + rest.consumed }) = run at hw
      dsimp only [continuation] at hw
      cases hr : first.result with
      | error cause =>
        simp only [hr, run_pure, List.append_nil, Nat.add_zero] at hw
        subst run
        exact Writes.failed (by omega) (by simpa [retryBudget, maxWrite, hr] using hs)
      | ok n =>
        cases n with
        | zero =>
          simp only [hr, run_pure, List.append_nil, Nat.add_zero] at hw
          subst run
          exact Writes.stalled (by omega) (by simpa [retryBudget, maxWrite, hr] using hs)
        | succ n =>
          by_cases hn : n + 1 ≤ min remaining maxWrite
          · simp only [hr, hn, ite_true] at hw
            subst run
            have bound : remaining - (n + 1) < remaining := by omega
            exact Writes.progress (by omega) (by simpa [retryBudget, maxWrite, hr] using hs)
              (by omega) hn (ih _ bound _ _ (consistent_right hc))
          · simp only [hr, hn, ite_false, run_pure, List.append_nil,
              Nat.add_zero] at hw
            subst run
            have hb := retry_write_bound (by simpa [hr] using hs) hc
            exact False.elim (hn hb)

theorem create_sound (path : Path) (mode : Mode) (script : Script) :
    Create path mode (scriptCreate path mode script).events
      (scriptCreate path mode script).result := by
  have hs := retry_sound (.create path mode) retryBudget script
  simp only [scriptCreate, asExecution, create, run_bind]
  generalize hr : (retry scripted (.create path mode) retryBudget).run script = run at *
  cases h : run.result with
  | ok fd =>
    simpa [h, run_pure, retryBudget] using Create.accepted (by simpa [h, retryBudget] using hs)
  | error cause =>
    simpa [h, run_pure, Policy.error, FvapiSpec.Fsync.error] using
      Create.failed (by simpa [h, retryBudget] using hs)

theorem directory_sound (path : Path) (script : Script) :
    Directory path (scriptDirectory path script).events (scriptDirectory path script).result := by
  have hs := retry_sound (.openDir path) retryBudget script
  simp only [scriptDirectory, asExecution, directory, run_bind]
  generalize hr : (retry scripted (.openDir path) retryBudget).run script = opened at *
  cases h : opened.result with
  | error cause =>
    simpa [h, run_pure, Policy.error, FvapiSpec.Fsync.error] using
      Directory.openFailed (by simpa [h, retryBudget] using hs)
  | ok fd =>
    simp only [run_bind, run_pure, run_call, List.append_nil, Nat.zero_add]
    let synced := (retry scripted (.fsync fd) retryBudget).run
      (fun n => script (n + opened.consumed))
    have hd := Directory.opened
      (closed := script (synced.consumed + opened.consumed))
      (by simpa [h, retryBudget] using hs)
      (retry_sound (.fsync fd) retryBudget (fun n => script (n + opened.consumed)))
    rw [directory_result_eq]
    simpa only [List.append_assoc, retryBudget, synced] using hd

theorem writer_sound (owned : WriterState) (action : WriterAction) (script : Script)
    (hc : Consistent (scriptWriter owned action script).events) :
    WriterOperation owned action (scriptWriter owned action script).events
      (scriptWriter owned action script).result := by
  by_cases closed : owned.closed = true
  · by_cases finalizing : action = .finalize
    · subst action
      simpa [scriptWriter, asExecution, writer, closed] using
        WriterOperation.finalizedClosed (writer := owned) closed
    · cases action with
      | write size =>
        simpa [scriptWriter, asExecution, writer, closed, actionOp, Policy.error,
          FvapiSpec.Fsync.error] using
            WriterOperation.alreadyClosed (.write size) closed (by simp)
      | sync =>
        simpa [scriptWriter, asExecution, writer, closed, actionOp, Policy.error,
          FvapiSpec.Fsync.error] using WriterOperation.alreadyClosed .sync closed (by simp)
      | close =>
        simpa [scriptWriter, asExecution, writer, closed, actionOp, Policy.error,
          FvapiSpec.Fsync.error] using WriterOperation.alreadyClosed .close closed (by simp)
      | finalize => exact False.elim (finalizing rfl)
  · have opened : owned.closed = false := Bool.eq_false_iff.mpr closed
    cases action with
    | write size =>
      simp only [scriptWriter, asExecution, writer, opened, Bool.false_eq_true, ite_false,
        run_bind, run_pure, List.append_nil, Nat.add_zero] at hc ⊢
      rw [write_result_eq]
      exact WriterOperation.written opened (writes_sound owned.fd 0 size script hc)
    | sync =>
      simp only [scriptWriter, asExecution, writer, opened, Bool.false_eq_true, ite_false,
        run_bind, run_pure, List.append_nil, Nat.add_zero]
      rw [unit_result_eq]
      exact WriterOperation.synced opened
        (by simpa [retryBudget] using retry_sound (.fsync owned.fd) retryBudget script)
    | close =>
      simpa [scriptWriter, asExecution, writer, opened, close_result_eq] using
        WriterOperation.closed (response := script 0) opened
    | finalize =>
      simpa [scriptWriter, asExecution, writer, opened] using
        WriterOperation.finalized (response := script 0) opened

end FvapiProof.Fsync
