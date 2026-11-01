import Fvapi.Json.Value

/-! Decoding the fvapi JSON profile (`docs/contracts/U3-codecs.md` J3, J5): a nesting-depth byte
scan first, then a parser over byte indices, then the string cap, duplicate keys and member
order. Proven exact against `FvapiSpec.Json.Outcome` (`FvapiProof/Json.lean`). -/

namespace Fvapi.Json

/-- Largest integer magnitude: |n| ≤ 2^53 − 1 (`docs/api.md`). -/
def maxInt : Nat := 2 ^ 53 - 1

/-- Largest string or key, in UTF-8 bytes. -/
def maxStringBytes : Nat := 65536

/-- Largest nesting depth, the root container counting 1. -/
def maxDepth : Nat := 32

/-- Nesting depth seen by a byte scan (`FvapiSpec.Json.lexicalDepth`), as a loop: any input runs
in constant stack, and the parser below only ever sees inputs nested ≤ `maxDepth` deep. -/
def scanDepth (b : ByteArray) : Nat := go 0 false false 0 0
where
  go (i : Nat) (inStr esc : Bool) (level top : Nat) : Nat :=
    if h : i < b.size then
      let c := b[i]
      if inStr then
        if esc then go (i + 1) true false level top
        else go (i + 1) (c != 0x22) (c == 0x5C) level top
      else if c == 0x22 then go (i + 1) true false level top
      else if c == 0x5B || c == 0x7B then
        go (i + 1) false false (level + 1) (max top (level + 1))
      else if c == 0x5D || c == 0x7D then go (i + 1) false false (level - 1) top
      else go (i + 1) false false level top
    else top
  termination_by b.size - i

/-- RFC 8259 whitespace: space, tab, LF, CR. -/
def isWs (c : UInt8) : Bool := c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D

/-- The first index at or after `i` holding no whitespace byte. -/
def skipWs (b : ByteArray) (i : Nat) : Nat :=
  if h : i < b.size then
    if isWs b[i] then skipWs b (i + 1) else i
  else i
termination_by b.size - i

/-- The index after `lit` when the bytes at `i` spell it. -/
def literal (b : ByteArray) (i : Nat) : List UInt8 → Option Nat
  | [] => some i
  | c :: cs => if b[i]? == some c then literal b (i + 1) cs else none

/-- A hex digit of either case. -/
def hexVal (c : UInt8) : Option Nat :=
  if 0x30 ≤ c ∧ c ≤ 0x39 then some (c - 0x30).toNat
  else if 0x41 ≤ c ∧ c ≤ 0x46 then some (c - 0x37).toNat
  else if 0x61 ≤ c ∧ c ≤ 0x66 then some (c - 0x57).toNat
  else none

/-- The value of the four hex digits at `i`. -/
def hex4 (b : ByteArray) (i : Nat) : Option Nat := do
  let a ← hexVal (← b[i]?)
  let c ← hexVal (← b[i + 1]?)
  let d ← hexVal (← b[i + 2]?)
  let e ← hexVal (← b[i + 3]?)
  return ((a * 16 + c) * 16 + d) * 16 + e

/-- The scalar a `\u` escape at `i` (just after the `u`) denotes + the index after it: a
non-surrogate unit, or a high surrogate immediately followed by `\u` + a low one. -/
def unicodeEscape (b : ByteArray) (i : Nat) : Option (Char × Nat) :=
  match hex4 b i with
  | none => none
  | some n =>
    if n < 0xD800 ∨ 0xDFFF < n then some (Char.ofNat n, i + 4)
    else if 0xDBFF < n then none
    else if b[i + 4]? = some 0x5C ∧ b[i + 5]? = some 0x75 then
      match hex4 b (i + 6) with
      | none => none
      | some lo =>
        if 0xDC00 ≤ lo ∧ lo ≤ 0xDFFF then
          some (Char.ofNat (0x10000 + (n - 0xD800) * 0x400 + (lo - 0xDC00)), i + 10)
        else none
    else none

theorem unicodeEscape_lt {b : ByteArray} {i j : Nat} {c : Char}
    (h : unicodeEscape b i = some (c, j)) : i < j := by
  unfold unicodeEscape at h
  repeat' split at h
  all_goals first
    | contradiction
    | (injection h with h; injection h with _ h; omega)

/-- The scalar the escape after a backslash at `i` denotes + the index after the escape. -/
def escape (b : ByteArray) (i : Nat) : Option (Char × Nat) :=
  match b[i]? with
  | some 0x22 => some ('"', i + 1)
  | some 0x5C => some ('\\', i + 1)
  | some 0x2F => some ('/', i + 1)
  | some 0x62 => some (Char.ofNat 0x08, i + 1)
  | some 0x66 => some (Char.ofNat 0x0C, i + 1)
  | some 0x6E => some ('\n', i + 1)
  | some 0x72 => some ('\r', i + 1)
  | some 0x74 => some ('\t', i + 1)
  | some 0x75 => unicodeEscape b (i + 1)
  | _ => none

theorem escape_lt {b : ByteArray} {i j : Nat} {c : Char} (h : escape b i = some (c, j)) :
    i < j := by
  unfold escape at h
  split at h
  all_goals first
    | contradiction
    | (injection h with h; injection h with _ h; omega)
    | (have := unicodeEscape_lt h; omega)

/-- A string body from `i` (after the opening quote) through the closing quote: the decoded
text + the index after the quote. A loop: any length runs in constant stack. -/
def parseStr (b : ByteArray) (i : Nat) (acc : String) : Option (String × Nat) :=
  if h : i < b.size then
    let c := b[i]
    if c == 0x22 then some (acc, i + 1)
    else if c == 0x5C then
      match he : escape b (i + 1) with
      | some (ch, j) =>
        have := escape_lt he
        parseStr b j (acc.push ch)
      | none => none
    else if c < 0x20 then none
    else
      match hd : b.utf8DecodeChar? i with
      | some ch =>
        have := ch.utf8Size_pos
        parseStr b (i + ch.utf8Size) (acc.push ch)
      | none => none
  else none
termination_by b.size - i

/-- A maximal digit run from `i` folded into `acc`, + the index after it; `none` once the value
exceeds `maxInt` (more digits only grow it, so no long run grows a big number). -/
def digits (b : ByteArray) (i : Nat) (acc : Nat) : Option (Nat × Nat) :=
  if h : i < b.size then
    let c := b[i]
    if 0x30 ≤ c ∧ c ≤ 0x39 then
      let acc := 10 * acc + (c - 0x30).toNat
      if acc ≤ maxInt then digits b (i + 1) acc else none
    else some (acc, i)
  else some (acc, i)
termination_by b.size - i

/-- A profile integer at `i`: `0`, or an optional `-` then a nonzero digit's maximal run. -/
def parseInt (b : ByteArray) (i : Nat) : Option (Int × Nat) :=
  match b[i]? with
  | some 0x30 => some (0, i + 1)
  | some 0x2D =>
    match b[i + 1]? with
    | some d => if 0x31 ≤ d ∧ d ≤ 0x39 then
        (digits b (i + 1) 0).map fun (n, j) => (-(n : Int), j) else none
    | none => none
  | some d => if 0x31 ≤ d ∧ d ≤ 0x39 then (digits b i 0).map fun (n, j) => ((n : Int), j)
    else none
  | none => none

mutual
/-- The value whose text starts at `i`, + the index after it. `fuel` bounds the call chain
(`decode` passes `2 * size + 2`, proven sufficient); nesting recursion is bounded by the depth
scan, sibling + member loops are self tail calls (compiled loops). -/
def parseValue (b : ByteArray) (fuel i : Nat) : Option (Value × Nat) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    match b[i]? with
    | some 0x6E => (literal b (i + 1) [0x75, 0x6C, 0x6C]).map (.null, ·)
    | some 0x74 => (literal b (i + 1) [0x72, 0x75, 0x65]).map (.bool true, ·)
    | some 0x66 => (literal b (i + 1) [0x61, 0x6C, 0x73, 0x65]).map (.bool false, ·)
    | some 0x22 => (parseStr b (i + 1) "").map fun (s, j) => (.str s, j)
    | some 0x5B =>
      let j := skipWs b (i + 1)
      if b[j]? == some 0x5D then some (.arr [], j + 1) else parseElems b fuel j #[]
    | some 0x7B =>
      let j := skipWs b (i + 1)
      if b[j]? == some 0x7D then some (.obj [], j + 1) else parseMembers b fuel j #[]
    | some _ => (parseInt b i).map fun (n, j) => (.int n, j)
    | none => none

/-- Array elements from `i` (an element's first byte) through `]`. -/
def parseElems (b : ByteArray) (fuel i : Nat) (acc : Array Value) : Option (Value × Nat) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    match parseValue b fuel i with
    | none => none
    | some (v, j) =>
      let k := skipWs b j
      match b[k]? with
      | some 0x2C => parseElems b fuel (skipWs b (k + 1)) (acc.push v)
      | some 0x5D => some (.arr (acc.push v).toList, k + 1)
      | _ => none

/-- Object members from `i` (a key's opening quote) through `}`, in text order. -/
def parseMembers (b : ByteArray) (fuel i : Nat) (acc : Array (String × Value)) :
    Option (Value × Nat) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    if b[i]? != some 0x22 then none
    else
      match parseStr b (i + 1) "" with
      | none => none
      | some (key, j) =>
        let k := skipWs b j
        if b[k]? != some 0x3A then none
        else
          match parseValue b fuel (skipWs b (k + 1)) with
          | none => none
          | some (v, m) =>
            let n := skipWs b m
            match b[n]? with
            | some 0x2C => parseMembers b fuel (skipWs b (n + 1)) (acc.push (key, v))
            | some 0x7D => some (.obj (acc.push (key, v)).toList, n + 1)
            | _ => none
end

mutual
/-- Every string + key fits `maxStringBytes` (`&&` chains compile to loops over siblings). -/
def stringsFit : Value → Bool
  | .str s => s.utf8ByteSize ≤ maxStringBytes
  | .arr xs => stringsFitList xs
  | .obj ms => stringsFitMembers ms
  | _ => true
def stringsFitList : List Value → Bool
  | [] => true
  | v :: vs => stringsFit v && stringsFitList vs
def stringsFitMembers : List (String × Value) → Bool
  | [] => true
  | (k, v) :: ms => k.utf8ByteSize ≤ maxStringBytes && stringsFit v && stringsFitMembers ms
end

/-- Two equal neighbours in a list. -/
def adjacentDup : List String → Bool
  | a :: b :: rest => a == b || adjacentDup (b :: rest)
  | _ => false

mutual
/-- Some object holds two members with equal keys: its keys sorted, neighbours compared
(`O(m log m)`, where the spec's `Nodup` reads every pair). -/
def hasDupKey : Value → Bool
  | .arr xs => hasDupKeyList xs
  | .obj ms => adjacentDup ((ms.map (·.1)).mergeSort (· ≤ ·)) || hasDupKeyMembers ms
  | _ => false
def hasDupKeyList : List Value → Bool
  | [] => false
  | v :: vs => hasDupKey v || hasDupKeyList vs
def hasDupKeyMembers : List (String × Value) → Bool
  | [] => false
  | (_, v) :: ms => hasDupKey v || hasDupKeyMembers ms
end

mutual
/-- Members sorted by key at every level (`FvapiSpec.Json.canon`); siblings through
accumulators, so a long array or object runs in constant stack. -/
def canon : Value → Value
  | .arr xs => .arr (canonList xs [])
  | .obj ms => .obj (Value.sortMembers (canonMembers ms []))
  | v => v
def canonList : List Value → List Value → List Value
  | [], acc => acc.reverse
  | v :: vs, acc => canonList vs (canon v :: acc)
def canonMembers : List (String × Value) → List (String × Value) → List (String × Value)
  | [], acc => acc.reverse
  | (k, v) :: ms, acc => canonMembers ms ((k, canon v) :: acc)
end

/-- Decodes the fvapi JSON profile (`FvapiSpec.Json.Outcome`): too deep → `tooLarge` before
any parse; not a JSON text → `malformed`; a string or key over the cap → `tooLarge`; a repeated
key → `duplicateKey`; else the value with members sorted by key. -/
def decode (b : ByteArray) : Except DecodeError Value :=
  if maxDepth < scanDepth b then .error .tooLarge
  else
    match parseValue b (2 * b.size + 2) (skipWs b 0) with
    | some (v, j) =>
      if skipWs b j != b.size then .error .malformed
      else if !stringsFit v then .error .tooLarge
      else if hasDupKey v then .error .duplicateKey
      else .ok (canon v)
    | none => .error .malformed

end Fvapi.Json
