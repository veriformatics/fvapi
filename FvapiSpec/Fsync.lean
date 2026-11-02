import Fvapi.Sys.Fsync.Types

/-! Syscall-script denotation. The native guard linearizes an entire API operation; finalization
is one close-if-open operation in that same sequence. A trace records calls, not successful IO
alone: recovered EINTR attempts remain visible. -/

namespace FvapiSpec.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model

abbrev Trace := List Event

/-- POSIX write results acknowledge at most the requested bytes. Open returns a newly owned
file description; allocation until the one close attempt is the OS-side script assumption. -/
def Consistent (events : Trace) : Prop :=
  ∀ e ∈ events, match e.request, e.response with
    | .write _ _ count, .ok n => n ≤ count
    | _, _ => True

/-- One syscall step, including at most `budget` recovered EINTRs. A close never uses Retry. -/
inductive Retry (request : Request) : Nat → Trace → Except Cause Nat → Prop where
  | success (budget n) : Retry request budget [⟨request, .ok n⟩] (.ok n)
  | failure (budget n) (notInterrupted : n ≠ 4) :
      Retry request budget [⟨request, .error n⟩] (.error (.errno n))
  | exhausted : Retry request 0 [⟨request, .error 4⟩] (.error .retryExhausted)
  | interrupted {budget events result} (rest : Retry request budget events result) :
      Retry request (budget + 1) (⟨request, .error 4⟩ :: events) result

/-- Every positive acknowledgement advances by exactly that count. The next remaining-byte step
starts with a fresh retry budget; a zero result is terminal rather than a progress loop. -/
inductive Writes (fd : Nat) : Nat → Nat → Trace → Except Cause Unit → Prop where
  | empty (offset) : Writes fd offset 0 [] (.ok ())
  | progress {offset remaining n first rest result}
      (nonempty : 0 < remaining)
      (attempt : Retry (.write fd offset (min remaining (2 ^ 30))) 64 first (.ok n))
      (positive : 0 < n) (bounded : n ≤ min remaining (2 ^ 30))
      (tail : Writes fd (offset + n) (remaining - n) rest result) :
      Writes fd offset remaining (first ++ rest) result
  | stalled {offset remaining first}
      (nonempty : 0 < remaining)
      (attempt : Retry (.write fd offset (min remaining (2 ^ 30))) 64 first (.ok 0)) :
      Writes fd offset remaining first (.error .noProgress)
  | failed {offset remaining first cause}
      (nonempty : 0 < remaining)
      (attempt : Retry (.write fd offset (min remaining (2 ^ 30))) 64 first (.error cause)) :
      Writes fd offset remaining first (.error cause)

def error (op : Op) (path : Path) (cause : Cause) : SysError := ⟨op, cause, path, none⟩

def unitResult (op : Op) (path : Path) : Except Cause Nat → Except SysError Nat
  | .ok _ => .ok 0
  | .error cause => .error (error op path cause)

def writeResult (path : Path) : Except Cause Unit → Except SysError Nat
  | .ok _ => .ok 0
  | .error cause => .error (error .write path cause)

/-- Close is a single attempt, including EINTR. -/
def closeResult (op : Op) (path : Path) : Response → Except SysError Nat
  | .ok _ => .ok 0
  | .error n => .error (error op path (.errno n))

def directoryResult (path : Path) (primary : Except Cause Nat)
    (closed : Response) : Except SysError Nat :=
  match primary, closed with
  | .ok _, r => closeResult .closeDir path r
  | .error cause, .ok _ => .error (error .syncDir path cause)
  | .error cause, .error n =>
    .error { error .syncDir path cause with secondary? := some (.closeDir, n) }

inductive Create (path : Path) (mode : Mode) : Trace → Except SysError Nat → Prop where
  | accepted {events fd} (attempt : Retry (.create path mode) 64 events (.ok fd)) :
      Create path mode events (.ok fd)
  | failed {events cause} (attempt : Retry (.create path mode) 64 events (.error cause)) :
      Create path mode events (.error (error .create path cause))

inductive Directory (path : Path) : Trace → Except SysError Nat → Prop where
  | openFailed {events cause} (attempt : Retry (.openDir path) 64 events (.error cause)) :
      Directory path events (.error (error .openDir path cause))
  | opened {opened synced fd primary closed}
      (openAttempt : Retry (.openDir path) 64 opened (.ok fd))
      (syncAttempt : Retry (.fsync fd) 64 synced primary) :
      Directory path (opened ++ synced ++ [⟨.close fd, closed⟩])
        (directoryResult path primary closed)

def after (writer : WriterState) : WriterAction → WriterState
  | .close | .finalize => { writer with closed := true }
  | _ => writer

/-- Finalization's dummy `.ok 0` denotes no report, not successful durability IO. -/
inductive WriterOperation (writer : WriterState) : WriterAction → Trace →
    Except SysError Nat → Prop where
  | alreadyClosed (action) (closed : writer.closed = true)
      (explicit : action ≠ .finalize) :
      WriterOperation writer action [] (.error (error (match action with
        | .write _ => .write | .sync => .sync | _ => .close) writer.path .alreadyClosed))
  | finalizedClosed (closed : writer.closed = true) :
      WriterOperation writer .finalize [] (.ok 0)
  | written {size events result} (opened : writer.closed = false)
      (steps : Writes writer.fd 0 size events result) :
      WriterOperation writer (.write size) events (writeResult writer.path result)
  | synced {events result} (opened : writer.closed = false)
      (attempt : Retry (.fsync writer.fd) 64 events result) :
      WriterOperation writer .sync events (unitResult .sync writer.path result)
  | closed {response} (opened : writer.closed = false) :
      WriterOperation writer .close [⟨.close writer.fd, response⟩]
        (closeResult .close writer.path response)
  | finalized {response} (opened : writer.closed = false) :
      WriterOperation writer .finalize [⟨.close writer.fd, response⟩] (.ok 0)

inductive WriterTrace : WriterState → List WriterAction → Trace → List (Except SysError Nat) →
    Prop where
  | nil (writer) : WriterTrace writer [] [] []
  | cons {writer action actions first rest result results}
      (head : WriterOperation writer action first result)
      (tail : WriterTrace (after writer action) actions rest results) :
      WriterTrace writer (action :: actions) (first ++ rest) (result :: results)

def closeCount (events : Trace) : Nat :=
  (events.filter fun e => match e.request with | .close _ => true | _ => false).length

def successfulCount : Except Cause Nat → Nat
  | .ok n => n
  | .error _ => 0

def acknowledged (events : Trace) : Nat :=
  (events.map fun e => match e.request, e.response with
    | .write _ _ _, .ok n => n | _, _ => 0).sum

def writerOnly (fd : Nat) (events : Trace) : Prop :=
  ∀ e ∈ events, match e.request with
    | .write actual _ count => actual = fd ∧ count ≤ 2 ^ 30
    | .fsync actual | .close actual => actual = fd
    | _ => False

/-- A recovered prefix has at most 64 EINTRs; the 65th interruption terminates. -/
def RetryLimit : Prop :=
  (∀ request budget events result, Retry request budget events result →
    events.length ≤ budget + 1) ∧
  (∀ request, Retry request 64 (List.replicate 65 ⟨request, .error 4⟩)
    (.error .retryExhausted)) ∧
  ∀ request budget events result, Retry request budget events result →
    ∀ e ∈ events, e.request = request

end FvapiSpec.Fsync
