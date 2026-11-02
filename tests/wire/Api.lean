import Fvapi.Wire.Records
import Fvapi.Wire.Decide

open Fvapi.Json Fvapi.Wire

def main : IO Unit := do
  let value := Value.object [("id", .str "x"), ("revision", .int 1)]
  let some record := Record.ofValue? entryRef value
    | throw (IO.userError "wire-api: valid EntryRef rejected")
  unless decide (record.toValue = value) do
    throw (IO.userError "wire-api: EntryRef conversion changed its value")
  let extra := Value.object [("id", .str "x"), ("revision", .int 1), ("future", .null)]
  let some projected := Record.decode? entryRef extra
    | throw (IO.userError "wire-api: tolerant EntryRef decode rejected")
  unless decide (projected.toValue = value) do
    throw (IO.userError "wire-api: tolerant EntryRef decode retained an additive member")
  unless (Record.decode? entryRef extra true).isNone do
    throw (IO.userError "wire-api: strict EntryRef decode accepted an additive member")
  let zero := Value.object [("id", .str "x"), ("revision", .int 0)]
  unless (Record.ofValue? entryRef zero).isNone do
    throw (IO.userError "wire-api: zero revision accepted")
  let checkProjection (route : Route) (status : Nat) (input expected : Value) : IO Unit := do
    match decideResponse route status (encodeResponse (.json input)) with
    | .ok (.json actual) =>
      unless decide (actual = expected) do
        throw (IO.userError "wire-api: encoded response did not return its known-field projection")
    | _ => throw (IO.userError "wire-api: admissible additive response rejected")
  checkProjection .me 200 (.object [("caller_id", .str "a"), ("extra", .int 0)])
    (.object [("caller_id", .str "a")])
  checkProjection .request 202
    (.object [("extra", .int 0), ("row", .object
      [("id", .str "a"), ("state", .str "queued"), ("extra", .int 0)])])
    (.object [("row", .object [("id", .str "a"), ("state", .str "queued")])])
  IO.println "wire-api: typed records + conversions + additive response projection controls passed"
