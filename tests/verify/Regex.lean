import Fvapi.Json
import Fvapi.Verify.Regex

open Fvapi

private def feature : Json.Value → Option (Option String)
  | .null => some none
  | .str s => some (some s)
  | _ => none

def main (args : List String) : IO UInt32 := do
  let [path] := args | IO.eprintln "setup: regex-oracle: corpus path"; return 2
  let mut count := 0
  let mut failed := 0
  for line in (← IO.FS.readFile path).splitOn "\n" do
    unless line.isEmpty do
      let .ok (.arr [.str pattern, .str text, expected]) := Json.decode line.toUTF8
        | IO.eprintln "setup: regex-oracle: malformed corpus row"; return 2
      let some expected := feature expected
        | IO.eprintln "setup: regex-oracle: invalid expected feature"; return 2
      let got := Verify.Regex.search pattern text
      count := count + 1
      if got != expected then
        if failed < 8 then
          IO.eprintln (s!"assertion: regex-oracle: {repr pattern} / {repr text}: " ++
            s!"got {repr got}, expected {repr expected}")
        failed := failed + 1
  IO.println s!"regex-oracle: {count} cases, {failed} failed"
  return if count > 0 && failed == 0 then 0 else 1
