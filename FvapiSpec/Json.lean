import Fvapi.Json.Value

/-! The fvapi JSON profile as a byte grammar (`docs/contracts/U3-codecs.md` J1–J4): which bytes
denote which value, the outcome of decoding them, the canonical text of a value. Reviewed against
RFC 8259 + `docs/api.md`; never imported by shipped code. -/

namespace FvapiSpec.Json

open Fvapi.Json

abbrev Bytes := List UInt8

/-! ## Values -/

/-- Largest integer magnitude: |n| ≤ 2^53 − 1 (`docs/api.md`). -/
def maxInt : Nat := 2 ^ 53 - 1

/-- Largest string or key, in UTF-8 bytes (`docs/api.md`: strings ≤ 64 KiB). -/
def maxStringBytes : Nat := 65536

/-- Largest nesting depth, the root container counting 1 (`docs/api.md`: depth ≤ 32). -/
def maxDepth : Nat := 32

mutual
/-- A scalar 0; a container 1 + its deepest child (an empty container 1). -/
def depth : Value → Nat
  | .arr xs => 1 + depthList xs
  | .obj ms => 1 + depthMembers ms
  | _ => 0
def depthList : List Value → Nat
  | [] => 0
  | v :: vs => max (depth v) (depthList vs)
def depthMembers : List (String × Value) → Nat
  | [] => 0
  | (_, v) :: ms => max (depth v) (depthMembers ms)
end

mutual
/-- Every string + key fits `maxStringBytes`. -/
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

mutual
/-- Every integer has magnitude ≤ `maxInt`. -/
def intsFit : Value → Bool
  | .int n => n.natAbs ≤ maxInt
  | .arr xs => intsFitList xs
  | .obj ms => intsFitMembers ms
  | _ => true
def intsFitList : List Value → Bool
  | [] => true
  | v :: vs => intsFit v && intsFitList vs
def intsFitMembers : List (String × Value) → Bool
  | [] => true
  | (_, v) :: ms => intsFit v && intsFitMembers ms
end

mutual
/-- Some object holds two members whose keys are equal. -/
def hasDupKey : Value → Bool
  | .arr xs => hasDupKeyList xs
  | .obj ms => !decide (ms.map (·.1)).Nodup || hasDupKeyMembers ms
  | _ => false
def hasDupKeyList : List Value → Bool
  | [] => false
  | v :: vs => hasDupKey v || hasDupKeyList vs
def hasDupKeyMembers : List (String × Value) → Bool
  | [] => false
  | (_, v) :: ms => hasDupKey v || hasDupKeyMembers ms
end

mutual
/-- Every object's keys strictly ascend (`String` order = code point order = UTF-8 byte order). -/
def keysAscend : Value → Bool
  | .arr xs => keysAscendList xs
  | .obj ms => decide ((ms.map (·.1)).Pairwise (· < ·)) && keysAscendMembers ms
  | _ => true
def keysAscendList : List Value → Bool
  | [] => true
  | v :: vs => keysAscend v && keysAscendList vs
def keysAscendMembers : List (String × Value) → Bool
  | [] => true
  | (_, v) :: ms => keysAscend v && keysAscendMembers ms
end

/-- A value the decoder can return; the printer's laws hold on these. -/
def Valid (v : Value) : Prop :=
  intsFit v = true ∧ stringsFit v = true ∧ depth v ≤ maxDepth ∧ keysAscend v = true

mutual
/-- Members sorted by key (stable), at every level. -/
def canon : Value → Value
  | .arr xs => .arr (canonList xs)
  | .obj ms => .obj ((canonMembers ms).mergeSort fun a b => decide (a.1 ≤ b.1))
  | v => v
def canonList : List Value → List Value
  | [] => []
  | v :: vs => canon v :: canonList vs
def canonMembers : List (String × Value) → List (String × Value)
  | [] => []
  | (k, v) :: ms => (k, canon v) :: canonMembers ms
end

/-! ## Grammar (RFC 8259 restricted to the profile) -/

/-- RFC 8259 whitespace: space, tab, LF, CR. -/
def isWs (b : UInt8) : Bool := b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D

def isDigit (b : UInt8) : Bool := 0x30 ≤ b && b ≤ 0x39

/-- `Ws cs rest`: `cs` = a maximal whitespace run, then `rest`. -/
inductive Ws : Bytes → Bytes → Prop
  | stop {rest : Bytes} : (∀ b ∈ rest.head?, isWs b = false) → Ws rest rest
  | skip {b : UInt8} {cs rest : Bytes} : isWs b = true → Ws cs rest → Ws (b :: cs) rest

/-- `DigitRun acc cs n rest`: `cs` = a maximal nonempty run of decimal digits, `n` = `acc`
followed by those digits, then `rest`. -/
inductive DigitRun : Nat → Bytes → Nat → Bytes → Prop
  | last {acc : Nat} {d : UInt8} {rest : Bytes} :
      isDigit d = true → (∀ b ∈ rest.head?, isDigit b = false) →
      DigitRun acc (d :: rest) (10 * acc + (d - 0x30).toNat) rest
  | more {acc n : Nat} {d : UInt8} {cs rest : Bytes} :
      isDigit d = true → DigitRun (10 * acc + (d - 0x30).toNat) cs n rest →
      DigitRun acc (d :: cs) n rest

/-- Profile integers: `0`, or an optional `-` then a nonzero digit opening a maximal digit run,
magnitude ≤ `maxInt`; `-0`, `+`, leading zeros, fractions + exponents have no derivation. A
`0` followed by a digit leaves that digit as the rest (no text continues with it). -/
inductive IntLit : Bytes → Int → Bytes → Prop
  | zero {rest : Bytes} : IntLit (0x30 :: rest) 0 rest
  | pos {d : UInt8} {cs rest : Bytes} {n : Nat} :
      0x31 ≤ d → d ≤ 0x39 → DigitRun 0 (d :: cs) n rest → n ≤ maxInt → IntLit (d :: cs) n rest
  | neg {d : UInt8} {cs rest : Bytes} {n : Nat} :
      0x31 ≤ d → d ≤ 0x39 → DigitRun 0 (d :: cs) n rest → n ≤ maxInt →
      IntLit (0x2D :: d :: cs) (-n) rest

/-- A hex digit of either case. -/
def hexVal (b : UInt8) : Option Nat :=
  if 0x30 ≤ b ∧ b ≤ 0x39 then some (b - 0x30).toNat
  else if 0x41 ≤ b ∧ b ≤ 0x46 then some (b - 0x37).toNat
  else if 0x61 ≤ b ∧ b ≤ 0x66 then some (b - 0x57).toNat
  else none

/-- `Hex4 cs n rest`: four hex digits denoting `n`, then `rest`. -/
inductive Hex4 : Bytes → Nat → Bytes → Prop
  | mk {a b c d : UInt8} {rest : Bytes} {va vb vc vd : Nat} :
      hexVal a = some va → hexVal b = some vb → hexVal c = some vc → hexVal d = some vd →
      Hex4 (a :: b :: c :: d :: rest) (((va * 16 + vb) * 16 + vc) * 16 + vd) rest

/-- `Escape cs c rest`: an escape after its backslash, denoting the scalar `c`. A `\u` escape
of a surrogate stands only as a high + low pair, denoting one scalar above U+FFFF. -/
inductive Escape : Bytes → Char → Bytes → Prop
  | quote {rest : Bytes} : Escape (0x22 :: rest) '"' rest
  | backslash {rest : Bytes} : Escape (0x5C :: rest) '\\' rest
  | slash {rest : Bytes} : Escape (0x2F :: rest) '/' rest
  | backspace {rest : Bytes} : Escape (0x62 :: rest) (Char.ofNat 0x08) rest
  | formfeed {rest : Bytes} : Escape (0x66 :: rest) (Char.ofNat 0x0C) rest
  | newline {rest : Bytes} : Escape (0x6E :: rest) '\n' rest
  | ret {rest : Bytes} : Escape (0x72 :: rest) '\r' rest
  | tab {rest : Bytes} : Escape (0x74 :: rest) '\t' rest
  | unit {cs rest : Bytes} {n : Nat} :
      Hex4 cs n rest → (n < 0xD800 ∨ 0xDFFF < n) → Escape (0x75 :: cs) (Char.ofNat n) rest
  | pair {cs cs' rest : Bytes} {hi lo : Nat} :
      Hex4 cs hi (0x5C :: 0x75 :: cs') → Hex4 cs' lo rest →
      0xD800 ≤ hi → hi ≤ 0xDBFF → 0xDC00 ≤ lo → lo ≤ 0xDFFF →
      Escape (0x75 :: cs) (Char.ofNat (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00))) rest

/-- `StrBody cs chars rest`: string-literal elements through the closing quote. A raw element
is any scalar ≥ U+0020 other than `"` + `\`, as Lean core's UTF-8 encoding of it (so overlong
forms, encoded surrogates + stray continuation bytes have no derivation). -/
inductive StrBody : Bytes → List Char → Bytes → Prop
  | close {rest : Bytes} : StrBody (0x22 :: rest) [] rest
  | raw {c : Char} {cs rest : Bytes} {chs : List Char} :
      0x20 ≤ c.val → c ≠ '"' → c ≠ '\\' → StrBody cs chs rest →
      StrBody (String.utf8EncodeChar c ++ cs) (c :: chs) rest
  | esc {c : Char} {cs cs' rest : Bytes} {chs : List Char} :
      Escape cs c cs' → StrBody cs' chs rest → StrBody (0x5C :: cs) (c :: chs) rest

/-- A string literal denoting `String.ofList chars`. -/
inductive StrLit : Bytes → String → Bytes → Prop
  | mk {cs rest : Bytes} {chs : List Char} :
      StrBody cs chs rest → StrLit (0x22 :: cs) (String.ofList chs) rest

mutual
/-- `ValueP cs v rest`: `cs` = the text of `v` from its first byte, then `rest`. -/
inductive ValueP : Bytes → Value → Bytes → Prop
  | nullLit {rest : Bytes} : ValueP (0x6E :: 0x75 :: 0x6C :: 0x6C :: rest) .null rest
  | trueLit {rest : Bytes} : ValueP (0x74 :: 0x72 :: 0x75 :: 0x65 :: rest) (.bool .true) rest
  | falseLit {rest : Bytes} :
      ValueP (0x66 :: 0x61 :: 0x6C :: 0x73 :: 0x65 :: rest) (.bool .false) rest
  | int {cs rest : Bytes} {n : Int} : IntLit cs n rest → ValueP cs (.int n) rest
  | str {cs rest : Bytes} {s : String} : StrLit cs s rest → ValueP cs (.str s) rest
  | arrEmpty {cs rest : Bytes} : Ws cs (0x5D :: rest) → ValueP (0x5B :: cs) (.arr []) rest
  | arr {cs cs' rest : Bytes} {xs : List Value} :
      Ws cs cs' → Elems cs' xs rest → ValueP (0x5B :: cs) (.arr xs) rest
  | objEmpty {cs rest : Bytes} : Ws cs (0x7D :: rest) → ValueP (0x7B :: cs) (.obj []) rest
  | obj {cs cs' rest : Bytes} {ms : List (String × Value)} :
      Ws cs cs' → Members cs' ms rest → ValueP (0x7B :: cs) (.obj ms) rest

/-- Array elements after `[` + whitespace: values separated by `,` (whitespace around each),
through the closing `]`. -/
inductive Elems : Bytes → List Value → Bytes → Prop
  | last {cs r rest : Bytes} {v : Value} :
      ValueP cs v r → Ws r (0x5D :: rest) → Elems cs [v] rest
  | cons {cs r r' r'' rest : Bytes} {v : Value} {vs : List Value} :
      ValueP cs v r → Ws r (0x2C :: r') → Ws r' r'' → Elems r'' vs rest → Elems cs (v :: vs) rest

/-- Object members after `{` + whitespace: `key : value` separated by `,` (whitespace around
each token), through the closing `}`; members in text order, duplicates kept. -/
inductive Members : Bytes → List (String × Value) → Bytes → Prop
  | last {cs r₁ r₂ r₃ r₄ rest : Bytes} {k : String} {v : Value} :
      StrLit cs k r₁ → Ws r₁ (0x3A :: r₂) → Ws r₂ r₃ → ValueP r₃ v r₄ → Ws r₄ (0x7D :: rest) →
      Members cs [(k, v)] rest
  | cons {cs r₁ r₂ r₃ r₄ r₅ r₆ rest : Bytes} {k : String} {v : Value}
      {ms : List (String × Value)} :
      StrLit cs k r₁ → Ws r₁ (0x3A :: r₂) → Ws r₂ r₃ → ValueP r₃ v r₄ → Ws r₄ (0x2C :: r₅) →
      Ws r₅ r₆ → Members r₆ ms rest → Members cs ((k, v) :: ms) rest
end

/-- A JSON text: whitespace, one value, whitespace, nothing after (a BOM has no derivation). -/
def Text (cs : Bytes) (v : Value) : Prop :=
  ∃ r₁ r₂, Ws cs r₁ ∧ ValueP r₁ v r₂ ∧ Ws r₂ []

/-- Nesting depth seen by a byte scan: `[`/`{` outside string literals opens a level, `]`/`}`
closes one (never below 0); the largest level reached. Inside a literal a backslash hides the
next byte. On a JSON text it equals the value's `depth`. -/
def lexicalDepth (cs : Bytes) : Nat := go cs false false 0 0
where
  go : Bytes → Bool → Bool → Nat → Nat → Nat
    | [], _, _, _, top => top
    | _ :: cs, true, true, level, top => go cs true false level top
    | b :: cs, true, false, level, top => go cs (b != 0x22) (b == 0x5C) level top
    | b :: cs, false, _, level, top =>
      if b == 0x22 then go cs true false level top
      else if b == 0x5B || b == 0x7B then go cs false false (level + 1) (max top (level + 1))
      else if b == 0x5D || b == 0x7D then go cs false false (level - 1) top
      else go cs false false level top

/-! ## Outcome -/

/-- What decoding `b` returns, in precedence: too deep (byte scan, before any parse) → no
derivation → a string over its cap → a duplicate key → the value with members sorted. -/
inductive Outcome (b : Bytes) : Except DecodeError Value → Prop
  | deep : maxDepth < lexicalDepth b → Outcome b (.error .tooLarge)
  | malformed : lexicalDepth b ≤ maxDepth → (∀ v, ¬ Text b v) → Outcome b (.error .malformed)
  | long {v : Value} : lexicalDepth b ≤ maxDepth → Text b v → stringsFit v = false →
      Outcome b (.error .tooLarge)
  | duplicate {v : Value} : lexicalDepth b ≤ maxDepth → Text b v → stringsFit v = true →
      hasDupKey v = true → Outcome b (.error .duplicateKey)
  | ok {v : Value} : lexicalDepth b ≤ maxDepth → Text b v → stringsFit v = true →
      hasDupKey v = false → Outcome b (.ok (canon v))

/-! ## Canonical text (jq `-S -c` on valid values) -/

/-- Lowercase hex digit. -/
def hexDigit (n : Nat) : UInt8 := if n < 10 then (0x30 + n).toUInt8 else (0x57 + n).toUInt8

/-- One scalar inside a canonical string literal: the seven short escapes, `\u00xx` for the
other C0 controls + DEL, every other scalar as its UTF-8 bytes. -/
def escapeChar (c : Char) : Bytes :=
  if c = '"' then [0x5C, 0x22]
  else if c = '\\' then [0x5C, 0x5C]
  else if c.val = 0x08 then [0x5C, 0x62]
  else if c.val = 0x0C then [0x5C, 0x66]
  else if c = '\n' then [0x5C, 0x6E]
  else if c = '\r' then [0x5C, 0x72]
  else if c = '\t' then [0x5C, 0x74]
  else if c.val < 0x20 ∨ c.val = 0x7F then
    [0x5C, 0x75, 0x30, 0x30, hexDigit (c.toNat / 16), hexDigit (c.toNat % 16)]
  else String.utf8EncodeChar c

def strText (s : String) : Bytes := 0x22 :: s.toList.flatMap escapeChar ++ [0x22]

/-- Shortest decimal, `-` only when negative. -/
def intText (n : Int) : Bytes :=
  (if n < 0 then [0x2D] else []) ++ (Nat.toDigits 10 n.natAbs).map fun c => c.toNat.toUInt8

mutual
/-- No whitespace; members in stored order (a valid value's: ascending keys). -/
def canonical : Value → Bytes
  | .null => [0x6E, 0x75, 0x6C, 0x6C]
  | .bool .true => [0x74, 0x72, 0x75, 0x65]
  | .bool .false => [0x66, 0x61, 0x6C, 0x73, 0x65]
  | .int n => intText n
  | .str s => strText s
  | .arr xs => 0x5B :: canonicalList xs ++ [0x5D]
  | .obj ms => 0x7B :: canonicalMembers ms ++ [0x7D]
def canonicalList : List Value → Bytes
  | [] => []
  | [v] => canonical v
  | v :: vs => canonical v ++ 0x2C :: canonicalList vs
def canonicalMembers : List (String × Value) → Bytes
  | [] => []
  | [(k, v)] => strText k ++ 0x3A :: canonical v
  | (k, v) :: ms => strText k ++ 0x3A :: canonical v ++ 0x2C :: canonicalMembers ms
end

end FvapiSpec.Json
