import Fvapi.Sys.Fsync.Policy
import FvapiSpec.Fsync

namespace FvapiSelf.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model FvapiSpec.Fsync

/-- Every reported API success, and only a completed reporting operation, is success. Finalizers
have no report. Recovered EINTRs remain visible; a successful write acknowledges its byte count. -/
def NoFalseSuccess : Prop :=
  (∀ path mode script n, let run := Policy.scriptCreate path mode script
    Consistent run.events → (run.result = .ok n ↔ Create path mode run.events (.ok n))) ∧
  (∀ writer action script n, let run := Policy.scriptWriter writer action script
    Consistent run.events → action ≠ .finalize →
      (run.result = .ok n ↔ WriterOperation writer action run.events (.ok n))) ∧
  (∀ path script n, let run := Policy.scriptDirectory path script
    Consistent run.events → (run.result = .ok n ↔ Directory path run.events (.ok n))) ∧
  ∀ writer size script n, let run := Policy.scriptWriter writer (.write size) script
    Consistent run.events → run.result = .ok n → acknowledged run.events = size

/-- The explicit-call + finalizer sequence attempts close at most once. A directory description
that open returned gets exactly one close attempt, regardless of the sync result. -/
def CloseOnce : Prop :=
  (∀ writer actions script,
    Consistent (Policy.scriptActions writer actions script).events →
    closeCount (Policy.scriptActions writer actions script).events ≤
      if writer.closed then 0 else 1) ∧
  ∀ path script, let run := Policy.scriptDirectory path script
    closeCount run.events ≤ 1 ∧
    ((∃ e ∈ run.events, ∃ fd, e.request = .openDir path ∧ e.response = .ok fd) →
      closeCount run.events = 1)

/-- The implementation's traces obey the independently specified bounded retry grammar. Each
positive write acknowledgement starts another full-budget step, not a shared operation budget. -/
def RetryBounded : Prop :=
  (∀ path mode script, let run := Policy.scriptCreate path mode script
    Consistent run.events → Create path mode run.events run.result) ∧
  (∀ writer action script, let run := Policy.scriptWriter writer action script
    Consistent run.events → WriterOperation writer action run.events run.result) ∧
  (∀ path script, let run := Policy.scriptDirectory path script
    Consistent run.events → Directory path run.events run.result) ∧ RetryLimit

/-- Writer IO uses only the create-owned description, within the per-call chunk cap. Once the
close transition occurs, every subsequent call (including finalization) issues no syscall. -/
def SameDescription : Prop :=
  ∀ writer action script, let run := Policy.scriptWriter writer action script
    Consistent run.events →
    writerOnly writer.fd run.events ∧ (writer.closed = true → run.events = [])

/-- The first terminal event, not a recovered EINTR, supplies the primary error. Directory close
failure is primary only after successful sync, and otherwise is the secondary error. -/
def ErrorExact : Prop :=
  (∀ path mode script e, let run := Policy.scriptCreate path mode script
    Consistent run.events → (run.result = .error e ↔
      Create path mode run.events (.error e))) ∧
  (∀ writer action script e, let run := Policy.scriptWriter writer action script
    Consistent run.events → action ≠ .finalize → (run.result = .error e ↔
      WriterOperation writer action run.events (.error e))) ∧
  ∀ path script e, let run := Policy.scriptDirectory path script
    Consistent run.events → (run.result = .error e ↔ Directory path run.events (.error e))

end FvapiSelf.Fsync
