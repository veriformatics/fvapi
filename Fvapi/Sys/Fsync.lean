import Fvapi.Sys.Fsync.Policy

namespace Fvapi.Sys.Fsync

open Model

private opaque NativeImpl : NonemptyType.{0}
private abbrev Native := NativeImpl.type

@[extern "fvapi_fsync_open_file"]
private opaque openFile (path : @& String) (mode : UInt32) : IO Response

@[extern "fvapi_fsync_open_dir"]
private opaque openDir (path : @& String) : IO Response

@[extern "fvapi_fsync_write"]
private opaque writeRaw (fd : UInt32) (bytes : @& ByteArray) (offset count : USize) : IO Response

@[extern "fvapi_fsync_sync"]
private opaque syncRaw (fd : UInt32) : IO Response

@[extern "fvapi_fsync_close"]
private opaque closeRaw (fd : UInt32) : IO Response

@[extern "fvapi_fsync_writer_new"]
private opaque newNative (fd : UInt32) (path : @& String) : IO Native

@[extern "fvapi_fsync_writer_acquire"]
private opaque acquire (writer : @& Native) : IO (Nat × Bool)

@[extern "fvapi_fsync_writer_mark_closed"]
private opaque markClosed (writer : @& Native) : IO Unit

@[extern "fvapi_fsync_writer_release"]
private opaque release (writer : @& Native) : IO Unit

/-- One create-owned description. The private native reference carries the guard + close flag;
copying a Writer shares that ownership, not another descriptor. -/
structure Writer where private mk ::
  private native : Native
  path : Path

private def syscalls (bytes : ByteArray := ByteArray.empty) (owned : Option Native := none) :
    Policy.Interface IO := ⟨fun request => do
  match request with
  | .create path mode => openFile path.toString mode.toNat.toUInt32
  | .openDir path => openDir path.toString
  | .write fd offset count => writeRaw fd.toUInt32 bytes offset.toUSize count.toUSize
  | .fsync fd => syncRaw fd.toUInt32
  | .close fd =>
    if let some native := owned then markClosed native
    closeRaw fd.toUInt32⟩

namespace Writer

def create (path : Path) (mode : Mode := Mode.default) : IO (Except SysError Writer) := do
  match ← Policy.create (syscalls ByteArray.empty) path mode with
  | .error e => return .error e
  | .ok fd => return .ok ⟨← newNative fd.toUInt32 path.toString, path⟩

private def run (writer : Writer) (action : WriterAction) (bytes : ByteArray := ByteArray.empty) :
    IO (Except SysError Unit) := do
  let (fd, closed) ← acquire writer.native
  try
    let result ← Policy.writer (syscalls bytes (some writer.native))
      ⟨writer.path, fd, closed⟩ action
    return result.map (fun _ => ())
  finally
    release writer.native

def write (writer : Writer) (bytes : ByteArray) : IO (Except SysError Unit) :=
  run writer (.write bytes.size) bytes

def sync (writer : Writer) : IO (Except SysError Unit) := run writer .sync

/-- Closed before its single close attempt, including when close returns EINTR. -/
def close (writer : Writer) : IO (Except SysError Unit) := run writer .close

end Writer

def write (writer : Writer) (bytes : ByteArray) : IO (Except SysError Unit) := writer.write bytes

def sync (writer : Writer) : IO (Except SysError Unit) := writer.sync

def close (writer : Writer) : IO (Except SysError Unit) := writer.close

def syncDir (path : Path) : IO (Except SysError Unit) := do
  return (← Policy.directory (syscalls ByteArray.empty) path).map (fun _ => ())

end Fvapi.Sys.Fsync
