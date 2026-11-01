import TestsU3.Boundary

namespace TestsU3

def check (ok : Bool) (label : String) : IO Unit :=
  unless ok do throw (IO.userError s!"assertion: {label}")

def independentHex (bs : ByteArray) : String :=
  String.ofList (bs.data.toList.flatMap fun b =>
    let digits := "0123456789abcdef".toList.toArray
    [digits[b.toNat / 16]!, digits[b.toNat % 16]!])

def unhex (s : String) : Except String ByteArray := do
  let mut high : Option Nat := none
  let mut out := ByteArray.empty
  for c in s.toList do
    let n := c.toNat
    let d ← if 48 ≤ n && n ≤ 57 then pure (n - 48)
      else if 97 ≤ n && n ≤ 102 then pure (n - 87)
      else throw s!"bad hex {repr c}"
    match high with
    | none => high := some d
    | some h => out := out.push (UInt8.ofNat (h * 16 + d)); high := none
  if high.isSome then throw "odd hex length"
  return out

def unhexIO (s : String) : IO ByteArray :=
  match unhex s with
  | .ok b => pure b
  | .error e => throw (IO.userError s!"setup: {e}")

def outcomeText : Outcome → String
  | .error .malformed => "malformed"
  | .error .tooLarge => "tooLarge"
  | .error .duplicateKey => "duplicateKey"
  | .ok v => "ok:" ++ independentHex (Oracle.text v).toUTF8

def loadRows (path : System.FilePath) : IO (List (List String)) := do
  unless ← path.pathExists do throw (IO.userError s!"setup: missing {path}")
  let text ← IO.FS.readFile path
  return (text.splitOn "\n").filterMap fun line =>
    if line.isEmpty then none else some (line.splitOn "\t")

/-- Simple LCG: fixed arithmetic independent of implementation randomness. -/
def next (s : UInt64) : UInt64 := s * 6364136223846793005 + 1442695040888963407

def bytes (seed : UInt64) (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  let mut s := seed
  for _ in [:n] do
    s := next s
    out := out.push (UInt8.ofNat (s.toNat / 0x100000000 % 256))
  return out

private def alphabet : Array String := #["", "a", "A", "a\x00b", "é", "é", "𝄞", " ", " ",
  "\x7f", "\x08\x0c\n\r\t", "\\\"/", "", "𐀀", "﻿", "﷐", "￿"]

partial def generated (seed : UInt64) (depth : Nat := 4) : Value :=
  let s := next seed
  let n := s.toNat
  match n % (if depth == 0 then 4 else 6) with
  | 0 => .null
  | 1 => .bool (n % 2 == 0)
  | 2 => .int (if n % 2 == 0 then Int.ofNat (n % 9007199254740992)
      else -(Int.ofNat (n % 9007199254740992)))
  | 3 => .str alphabet[n / 8 % alphabet.size]!
  | 4 => .arr ((List.range (n / 8 % 5)).map fun i => generated (s + i.toUInt64 + 1) (depth - 1))
  | _ => .obj (Oracle.sortMembers ((List.range (n / 8 % 5)).map fun i =>
      (s!"k{i}" ++ alphabet[(n + i) % alphabet.size]!,
        generated (s + i.toUInt64 + 1) (depth - 1))))

end TestsU3
