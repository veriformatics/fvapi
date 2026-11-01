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

end Fvapi.Json
