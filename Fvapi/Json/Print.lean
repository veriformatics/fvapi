import Fvapi.Json.Value

/-! Canonical text (`docs/contracts/U3-codecs.md` J4 = jq `-S -c` without its final LF on valid
values), proven equal to `FvapiSpec.Json.canonical` (`FvapiProof/Json.lean`). -/

namespace Fvapi.Json

/-- Lowercase hex digit of `n < 16`. -/
def hexByte (n : Nat) : UInt8 := if n < 10 then (0x30 + n).toUInt8 else (0x57 + n).toUInt8

/-- One scalar inside a string literal: the seven short escapes, `\u00xx` for the other C0
controls + DEL, every other scalar as its UTF-8 bytes. -/
def pushChar (out : ByteArray) (c : Char) : ByteArray :=
  if c = '"' then (out.push 0x5C).push 0x22
  else if c = '\\' then (out.push 0x5C).push 0x5C
  else if c.val = 0x08 then (out.push 0x5C).push 0x62
  else if c.val = 0x0C then (out.push 0x5C).push 0x66
  else if c = '\n' then (out.push 0x5C).push 0x6E
  else if c = '\r' then (out.push 0x5C).push 0x72
  else if c = '\t' then (out.push 0x5C).push 0x74
  else if c.val < 0x20 ∨ c.val = 0x7F then
    out.push 0x5C |>.push 0x75 |>.push 0x30 |>.push 0x30 |>.push (hexByte (c.toNat / 16))
      |>.push (hexByte (c.toNat % 16))
  else (String.utf8EncodeChar c).foldl ByteArray.push out

def pushStr (out : ByteArray) (s : String) : ByteArray :=
  (s.foldl pushChar (out.push 0x22)).push 0x22

/-- Shortest decimal, `-` only when negative. -/
def pushInt (out : ByteArray) (n : Int) : ByteArray :=
  let out := if n < 0 then out.push 0x2D else out
  (Nat.toDigits 10 n.natAbs).foldl (fun o c => o.push c.toNat.toUInt8) out

mutual
/-- Appends the canonical text of `v`: no whitespace, members in stored order. Siblings loop
(self tail calls); only nesting recurses. -/
def printTo (out : ByteArray) : Value → ByteArray
  | .null => out.push 0x6E |>.push 0x75 |>.push 0x6C |>.push 0x6C
  | .bool true => out.push 0x74 |>.push 0x72 |>.push 0x75 |>.push 0x65
  | .bool false => out.push 0x66 |>.push 0x61 |>.push 0x6C |>.push 0x73 |>.push 0x65
  | .int n => pushInt out n
  | .str s => pushStr out s
  | .arr xs => (printList (out.push 0x5B) xs).push 0x5D
  | .obj ms => (printMembers (out.push 0x7B) ms).push 0x7D
def printList (out : ByteArray) : List Value → ByteArray
  | [] => out
  | [v] => printTo out v
  | v :: vs => printList ((printTo out v).push 0x2C) vs
def printMembers (out : ByteArray) : List (String × Value) → ByteArray
  | [] => out
  | [(k, v)] => printTo ((pushStr out k).push 0x3A) v
  | (k, v) :: ms => printMembers ((printTo ((pushStr out k).push 0x3A) v).push 0x2C) ms
end

/-- The canonical text of `v`. -/
def print (v : Value) : ByteArray := printTo .empty v

end Fvapi.Json
