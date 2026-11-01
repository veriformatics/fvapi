import Fvapi.Verify.Replay.Input

namespace Fvapi.Verify.Replay

structure ProcessResult where
  rc : Option Nat := none
  timedOut : Bool := false
  wallMs : Nat := 0
  stdoutPath : System.FilePath
  stderr : String := ""

def ProcessResult.ok (r : ProcessResult) : Bool := !r.timedOut && r.rc == some 0

private def seconds (ms : Nat) : String :=
  s!"{ms / 1000}.{String.ofList (List.replicate (3 - (toString (ms % 1000)).length) '0')}" ++
    s!"{ms % 1000}s"

/-- `false` = ESRCH, including a group whose last orphan has been reaped by init. -/
private def signalGroup (pid : Nat) (signal : String) : IO Bool := do
  let out ← IO.Process.output {
    cmd := "kill", args := #[signal, "--", s!"-{pid}"]
    env := #[("LC_ALL", some "C")] }
  if out.exitCode == 0 then return true
  if Read.hasPlaceholder out.stderr "No such process" then return false
  throw <| IO.userError s!"process group {pid}: {out.stderr}"

private def reapGroup (path : System.FilePath) : IO Unit := do
  let raw ← IO.FS.readFile path
  let some pid := raw.trimAscii.toString.toNat? |
    throw <| IO.userError "supervisor did not record its process group"
  unless pid > 1 do throw <| IO.userError "invalid supervisor process group"
  unless (← signalGroup pid "-KILL") do return
  -- Orphans belong to init after the leader exits; retain ownership until they disappear.
  for _ in [:200] do
    unless (← signalGroup pid "-0") do return
    IO.sleep 10
  throw <| IO.userError s!"process group {pid} was not reaped"

/-- Each invocation owns a session. Deadline handling stays in GNU timeout; after every exit,
kill the whole group and wait for its removal. Tool stderr never impersonates the supervisor. -/
def runProcess (cwd directory : System.FilePath) (label : String) (timeoutMs memoryBytes : Nat)
    (command : String) (args : Array String) : IO ProcessResult := do
  let stdoutPath := directory / (label ++ ".stdout")
  let stderrPath := directory / (label ++ ".stderr")
  let groupPath := directory / (label ++ ".pgid")
  let start ← IO.monoMsNow
  let result ← (IO.Process.output {
    cmd := "setsid"
    args := #["--wait", "bash", "-c",
      "pidfile=$1; shift; printf '%s\\n' \"$$\" >\"$pidfile\"; exec \"$@\"", "fvapi-session",
      groupPath.toString, "timeout", "--verbose", "-k", "2", seconds timeoutMs, "prlimit",
      s!"--as={memoryBytes}", "--", "bash", "-c",
      "out=$1; err=$2; shift 2; exec \"$@\" >\"$out\" 2>\"$err\"", "fvapi-replay",
      stdoutPath.toString, stderrPath.toString, command] ++ args
    cwd := some cwd
    -- Lean's default worker stacks can exhaust the profile's virtual-address cap at startup.
    env := #[("LEAN_STACK_SIZE_KB", some "65536"), ("LEAN_NUM_THREADS", some "2"),
      ("LEAN_IMPORT_WORKERS", some "1"), ("LC_ALL", some "C")] }).toBaseIO
  let cleanup ← (reapGroup groupPath).toBaseIO
  let wallMs := (← IO.monoMsNow) - start
  let stderr ← match ← (IO.FS.readFile stderrPath).toBaseIO with
    | .ok s => pure s
    | .error _ => pure ""
  let cleanupError := match cleanup with
    | .ok _ => ""
    | .error e => s!"process cleanup failed: {e}\n"
  match result with
  | .error e => return { stdoutPath, wallMs, stderr := stderr ++ cleanupError ++ s!"{e}" }
  | .ok out => return {
      stdoutPath, wallMs
      rc := if cleanupError.isEmpty then some out.exitCode.toNat else none
      timedOut := Read.hasPlaceholder out.stderr "timeout: sending signal "
      stderr := stderr ++ out.stderr ++ cleanupError }

def temporaryDirectory : IO System.FilePath := do
  let out ← IO.Process.output { cmd := "mktemp", args := #["-d", "/tmp/fvapi-replay.XXXXXXXX"] }
  unless out.exitCode == 0 do throw <| IO.userError s!"mktemp: {out.stderr}"
  return out.stdout.trimAscii.toString

def makeReadOnly (path : System.FilePath) : IO Unit := do
  let out ← IO.Process.output { cmd := "chmod", args := #["0444", path.toString] }
  unless out.exitCode == 0 do throw <| IO.userError s!"chmod: {out.stderr}"

end Fvapi.Verify.Replay
