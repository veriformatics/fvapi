import TestsU3.Support

namespace TestsU3.JsonSuite

/-- Compare the independent parser with strict-Python outcomes and jq's canonical bytes. -/
def corpus (api : JsonApi) (dir : System.FilePath) (group : String) : IO Nat := do
  let rows ← loadRows (dir / "json.tsv")
  let mut count := 0
  for row in rows do
    match row with
    | [g, name, raw, tag, canonical] =>
      if group == "all" || group == g then
        let input ← unhexIO raw
        let expected := if tag == "ok" then "ok:" ++ canonical else tag
        let reference := Oracle.decode input
        check (outcomeText reference == expected) s!"oracle/{g}/{name}: staged Python crosscheck"
        let actual := api.decode input
        check (actual == reference) s!"{g}/{name}: decode expected {expected.take 120}"
        if let .ok v := actual then
          check (Oracle.valid v) s!"{g}/{name}: DecodeValid"
          check (Oracle.lexicalDepth input.data.toList == Oracle.depth v)
            s!"{g}/{name}: lexical/value depth correspondence"
          let printed := api.print v
          check (independentHex printed == canonical) s!"{g}/{name}: print decoded value"
        if let .ok v := reference then
          check (independentHex (api.print v) == canonical) s!"{g}/{name}: print reference value"
        count := count + 1
    | _ => throw (IO.userError "setup: json.tsv row shape")
  check (count > 0) s!"setup: empty corpus group {group}"
  return count

private def projections (api : JsonApi) (v : Value) (label : String) : IO Unit := do
  check (api.asStr? v == (match v with | .str s => some s | _ => none)) (label ++ "/asStr?")
  check (api.asInt? v == (match v with | .int n => some n | _ => none)) (label ++ "/asInt?")
  check (api.asBool? v == (match v with | .bool b => some b | _ => none)) (label ++ "/asBool?")
  check (api.asArr? v == (match v with | .arr xs => some xs | _ => none)) (label ++ "/asArr?")
  check (api.asObj? v == (match v with | .obj ms => some ms | _ => none)) (label ++ "/asObj?")

private def lookup (key : String) : Value → Option Value
  | .obj ms => (ms.find? (fun (k, _) => k == key)).map Prod.snd
  | _ => none

private def nested (n : Nat) : Value := (List.range n).foldl (fun v _ => .arr [v]) .null

/-- Properties quantified by the contract, checked on fixed-seed generated values. -/
def laws (api : JsonApi) : IO Nat := do
  let base : List Value := [.null, .bool false, .bool true, .int 0, .int (-1), .str "",
    .str "a\x00b", .arr [], .obj [], .obj [("x", .null)],
    .obj [("x", .int 1), ("x", .int 2)], .int 9007199254740992, .int (2 ^ 256),
    .str (String.ofList (List.replicate 65537 'a')), nested 33, nested 128,
    .obj [("z", .null), ("a", .null)], .arr [.int 0], .arr [.int 0, .int 1],
    .obj [("a", .str "a\x00"), ("a\x00", .str "a\x00b")]]
  let keys := ["", "x", "X", "missing", "a", "a\x00", "a\x00b", "é", "é", "𐀀", ""]
  let samples := base ++ ((List.range 4096).map fun i => generated (0x350003 + i.toUInt64))
  let mut count := 0
  for v in samples do
    let label := s!"T7/property-{count}"
    projections api v label
    for k in keys do
      check (api.get? k v == lookup k v) (label ++ "/get?")
    let printed := api.print v
    check (printed == (Oracle.text v).toUTF8) (label ++ "/PrintExact-total")
    if Oracle.valid v then
      check (api.decode printed == .ok v) (label ++ "/round-trip")
      check (Oracle.decode printed == .ok v) (label ++ "/reference-round-trip")
    check (api.equal v v) (label ++ "/BEq-reflexive")
    let other := generated (0x8259 + count.toUInt64)
    check (api.equal v other == (v == other)) (label ++ "/BEq-equality")
    if Oracle.valid v && Oracle.valid other then
      check ((api.print v == api.print other) == (v == other)) (label ++ "/canonical-injective")
    count := count + 1
  let children := [("z", .obj [("z", .int 1), ("a", .int 2)]),
    ("a", .obj [("x", .null), ("x", .bool true)]), ("z", nested 33)]
  check (api.object children == .obj (Oracle.sortMembers children))
    "T7/object: outer stable sort preserves invalid children"
  let bigKey := String.ofList (List.replicate 65537 'a')
  for ms in [[("", nested 31)], [("", nested 32)], [(bigKey, .null), ("a", .int 0)]] do
    let made := api.object ms
    check (made == .obj (Oracle.sortMembers ms)) "T7/object: depth + key-cap boundary"
    if Oracle.valid made then
      check (api.decode (api.print made) == .ok made) "T7/object: depth-32 round trip"
  for a in base do
    for b in base do
      check (api.equal a b == (a == b)) "T7/BEq: constructor + sequence boundaries"
  let sequencePairs : List (Value × Value) := [
    (.arr [.int 0, .int 1], .arr [.int 1, .int 0]),
    (.obj [("a", .int 0), ("b", .int 1)], .obj [("b", .int 1), ("a", .int 0)]),
    (.obj [("x", .int 0), ("x", .int 1)], .obj [("x", .int 1), ("x", .int 0)]),
    (.str "a\x00", .str "a\x00b"), (.int 0, .bool false)]
  for (a, b) in sequencePairs do
    check (!api.equal a b && !api.equal b a) "T7/BEq: order, NUL + constructor identity"
  let keyIdentity := Value.obj [("é", .int 1), ("é", .int 2), ("A", .int 3), ("a", .int 4)]
  for key in ["é", "é", "A", "a", "É"] do
    check (api.get? key keyIdentity == lookup key keyIdentity)
      "T7/get?: complete scalar identity, no normalization or case folding"
  for i in [:2048] do
    let ms := [("z", generated (i.toUInt64 + 1)), ("x", .int 1), ("x", .int 2),
      ("", .null), ("a\x00b", .bool false), ("a", .str "v"), ("𐀀", .null), ("", .null)]
    let ordered := Oracle.sortMembers ms
    check (api.object ms == .obj ordered) s!"T7/object-{i}: stable sort + repeated keys retained"
    for k in keys do
      check (api.get? k (api.object ms) == lookup k (.obj ordered)) s!"T7/object-{i}: first key"
    let distinct := ms.filter (fun (k, _) => k != "x")
    let made := api.object distinct
    check (Oracle.valid made) s!"T7/object-{i}: valid constructor"
    check (api.decode (api.print made) == .ok made) s!"T7/object-{i}: constructor round trip"
    count := count + 1
  return count

private def repeated (s : String) (n : Nat) : String := String.join (List.replicate n s)

private def padded (n : Nat) : String :=
  let s := toString n
  String.ofList (List.replicate (8 - s.length) '0') ++ s

private def resourceInput (kind : String) (n : Nat) : ByteArray :=
  let object (reverse sharedPrefix : Bool) :=
    let indices := if reverse then (List.range n).reverse else List.range n
    let keyPrefix := if sharedPrefix then repeated "p" 256 else "k"
    "{" ++ String.intercalate "," (indices.map fun i =>
      Oracle.quote (keyPrefix ++ padded i) ++ ":0") ++ "}"
  (match kind with
   | "deep" => "x" ++ repeated "[" n
   | "digits" => repeated "9" n
   | "cap-suffix" => "[\"" ++ repeated "a" n ++ "\",]"
   | "flat" => "[" ++ String.intercalate "," (List.replicate n "0") ++ "]"
   | "sorted" => object false false
   | "reverse" => object true false
   | "prefix" => object true true
   | "escaped" => "\"" ++ repeated "\\u0061" n ++ "\""
   | "multibyte" => "\"" ++ repeated "é" n ++ "\""
   | _ => "").toUTF8

private def resourceTag (kind : String) (n : Nat) : String :=
  if kind == "deep" then (if n > 32 then "tooLarge" else "malformed")
  else if kind == "digits" then (if 1 ≤ n && n ≤ 15 then "ok" else "malformed")
  else if kind == "cap-suffix" then "malformed"
  else if (kind == "escaped" && n > 65536) || (kind == "multibyte" && n * 2 > 65536) then
    "tooLarge"
  else "ok"

private def rss : IO String := do
  let status ← IO.FS.readFile "/proc/self/status"
  return ((status.splitOn "\n").find? (·.startsWith "VmRSS:")).getD "VmRSS: unavailable"

/-- One compiled Task includes decode, normalize, print and result release. Inputs retained
outside the Task vs built inside it expose builder retention in the RSS observations. -/
def resource (api : JsonApi) (kind : String) (n : Nat) (mode : String) : IO Unit := do
  check (["deep", "digits", "cap-suffix", "flat", "sorted", "reverse", "prefix", "escaped",
    "multibyte"].contains kind) "setup: resource kind"
  check (mode == "fresh" || mode == "retained") "setup: resource mode"
  let retained := if mode == "retained" then some (resourceInput kind n) else none
  let before ← rss
  let start ← IO.monoMsNow
  let task := Task.spawn fun _ =>
    let input := match retained with
      | some input => input
      | none => resourceInput kind n
    let result := api.decode input
    match result with
    | .ok v => ("ok", input.size, (api.print v).size)
    | .error .malformed => ("malformed", input.size, 0)
    | .error .tooLarge => ("tooLarge", input.size, 0)
    | .error .duplicateKey => ("duplicateKey", input.size, 0)
  let (tag, inputSize, printedSize) := task.get
  check (tag == resourceTag kind n) s!"T8/{kind}/{n}: expected {resourceTag kind n}, got {tag}"
  if tag == "ok" then check (printedSize > 0) "T8: force print traversal"
  if let some input := retained then check (input.size == inputSize) "T8: retain source"
  IO.println (s!"RESOURCE\t{kind}\t{n}\t{mode}\t{inputSize}\t{(← IO.monoMsNow) - start}"
    ++ s!"\t{before}\t{← rss}\t{printedSize}")

end TestsU3.JsonSuite
