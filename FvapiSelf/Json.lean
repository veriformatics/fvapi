import Fvapi.Json
import FvapiSpec.Json

/-! Closed claims for the fvapi JSON profile codec (`docs/contracts/U3-codecs.md` J5–J6). -/

namespace FvapiSelf.Json

open Fvapi.Json FvapiSpec.Json

/-- J6: decoding returns exactly the outcome the byte grammar assigns (total + deterministic,
errors included). -/
def DecodeExact : Prop :=
  ∀ (b : ByteArray) (r : Except DecodeError Value), decode b = r ↔ Outcome b.data.toList r

/-- J1, J6: a successful decode returns a valid value. -/
def DecodeValid : Prop := ∀ (b : ByteArray) (v : Value), decode b = .ok v → Valid v

/-- J6: the raw grammar is deterministic: a text denotes one value (members in text order). -/
def TextUnique : Prop := ∀ (bs : Bytes) (v w : Value), Text bs v → Text bs w → v = w

/-- J6: the shipped printer emits exactly the reviewed canonical text. -/
def PrintExact : Prop := ∀ v : Value, (print v).data.toList = canonical v

/-- J6: the canonical text of a valid value decodes, by the grammar, to that value. -/
def RoundTrip : Prop := ∀ v : Value, Valid v → Outcome (canonical v) (.ok v)

/-- J6 corollary: shipped `print`, then shipped `decode`, returns a valid value unchanged. -/
def PrintDecode : Prop := ∀ v : Value, Valid v → decode (print v) = .ok v

/-- J6 corollary: canonical text tells valid values apart. -/
def CanonicalInjective : Prop :=
  ∀ v w : Value, Valid v → Valid w → canonical v = canonical w → v = w

/-- J5: `Value.object ms` is `ms` stably sorted by key: a permutation, keys ascending, members
with equal keys in their original order (children untouched). -/
def ObjectLaw : Prop :=
  ∀ ms : List (String × Value), ∃ ms', Value.object ms = .obj ms' ∧ ms'.Perm ms ∧
    ms'.Pairwise (fun a b => a.1 ≤ b.1) ∧ ∀ k, ms'.filter (·.1 == k) = ms.filter (·.1 == k)

/-- J5: `get? key` returns the value of the first member whose key equals `key`; `none` for an
absent key or a non-object. -/
def GetLaw : Prop :=
  (∀ (ms : List (String × Value)) (k : String) (w : Value),
      (Value.obj ms).get? k = some w ↔
        ∃ pre post, ms = pre ++ (k, w) :: post ∧ ∀ p ∈ pre, p.1 ≠ k) ∧
  (∀ (ms : List (String × Value)) (k : String),
      (Value.obj ms).get? k = none ↔ ∀ p ∈ ms, p.1 ≠ k) ∧
  ∀ (v : Value) (k : String), (∀ ms, v ≠ .obj ms) → v.get? k = none

/-- J5: each projection returns exactly its constructor's payload, `none` for the rest. -/
def AsLaws : Prop :=
  (∀ v b, Value.asBool? v = some b ↔ v = .bool b) ∧
  (∀ v n, Value.asInt? v = some n ↔ v = .int n) ∧
  (∀ v s, Value.asStr? v = some s ↔ v = .str s) ∧
  (∀ v xs, Value.asArr? v = some xs ↔ v = .arr xs) ∧
  ∀ v ms, Value.asObj? v = some ms ↔ v = .obj ms

end FvapiSelf.Json
