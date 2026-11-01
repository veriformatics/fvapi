import Std

namespace TestsU3

/-- Test vocabulary; independent of shipped types and the reviewed spec. -/
inductive Value where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | str (s : String)
  | arr (xs : List Value)
  | obj (ms : List (String × Value))
  deriving BEq, Repr, Inhabited

inductive Error where
  | malformed
  | tooLarge
  | duplicateKey
  deriving BEq, Repr

abbrev Outcome := Except Error Value

instance : BEq Outcome where
  beq a b := match a, b with
    | .ok x, .ok y => x == y
    | .error x, .error y => x == y
    | _, _ => false

namespace Oracle

private def ws (b : UInt8) : Bool := [32, 9, 10, 13].contains b.toNat
private def digit (b : UInt8) : Bool := 48 ≤ b.toNat && b.toNat ≤ 57
private def maxInt : Nat := 9007199254740991

/-- A byte scan precedes all grammar checks, including UTF-8 validation. -/
def lexicalDepth (bs : List UInt8) : Nat := Id.run do
  let mut level := 0
  let mut top := 0
  let mut quoted := false
  let mut escaped := false
  for b in bs do
    if quoted then
      if escaped then escaped := false
      else if b == 92 then escaped := true
      else if b == 34 then quoted := false
    else if b == 34 then quoted := true
    else if b == 91 || b == 123 then
      level := level + 1
      top := max top level
    else if b == 93 || b == 125 then level := level - 1
  return top

private abbrev Parser := StateT (List UInt8) (Except Unit)

private def fail {α : Type} : Parser α := throw ()
private def pop : Parser UInt8 := do
  match ← get with
  | [] => fail
  | b :: rest => set rest; pure b

private def peek : Parser (Option UInt8) := return (← get).head?

private def take (n : Nat) : Parser Unit := do
  unless (← pop).toNat == n do fail

private def skip : Parser Unit := modify (·.dropWhile ws)

private def nibble (b : UInt8) : Option Nat :=
  let n := b.toNat
  if 48 ≤ n && n ≤ 57 then some (n - 48)
  else if 65 ≤ n && n ≤ 70 then some (n - 55)
  else if 97 ≤ n && n ≤ 102 then some (n - 87)
  else none

private def hex4 : Parser Nat := do
  let mut n := 0
  for _ in [:4] do
    match nibble (← pop) with
    | none => fail
    | some d => n := n * 16 + d
  return n

private def escapedChar : Parser Char := do
  match (← pop).toNat with
  | 34 => pure '"'
  | 92 => pure '\\'
  | 47 => pure '/'
  | 98 => pure (Char.ofNat 8)
  | 102 => pure (Char.ofNat 12)
  | 110 => pure '\n'
  | 114 => pure '\r'
  | 116 => pure '\t'
  | 117 =>
    let h ← hex4
    if 0xD800 ≤ h && h ≤ 0xDBFF then
      take 92
      take 117
      let l ← hex4
      unless 0xDC00 ≤ l && l ≤ 0xDFFF do fail
      return Char.ofNat (0x10000 + (h - 0xD800) * 1024 + (l - 0xDC00))
    else if 0xDC00 ≤ h && h ≤ 0xDFFF then fail
    else pure (Char.ofNat h)
  | _ => fail

/-- Decode one scalar explicitly; no runtime replacement-character decoder is an oracle. -/
private def rawChar (b : UInt8) : Parser Char := do
  let n := b.toNat
  if n < 32 then fail
  else if n < 128 then pure (Char.ofNat n)
  else
    let (count, low, high, initial) ←
      if 0xC2 ≤ n && n ≤ 0xDF then pure (1, 0x80, 0xBF, n - 0xC0)
      else if n == 0xE0 then pure (2, 0xA0, 0xBF, n - 0xE0)
      else if 0xE1 ≤ n && n ≤ 0xEC then pure (2, 0x80, 0xBF, n - 0xE0)
      else if n == 0xED then pure (2, 0x80, 0x9F, n - 0xE0)
      else if 0xEE ≤ n && n ≤ 0xEF then pure (2, 0x80, 0xBF, n - 0xE0)
      else if n == 0xF0 then pure (3, 0x90, 0xBF, n - 0xF0)
      else if 0xF1 ≤ n && n ≤ 0xF3 then pure (3, 0x80, 0xBF, n - 0xF0)
      else if n == 0xF4 then pure (3, 0x80, 0x8F, n - 0xF0)
      else fail
    let mut scalar := initial
    for i in [:count] do
      let c := (← pop).toNat
      unless (if i == 0 then low ≤ c && c ≤ high else 0x80 ≤ c && c ≤ 0xBF) do
        fail
      scalar := scalar * 64 + c - 0x80
    return Char.ofNat scalar

private partial def stringTail (acc : List Char) : Parser String := do
  let b ← pop
  if b == 34 then return String.ofList acc.reverse
  let c ← if b == 92 then escapedChar else rawChar b
  stringTail (c :: acc)

private def string : Parser String := do
  take 34
  stringTail []

private def integer : Parser Value := do
  let negative := (← peek) == some 45
  if negative then take 45
  let first ← pop
  if first == 48 then
    if negative then fail else return .int 0
  unless 49 ≤ first.toNat && first.toNat ≤ 57 do fail
  let mut magnitude := first.toNat - 48
  while (← peek).any digit do
    let d := (← pop).toNat - 48
    magnitude := min (maxInt + 1) (magnitude * 10 + d)
  if magnitude > maxInt then fail
  else return .int (if negative then -(Int.ofNat magnitude) else Int.ofNat magnitude)

mutual
  private partial def value : Parser Value := do
    skip
    match (← peek).map UInt8.toNat with
    | some 110 =>
      for b in [110, 117, 108, 108] do take b
      pure .null
    | some 116 =>
      for b in [116, 114, 117, 101] do take b
      pure (.bool true)
    | some 102 =>
      for b in [102, 97, 108, 115, 101] do take b
      pure (.bool false)
    | some 34 => return .str (← string)
    | some 91 =>
      take 91
      skip
      if (← peek) == some 93 then take 93; return .arr []
      return .arr (← arrayTail [])
    | some 123 =>
      take 123
      skip
      if (← peek) == some 125 then take 125; return .obj []
      return .obj (← objectTail [])
    | some _ => integer
    | none => fail

  private partial def arrayTail (acc : List Value) : Parser (List Value) := do
    let v ← value
    skip
    match (← pop).toNat with
    | 93 => pure (v :: acc).reverse
    | 44 => arrayTail (v :: acc)
    | _ => fail

  private partial def objectTail (acc : List (String × Value)) :
      Parser (List (String × Value)) := do
    skip
    let key ← string
    skip
    take 58
    let v ← value
    skip
    match (← pop).toNat with
    | 125 => pure ((key, v) :: acc).reverse
    | 44 => objectTail ((key, v) :: acc)
    | _ => fail
end

private partial def large : Value → Bool
  | .str s => s.toUTF8.size > 65536
  | .arr xs => xs.any large
  | .obj ms => ms.any fun (k, v) => k.toUTF8.size > 65536 || large v
  | _ => false

private partial def duplicate : Value → Bool
  | .arr xs => xs.any duplicate
  | .obj ms =>
    (ms.map Prod.fst).length != (ms.map Prod.fst).eraseDups.length ||
      ms.any (duplicate ∘ Prod.snd)
  | _ => false

private def bytesLT : List UInt8 → List UInt8 → Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs => if a == b then bytesLT as bs else a.toNat < b.toNat

def keyLT (a b : String) : Bool := bytesLT a.toUTF8.data.toList b.toUTF8.data.toList

def sortMembers (ms : List (String × Value)) : List (String × Value) :=
  ms.mergeSort (fun a b => !keyLT b.1 a.1)

partial def normalize : Value → Value
  | .arr xs => .arr (xs.map normalize)
  | .obj ms => .obj (sortMembers (ms.map fun (k, v) => (k, normalize v)))
  | v => v

def decode (input : ByteArray) : Outcome := Id.run do
  let bytes := input.data.toList
  if lexicalDepth bytes > 32 then return .error .tooLarge
  match (do let v ← value; skip; pure v : Parser Value).run bytes with
  | .error _ => return .error .malformed
  | .ok (_, _ :: _) => return .error .malformed
  | .ok (v, []) =>
    if large v then return .error .tooLarge
    if duplicate v then return .error .duplicateKey
    return .ok (normalize v)

private def hexDigit (n : Nat) : Char := Char.ofNat (if n < 10 then 48 + n else 87 + n)

def quote (s : String) : String := Id.run do
  let mut out := ['"']
  for c in s.toList do
    let fragment := match c.toNat with
      | 34 => "\\\""
      | 92 => "\\\\"
      | 8 => "\\b"
      | 12 => "\\f"
      | 10 => "\\n"
      | 13 => "\\r"
      | 9 => "\\t"
      | n => if n < 32 || n == 127 then
          String.ofList ['\\', 'u', '0', '0', hexDigit (n / 16), hexDigit (n % 16)]
        else String.singleton c
    for x in fragment.toList do out := x :: out
  out := '"' :: out
  return String.ofList out.reverse

partial def text : Value → String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int n => toString n
  | .str s => quote s
  | .arr xs => "[" ++ String.intercalate "," (xs.map text) ++ "]"
  | .obj ms => "{" ++ String.intercalate "," (ms.map fun (k, v) => quote k ++ ":" ++ text v) ++ "}"

partial def depth : Value → Nat
  | .arr xs => 1 + (xs.map depth).foldl max 0
  | .obj ms => 1 + (ms.map (depth ∘ Prod.snd)).foldl max 0
  | _ => 0

partial def valid : Value → Bool
  | .int n => n.natAbs ≤ maxInt
  | .str s => s.toUTF8.size ≤ 65536
  | .arr xs => depth (.arr xs) ≤ 32 && xs.all valid
  | .obj ms => depth (.obj ms) ≤ 32 &&
    ms.all (fun (k, v) => k.toUTF8.size ≤ 65536 && valid v) &&
    ((ms.zip ms.tail).all fun (a, b) => keyLT a.1 b.1)
  | _ => true

end Oracle
end TestsU3
