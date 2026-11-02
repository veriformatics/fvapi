import Fvapi.Json.Value

namespace Fvapi.Wire

/-- Neutral syntax; the shipped interpreter and reviewed denotation live in separate modules. -/
inductive Scalar where
  | bool
  | nat
  | pos
  | boundedNat (lo hi : Nat)
  | ident
  | sha256
  | profileId
  | digest
  | token
  | cursor
  | label
  | spdx
  | text (lo hi : Nat)
  | source
  | leanName
  | absPath
  | oneOf (values : List String)
  | any
  deriving Repr, DecidableEq, Inhabited

inductive Rule where
  | path (hash path : String)
  | presenceBool (member flag : String)
  | presenceString (member tag value : String) (equal : Bool)
  | page (count items cursor : String) (first : Bool)
  | keyValue
  | rowOrigin
  | lineage
  | keysNonempty (member : String)
  | uniqueStrings (member : String)
  | uniqueField (member field : String)
  | changes
  deriving Repr, DecidableEq, Inhabited

inductive Schema where
  | scalar (kind : Scalar)
  | array (lo hi : Nat) (item : Schema)
  | record (fields : List (String × Bool × Schema)) (rules : List Rule := [])
  | tagged (tag : String) (branches : List (String × Schema))
  deriving Repr, Inhabited

abbrev Field := String × Bool × Schema

inductive Route where
  | health | me | catalog | entry | lookup | matches | bundle | check | request
  | rows | changes | row | claim | release | decline | resolve | answers | admit
  deriving Repr, DecidableEq, Inhabited

def Route.all : List Route :=
  [.health, .me, .catalog, .entry, .lookup, .matches, .bundle, .check, .request,
    .rows, .changes, .row, .claim, .release, .decline, .resolve, .answers, .admit]

def Route.name : Route → String
  | .health => "health" | .me => "me" | .catalog => "catalog" | .entry => "entry"
  | .lookup => "lookup" | .matches => "matches" | .bundle => "bundle" | .check => "check"
  | .request => "request" | .rows => "rows" | .changes => "changes" | .row => "row"
  | .claim => "claim" | .release => "release" | .decline => "decline"
  | .resolve => "resolve" | .answers => "answers" | .admit => "admit"

def Route.ofString? (s : String) : Option Route := Route.all.find? (·.name == s)

inductive BodyMode where
  | none | json | bytes
  deriving Repr, DecidableEq, Inhabited

structure QueryField where
  name : String
  kind : Scalar
  required : Bool := false
  default? : Option String := none
  deriving Repr, Inhabited

structure ResponseTable where
  status : Nat
  mode : BodyMode := .json
  schema : Schema
  deriving Repr, Inhabited

structure RouteTable where
  query : List QueryField
  requestMode : BodyMode
  requestSchema : Schema
  responses : List ResponseTable
  deriving Repr, Inhabited

inductive Failure where
  | malformed | duplicateKey | unknownKey | unauthorized | tooLarge | internal | busy
  | emptyQuery | unsupportedDigest | lookupMiss | missingEntry | missingBundle | missingRow
  | noChecker | checkerBindingMismatch | badTransition | notAdmitted
  deriving Repr, DecidableEq, Inhabited

structure Error where
  status : Nat
  code : String
  deriving Repr, DecidableEq, Inhabited

inductive Body where
  | none
  | json (value : Fvapi.Json.Value)
  | bytes (value : ByteArray)
  deriving Inhabited

structure Request where
  query : Fvapi.Json.Value
  body : Body
  deriving Inhabited

inductive Response where
  | json (value : Fvapi.Json.Value)
  | bytes (value : ByteArray)
  deriving Inhabited

inductive ResponseResult where
  | ok (value : Response)
  | badResponse
  | unsupported (features : List String)
  deriving Inhabited

structure EncodedRequest where
  query : ByteArray
  body : ByteArray
  deriving Inhabited

end Fvapi.Wire
