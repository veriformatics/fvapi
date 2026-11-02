import FvapiProof.Fsync.Exact

namespace FvapiProof.Fsync

open Fvapi.Sys.Fsync Fvapi.Sys.Fsync.Model Fvapi.Sys.Fsync.Policy
open FvapiSpec.Fsync

theorem create_exact (path : Path) (mode : Mode) (script : Script) (r : Except SysError Nat) :
    (scriptCreate path mode script).result = r ↔
      Create path mode (scriptCreate path mode script).events r := by
  constructor
  · intro h; rw [← h]; exact create_sound path mode script
  · exact create_unique (create_sound path mode script)

theorem writer_exact (owned : WriterState) (action : WriterAction) (script : Script)
    (hc : Consistent (scriptWriter owned action script).events) (r : Except SysError Nat) :
    (scriptWriter owned action script).result = r ↔
      WriterOperation owned action (scriptWriter owned action script).events r := by
  constructor
  · intro h; rw [← h]; exact writer_sound owned action script hc
  · exact writer_unique (writer_sound owned action script hc)

theorem directory_exact (path : Path) (script : Script) (r : Except SysError Nat) :
    (scriptDirectory path script).result = r ↔
      Directory path (scriptDirectory path script).events r := by
  constructor
  · intro h; rw [← h]; exact directory_sound path script
  · exact directory_unique (directory_sound path script)

theorem no_false_success : FvapiSelf.Fsync.NoFalseSuccess := by
  dsimp only [FvapiSelf.Fsync.NoFalseSuccess]
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro path mode script n _
    exact create_exact path mode script (.ok n)
  · intro owned action script n hc _
    exact writer_exact owned action script hc (.ok n)
  · intro path script n _
    exact directory_exact path script (.ok n)
  · intro owned size script n hc ok
    exact operation_write_acknowledged (writer_sound owned (.write size) script hc) ok

theorem close_once : FvapiSelf.Fsync.CloseOnce := by
  dsimp only [FvapiSelf.Fsync.CloseOnce]
  constructor
  · intro owned actions script hc
    exact writer_trace_close_count (actions_sound owned actions script hc)
  · intro path script
    exact ⟨directory_close_count (directory_sound path script),
      directory_opened_close (directory_sound path script)⟩

theorem retry_bounded : FvapiSelf.Fsync.RetryBounded := by
  dsimp only [FvapiSelf.Fsync.RetryBounded]
  refine ⟨?_, ?_, ?_, retry_limit⟩
  · intro path mode script _; exact create_sound path mode script
  · intro owned action script hc; exact writer_sound owned action script hc
  · intro path script _; exact directory_sound path script

theorem same_description : FvapiSelf.Fsync.SameDescription := by
  dsimp only [FvapiSelf.Fsync.SameDescription]
  intro owned action script hc
  have h := writer_sound owned action script hc
  exact ⟨operation_owned h, operation_closed_empty h⟩

theorem error_exact : FvapiSelf.Fsync.ErrorExact := by
  dsimp only [FvapiSelf.Fsync.ErrorExact]
  refine ⟨?_, ?_, ?_⟩
  · intro path mode script e _
    exact create_exact path mode script (.error e)
  · intro owned action script e hc _
    exact writer_exact owned action script hc (.error e)
  · intro path script e _
    exact directory_exact path script (.error e)

#print axioms no_false_success
#print axioms close_once
#print axioms retry_bounded
#print axioms same_description
#print axioms error_exact

end FvapiProof.Fsync
