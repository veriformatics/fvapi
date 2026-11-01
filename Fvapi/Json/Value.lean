namespace Fvapi.Json

/-- A JSON value of the fvapi profile (`docs/contracts/U3-codecs.md` J1): integers only; an
object holds its members as a list (decoded objects: ascending key bytes, keys unique). -/
inductive Value where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | str (s : String)
  | arr (xs : List Value)
  | obj (ms : List (String × Value))
  deriving Repr, Inhabited, BEq

/-- Why bytes are not a profile JSON text (`docs/api.md`: 400 `malformed` / `duplicate_key`,
413 `too_large`). -/
inductive DecodeError where
  | malformed
  | tooLarge
  | duplicateKey
  deriving Repr, DecidableEq

namespace Value

/-- Members in ascending key order (`String` order = code point order = UTF-8 byte order),
stable, at the outer level alone: repeated keys stay; children are untouched (J5). -/
def sortMembers (ms : List (String × Value)) : List (String × Value) :=
  ms.mergeSort fun a b => decide (a.1 ≤ b.1)

/-- An object whose members are `ms` stably sorted by key, so a code-built record prints
canonically; valid when its keys are distinct + bounded and its children valid (J5). -/
def object (ms : List (String × Value)) : Value := .obj (sortMembers ms)

/-- The value of the first member whose key equals `key`; `none` for an absent key or a
non-object (a present JSON null is `some .null`). -/
def get? (v : Value) (key : String) : Option Value :=
  match v with
  | .obj ms => (ms.find? (·.1 == key)).map (·.2)
  | _ => none

def asBool? : Value → Option Bool
  | .bool b => some b
  | _ => none

def asInt? : Value → Option Int
  | .int n => some n
  | _ => none

def asStr? : Value → Option String
  | .str s => some s
  | _ => none

def asArr? : Value → Option (List Value)
  | .arr xs => some xs
  | _ => none

def asObj? : Value → Option (List (String × Value))
  | .obj ms => some ms
  | _ => none

end Value

end Fvapi.Json
