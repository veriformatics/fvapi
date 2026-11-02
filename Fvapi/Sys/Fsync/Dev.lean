import Fvapi.Sys.Fsync
import Fvapi.Json

namespace Fvapi.Sys.Fsync.Dev

open Fvapi.Json

inductive Command where
  | create (path : Path) (mode : Mode)
  | write (size : Nat)
  | sync | close | drop
  | syncDir (path : Path)

def usage : String :=
  "usage: fvapi dev fsync run OP…\n" ++
  "ops: create PATH [MODE], write N, sync, close, drop, syncdir PATH\n"

private def operation (s : String) : Bool :=
  ["create", "write", "sync", "close", "drop", "syncdir"].contains s

private def mode? (s : String) : Option Mode := do
  let chars := s.toList
  unless 1 ≤ chars.length && chars.length ≤ 3 && chars.all (fun c => '0' ≤ c && c ≤ '7') do
    none
  Mode.ofNat? (chars.foldl (fun n c => n * 8 + (c.toNat - '0'.toNat)) 0)

private def count? (s : String) : Option Nat := do
  unless !s.isEmpty && s.toList.all (fun c => '0' ≤ c && c ≤ '9') do none
  s.toNat?

private def parse : List String → Option (List Command)
  | [] => some []
  | "create" :: path :: rest => do
    let path ← Path.ofString? path
    match rest with
    | mode :: more =>
      if operation mode then return .create path Mode.default :: (← parse (mode :: more))
      else return .create path (← mode? mode) :: (← parse more)
    | [] => return [.create path Mode.default]
  | "write" :: size :: rest => do return .write (← count? size) :: (← parse rest)
  | "sync" :: rest => do return .sync :: (← parse rest)
  | "close" :: rest => do return .close :: (← parse rest)
  | "drop" :: rest => do return .drop :: (← parse rest)
  | "syncdir" :: path :: rest => do return .syncDir (← Path.ofString? path) :: (← parse rest)
  | _ => none

private def opName : Op → String
  | .create => "create" | .write => "write" | .sync => "sync" | .close => "close"
  | .openDir => "openDir" | .syncDir => "syncDir" | .closeDir => "closeDir"

private def errorJson (e : SysError) : Value :=
  let fields := [("op", .str (opName e.op)), ("cause", .str (match e.cause with
    | .errno _ => "errno" | .retryExhausted => "retryExhausted"
    | .noProgress => "noProgress" | .alreadyClosed => "alreadyClosed"))]
  let fields := match e.cause with
    | .errno n => fields ++ [("errno", .int n)] | _ => fields
  let fields := match e.secondary? with
    | none => fields
    | some (op, n) => fields ++ [("secondary", .object
        [("op", .str (opName op)), ("errno", .int n)])]
  .object fields

private def report (op : String) (result : Except SysError Unit) : IO Unit := do
  let record := match result with
    | .ok _ => Value.object [("op", .str op), ("ok", .bool true)]
    | .error e => .object [("op", .str op), ("ok", .bool false), ("error", errorJson e)]
  IO.println (String.fromUTF8! (print record))

private def readExactly (count : Nat) : IO (Option ByteArray) := do
  let stdin ← IO.getStdin
  let mut bytes := ByteArray.empty
  while bytes.size < count do
    let part ← stdin.read (min (count - bytes.size) 65536).toUSize
    if part.isEmpty then return none
    bytes := bytes ++ part
  return some bytes

def run (args : List String) : IO UInt32 := do
  let some commands := parse args | IO.eprint usage; return 2
  if commands.isEmpty then IO.eprint usage; return 2
  let slot ← IO.mkRef (none : Option Writer)
  for command in commands do
    match command with
    | .create path mode =>
      if (← slot.get).isSome then IO.eprint usage; return 2
      match ← Writer.create path mode with
      | .error e => report "create" (.error e)
      | .ok writer => slot.set (some writer); report "create" (.ok ())
    | .write size =>
      let some writer ← slot.get | IO.eprint usage; return 2
      let some bytes ← readExactly size | IO.eprint usage; return 2
      report "write" (← writer.write bytes)
    | .sync =>
      let some writer ← slot.get | IO.eprint usage; return 2
      report "sync" (← writer.sync)
    | .close =>
      let some writer ← slot.get | IO.eprint usage; return 2
      report "close" (← writer.close)
    | .drop =>
      unless (← slot.get).isSome do IO.eprint usage; return 2
      slot.set none
      report "drop" (.ok ())
    | .syncDir path => report "syncdir" (← syncDir path)
  return 0

end Fvapi.Sys.Fsync.Dev
