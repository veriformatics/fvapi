import Fvapi.Wire.Schema

namespace Fvapi.Wire

open Fvapi.Json

mutual
/-- Constructive equality, independent of the codec's unproved derived `BEq Value`. -/
def valueDecEq (a b : Value) : Decidable (a = b) :=
  match a, b with
  | .null, .null => isTrue rfl
  | .bool x, .bool y => if h : x = y then isTrue (by cases h; rfl)
      else isFalse (by intro h'; cases h'; exact h rfl)
  | .int x, .int y => if h : x = y then isTrue (by cases h; rfl)
      else isFalse (by intro h'; cases h'; exact h rfl)
  | .str x, .str y => if h : x = y then isTrue (by cases h; rfl)
      else isFalse (by intro h'; cases h'; exact h rfl)
  | .arr xs, .arr ys => match valuesDecEq xs ys with
      | isTrue h => isTrue (congrArg Value.arr h)
      | isFalse h => isFalse (by intro h'; cases h'; exact h rfl)
  | .obj xs, .obj ys => match membersDecEq xs ys with
      | isTrue h => isTrue (congrArg Value.obj h)
      | isFalse h => isFalse (by intro h'; cases h'; exact h rfl)
  | .null, .bool _ | .null, .int _ | .null, .str _ | .null, .arr _ | .null, .obj _
  | .bool _, .null | .bool _, .int _ | .bool _, .str _ | .bool _, .arr _ | .bool _, .obj _
  | .int _, .null | .int _, .bool _ | .int _, .str _ | .int _, .arr _ | .int _, .obj _
  | .str _, .null | .str _, .bool _ | .str _, .int _ | .str _, .arr _ | .str _, .obj _
  | .arr _, .null | .arr _, .bool _ | .arr _, .int _ | .arr _, .str _ | .arr _, .obj _
  | .obj _, .null | .obj _, .bool _ | .obj _, .int _ | .obj _, .str _ | .obj _, .arr _ =>
      isFalse (by intro h; cases h)
def valuesDecEq (xs ys : List Value) : Decidable (xs = ys) :=
  match xs, ys with
  | [], [] => isTrue rfl
  | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
  | x :: xs, y :: ys => match valueDecEq x y, valuesDecEq xs ys with
      | isTrue h, isTrue h' => isTrue (by cases h; cases h'; rfl)
      | isFalse h, _ => isFalse (by intro h'; cases h'; exact h rfl)
      | _, isFalse h => isFalse (by intro h'; cases h'; exact h rfl)
def membersDecEq (xs ys : List (String × Value)) : Decidable (xs = ys) :=
  match xs, ys with
  | [], [] => isTrue rfl
  | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
  | (k, x) :: xs, (l, y) :: ys =>
      if h : k = l then
        match valueDecEq x y, membersDecEq xs ys with
        | isTrue h', isTrue h'' => isTrue (by cases h; cases h'; cases h''; rfl)
        | isFalse h', _ => isFalse (by intro e; cases e; exact h' rfl)
        | _, isFalse h' => isFalse (by intro e; cases e; exact h' rfl)
      else isFalse (by intro e; cases e; exact h rfl)
end

instance : DecidableEq Value := valueDecEq

end Fvapi.Wire
