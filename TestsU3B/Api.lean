import Fvapi.Sys.Fsync
import TestsU3B.TasksCore

set_option autoImplicit false

/-! Sole F implementation import; public-name adaptation stays here (F2: `Path.ofString?`,
`Mode.ofNat?`). -/
namespace TestsU3B.Api

open Fvapi.Sys.Fsync

def errorTag (error : SysError) : String :=
  match error.cause with
  | .errno n => s!"errno:{n}"
  | .retryExhausted => "retryExhausted"
  | .noProgress => "noProgress"
  | .alreadyClosed => "alreadyClosed"

def translated {α : Type} (result : Except SysError α) : Except String α :=
  result.mapError errorTag

def create (path : String) (mode : Nat) : IO (Except String Writer) := do
  match Path.ofString? path, Mode.ofNat? mode with
  | some path, some mode => pure <| translated (← Writer.create path mode)
  | _, _ => pure <| .error "invalid path/mode"

def port : TestsU3B.Port where
  Handle := Writer
  create := create
  write := fun writer bytes => do return translated (← Writer.write writer bytes)
  sync := fun writer => do return translated (← Writer.sync writer)
  close := fun writer => do return translated (← Writer.close writer)
  pathValid := fun path => (Path.ofString? path).isSome
  modeValid := fun mode => (Mode.ofNat? mode).isSome

end TestsU3B.Api
