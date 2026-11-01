import TestsU3.Oracle

namespace TestsU3

/-- Every shipped name occurs in Api.lean alone. Suites use this test-owned vocabulary. -/
structure JsonApi where
  decode : ByteArray → Outcome
  print : Value → ByteArray
  object : List (String × Value) → Value
  get? : String → Value → Option Value
  asStr? : Value → Option String
  asInt? : Value → Option Int
  asBool? : Value → Option Bool
  asArr? : Value → Option (List Value)
  asObj? : Value → Option (List (String × Value))
  equal : Value → Value → Bool

structure HashApi where
  State : Type
  hash : ByteArray → ByteArray
  init : State
  update : State → ByteArray → State
  finish : State → ByteArray
  ofReader : IO ByteArray → IO ByteArray
  file : System.FilePath → IO ByteArray
  hex : ByteArray → String

end TestsU3
