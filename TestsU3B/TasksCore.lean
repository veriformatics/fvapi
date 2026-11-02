import Std

set_option autoImplicit false

namespace TestsU3B

structure Port where
  Handle : Type
  create : String → Nat → IO (Except String Handle)
  write : Handle → ByteArray → IO (Except String Unit)
  sync : Handle → IO (Except String Unit)
  close : Handle → IO (Except String Unit)
  pathValid : String → Bool
  modeValid : Nat → Bool

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def getOk {α : Type} (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

def taskResult (task : Task (Except IO.Error (Except String Unit))) : IO (Except String Unit) :=
  match task.get with
  | .ok result => pure result
  | .error error => throw error

def isOk {α : Type} (result : Except String α) : Bool :=
  match result with
  | .ok _ => true
  | .error _ => false

def isClosed {α : Type} (result : Except String α) : Bool :=
  match result with
  | .error "alreadyClosed" => true
  | _ => false

def waitFor (path : System.FilePath) : IO Unit := do
  for _ in [:10000] do
    if ← path.pathExists then return
    IO.sleep 1
  throw <| IO.userError s!"marker timed out: {path}"

def afterClose (port : Port) (writer : port.Handle) : IO Unit := do
  check (isClosed (← port.write writer ByteArray.empty)) "empty write after close"
  check (isClosed (← port.write writer (ByteArray.empty.push 42))) "write after close"
  check (isClosed (← port.sync writer)) "sync after close"
  check (isClosed (← port.close writer)) "repeated close"

def blocked (port : Port) (mode path control : String) : IO Unit := do
  let writer ← getOk (← port.create path 420)
  let first ← IO.asTask
    (if mode == "write" then port.write writer "bytes".toUTF8 else port.sync writer)
    (prio := .dedicated)
  waitFor (System.FilePath.mk control / "entered")
  let second ← IO.asTask (do
    IO.FS.writeFile (System.FilePath.mk control / "close-started") "started"
    let result ← port.close writer
    IO.FS.writeFile (System.FilePath.mk control / "close-done") "done"
    pure result) (prio := .dedicated)
  discard <| getOk (← taskResult first)
  discard <| getOk (← taskResult second)
  afterClose port writer

def closeRace (port : Port) (path : String) : IO Unit := do
  let writer ← getOk (← port.create path 420)
  let tasks ← (List.range 32).mapM fun _ =>
    IO.asTask (port.close writer) (prio := .dedicated)
  let results ← tasks.mapM taskResult
  check ((results.filter isOk).length == 1) "concurrent close must succeed exactly once"
  check ((results.filter isClosed).length == 31) "concurrent closes must observe closed state"
  afterClose port writer

def lifecycle (port : Port) (path : String) : IO Unit := do
  check (port.pathValid path) "NUL-free path rejected"
  check (!(port.pathValid "nul\x00path")) "NUL path accepted"
  for mode in [0, 1, 420, 511] do
    check (port.modeValid mode) s!"valid mode rejected: {mode}"
  for mode in [512, 4095, 65536] do
    check (!(port.modeValid mode)) s!"invalid mode accepted: {mode}"
  let writer ← getOk (← port.create path 420)
  discard <| getOk (← port.write writer "finalizer".toUTF8)
  discard <| getOk (← port.sync writer)
  -- No close: returning releases the last handle; the external trace checks close-if-open.

def chunk (port : Port) (path : String) : IO Unit := do
  let writer ← getOk (← port.create path 420)
  let mut bytes := ByteArray.empty.push 0
  for _ in [:30] do
    bytes := bytes ++ bytes
  bytes := bytes.push 0
  discard <| getOk (← port.write writer bytes)
  discard <| getOk (← port.close writer)
  afterClose port writer

def tasksMain (port : Port) (args : List String) : IO UInt32 := do
  let [mode, path, control] := args | return 2
  try
    match mode with
    | "write" | "sync" => blocked port mode path control
    | "close-race" => closeRace port path
    | "lifecycle" => lifecycle port path
    | "chunk" => chunk port path
    | _ => return 2
    IO.println ("{\"ok\":true,\"mode\":\"" ++ mode ++ "\"}")
    return 0
  catch error =>
    IO.eprintln s!"assertion: {error}"
    return 1

end TestsU3B
