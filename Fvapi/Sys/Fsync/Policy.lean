import Fvapi.Sys.Fsync.Types

/-! The policy is independent of IO: the native implementation and the syscall-script model
instantiate the same interface. Only the syscall interpreter + guarded ownership cross FFI. -/

namespace Fvapi.Sys.Fsync.Policy

open Model

structure Interface (m : Type → Type) where
  call : Request → m Response

def error (op : Op) (path : Path) (cause : Cause) : SysError := ⟨op, cause, path, none⟩

def unitResult (op : Op) (path : Path) : Except Cause Nat → Except SysError Nat
  | .ok _ => .ok 0
  | .error cause => .error (error op path cause)

def writeResult (path : Path) : Except Cause Unit → Except SysError Nat
  | .ok _ => .ok 0
  | .error cause => .error (error .write path cause)

def closeResult (op : Op) (path : Path) : Response → Except SysError Nat
  | .ok _ => .ok 0
  | .error n => .error (error op path (.errno n))

/-- `budget` counts retries after the initial attempt, not attempts remaining. -/
def retry {m : Type → Type} [Monad m] (sys : Interface m) (request : Request) :
    Nat → m (Except Cause Nat)
  | 0 => do
    match ← sys.call request with
    | .ok n => return .ok n
    | .error n => return .error (if n = eintr then .retryExhausted else .errno n)
  | budget + 1 => do
    match ← sys.call request with
    | .ok n => return .ok n
    | .error n =>
      if n = eintr then retry sys request budget else return .error (.errno n)

/-- The descent is the number of bytes remaining, not the syscall result's machine integer.
The upper-bound check also fails closed if a broken interpreter over-reports progress. -/
def writes {m : Type → Type} [Monad m] (sys : Interface m) (fd offset remaining : Nat) :
    m (Except Cause Unit) := do
  if remaining = 0 then return .ok ()
  let count := min remaining maxWrite
  match ← retry sys (.write fd offset count) retryBudget with
  | .error cause => return .error cause
  | .ok 0 => return .error .noProgress
  | .ok (n + 1) =>
    if h : n + 1 ≤ count then writes sys fd (offset + (n + 1)) (remaining - (n + 1))
    else return .error (.errno 5)
termination_by remaining
decreasing_by omega

def create {m : Type → Type} [Monad m] (sys : Interface m) (path : Path) (mode : Mode) :
    m (Except SysError Nat) := do
  match ← retry sys (.create path mode) retryBudget with
  | .ok fd => return .ok fd
  | .error cause => return .error (error .create path cause)

def after (writer : WriterState) : WriterAction → WriterState
  | .close | .finalize => { writer with closed := true }
  | _ => writer

def actionOp : WriterAction → Op
  | .write _ => .write
  | .sync => .sync
  | .close | .finalize => .close

def writer {m : Type → Type} [Monad m] (sys : Interface m) (owned : WriterState)
    (action : WriterAction) : m (Except SysError Nat) :=
  if owned.closed then
    if action = .finalize then pure (.ok 0)
    else pure (.error (error (actionOp action) owned.path .alreadyClosed))
  else match action with
    | .write size => do return writeResult owned.path (← writes sys owned.fd 0 size)
    | .sync => do return unitResult .sync owned.path (← retry sys (.fsync owned.fd) retryBudget)
    | .close => do return closeResult .close owned.path (← sys.call (.close owned.fd))
    | .finalize => do
      let _ ← sys.call (.close owned.fd)
      return .ok 0

def directoryResult (path : Path) (primary : Except Cause Nat)
    (closed : Response) : Except SysError Nat :=
  match primary, closed with
  | .ok _, r => closeResult .closeDir path r
  | .error cause, .ok _ => .error (error .syncDir path cause)
  | .error cause, .error n =>
    .error { error .syncDir path cause with secondary? := some (.closeDir, n) }

def directory {m : Type → Type} [Monad m] (sys : Interface m) (path : Path) :
    m (Except SysError Nat) := do
  match ← retry sys (.openDir path) retryBudget with
  | .error cause => return .error (error .openDir path cause)
  | .ok fd =>
    let primary ← retry sys (.fsync fd) retryBudget
    let closed ← sys.call (.close fd)
    return directoryResult path primary closed

def actions {m : Type → Type} [Monad m] (sys : Interface m) (owned : WriterState) :
    List WriterAction → m (List (Except SysError Nat))
  | [] => pure []
  | action :: rest => do
    let result ← writer sys owned action
    let results ← actions sys (after owned action) rest
    return result :: results

/-! ## Script interpretation of that same policy -/

abbrev Script := Nat → Response

structure Recorded (α : Type) where
  result : α
  events : List Event := []
  consumed : Nat := 0

structure ScriptIO (α : Type) where
  run : Script → Recorded α

namespace ScriptIO

variable {α β : Type}

def pure (a : α) : ScriptIO α := ⟨fun _ => ⟨a, [], 0⟩⟩

def bind (a : ScriptIO α) (f : α → ScriptIO β) : ScriptIO β := ⟨fun script =>
  let first := a.run script
  let rest := (f first.result).run (fun n => script (n + first.consumed))
  ⟨rest.result, first.events ++ rest.events, first.consumed + rest.consumed⟩⟩

instance : Monad ScriptIO where
  pure := pure
  bind := bind

end ScriptIO

def scripted : Interface ScriptIO := ⟨fun request => ⟨fun script =>
  ⟨script 0, [⟨request, script 0⟩], 1⟩⟩⟩

def asExecution (record : Recorded (Except SysError Nat)) : Execution :=
  ⟨record.result, record.events, record.consumed⟩

def scriptCreate (path : Path) (mode : Mode) (script : Script) : Execution :=
  asExecution ((create scripted path mode).run script)

def scriptWriter (owned : WriterState) (action : WriterAction) (script : Script) : Execution :=
  asExecution ((writer scripted owned action).run script)

def scriptDirectory (path : Path) (script : Script) : Execution :=
  asExecution ((directory scripted path).run script)

def scriptActions (owned : WriterState) (as : List WriterAction) (script : Script) :
    Recorded (List (Except SysError Nat)) := (actions scripted owned as).run script

end Fvapi.Sys.Fsync.Policy
