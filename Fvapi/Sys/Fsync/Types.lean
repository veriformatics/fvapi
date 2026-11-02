import Std

namespace Fvapi.Sys.Fsync

structure Path where
  toString : String
  nulFree : '\x00' ∉ toString.toList
  deriving Repr

namespace Path

def ofString? (s : String) : Option Path :=
  if h : '\x00' ∉ s.toList then some ⟨s, h⟩ else none

instance : ToString Path := ⟨Path.toString⟩

end Path

structure Mode where
  toNat : Nat
  bounded : toNat ≤ 511
  deriving Repr

namespace Mode

def ofNat? (n : Nat) : Option Mode := if h : n ≤ 511 then some ⟨n, h⟩ else none

def default : Mode := ⟨420, by decide⟩

instance : Inhabited Mode := ⟨default⟩

end Mode

inductive Op where
  | create | write | sync | close | openDir | syncDir | closeDir
  deriving Repr, DecidableEq, BEq

inductive Cause where
  | errno (number : Nat)
  | retryExhausted | noProgress | alreadyClosed
  deriving Repr, DecidableEq, BEq

structure SysError where
  op : Op
  cause : Cause
  path : Path
  secondary? : Option (Op × Nat) := none
  deriving Repr

namespace Model

abbrev Response := Except Nat Nat

def eintr : Nat := 4

def retryBudget : Nat := 64

def maxWrite : Nat := 2 ^ 30

inductive Request where
  | create (path : Path) (mode : Mode)
  | openDir (path : Path)
  | write (fd offset count : Nat)
  | fsync (fd : Nat)
  | close (fd : Nat)
  deriving Repr

structure Event where
  request : Request
  response : Response
  deriving Repr

structure WriterState where
  path : Path
  fd : Nat
  closed : Bool := false
  deriving Repr

inductive WriterAction where
  | write (size : Nat)
  | sync | close | finalize
  deriving Repr, DecidableEq

structure Execution where
  result : Except SysError Nat
  events : List Event
  consumed : Nat
  deriving Repr

end Model
end Fvapi.Sys.Fsync
