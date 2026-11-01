import TestsU3.Runner

open TestsU3

private def reference : JsonApi where
  decode := Oracle.decode
  print v := (Oracle.text v).toUTF8
  object ms := .obj (Oracle.sortMembers ms)
  get? k v := match v with
    | .obj ms => (ms.find? (fun (key, _) => key == k)).map Prod.snd
    | _ => none
  asStr? v := match v with | .str s => some s | _ => none
  asInt? v := match v with | .int n => some n | _ => none
  asBool? v := match v with | .bool b => some b | _ => none
  asArr? v := match v with | .arr xs => some xs | _ => none
  asObj? v := match v with | .obj ms => some ms | _ => none
  equal := (· == ·)

/-- This target never imports implementation modules. Green here is oracle/harness evidence. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | [dir] =>
    try
      let t0 ← IO.monoMsNow
      let count ← JsonSuite.corpus reference dir "all"
      let laws ← JsonSuite.laws reference
      let mut detected := 0
      for bad in [
        { reference with decode := fun _ => .ok .null },
        { reference with print := fun _ => "null".toUTF8 },
        { reference with object := fun ms => .obj ms },
        { reference with get? := fun _ _ => none },
        { reference with asInt? := fun _ => some 0 }] do
        let rejected ← try
          let _ ← JsonSuite.corpus bad dir "T1"
          let _ ← JsonSuite.laws bad
          pure false
        catch _ => pure true
        check rejected "oracle selfcheck: planted bad API escaped assertions"
        detected := detected + 1
      for kind in ["deep", "digits", "cap-suffix", "flat", "sorted", "reverse", "prefix",
          "escaped", "multibyte"] do
        for mode in ["fresh", "retained"] do
          JsonSuite.resource reference kind 40 mode
      IO.println (s!"oracle: {count} crosschecks + {laws} laws; {detected} bad APIs caught; "
        ++ s!"18 reference-Task smokes; {(← IO.monoMsNow) - t0} ms")
      return 0
    catch e =>
      IO.eprintln e.toString
      return if (e.toString.splitOn "setup:").length > 1 then 2 else 1
  | _ => IO.eprintln "usage: fvapi-tests-u3-oracle CORPUS_DIR"; return 2
