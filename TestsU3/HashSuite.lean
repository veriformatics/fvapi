import TestsU3.Support

namespace TestsU3.HashSuite

private def assertDigest (api : HashApi) (input : ByteArray)
    (expected label : String) : IO Unit := do
  let before := independentHex input
  let actual := api.hash input
  check (actual.size == 32) (label ++ "/32-bytes")
  check (independentHex actual == expected) (label ++ "/digest")
  check (api.hex actual == expected) (label ++ "/hex")
  check (independentHex input == before) (label ++ "/input-unchanged")

private def vectors (api : HashApi) (file : System.FilePath) : IO Nat := do
  let rows ← loadRows file
  check (!rows.isEmpty) "setup: empty hash vectors"
  for row in rows do
    match row with
    | [name, raw, expected] => assertDigest api (← unhexIO raw) expected name
    | _ => throw (IO.userError "setup: hash vector row shape")
  return rows.length

/-- NIST's MD0=MD1=MD2=seed; 1000 three-digest rounds per outer count. -/
def nist (api : HashApi) (dir : System.FilePath) : IO Nat := do
  let count ← vectors api (dir / "nist.tsv")
  let rows ← loadRows (dir / "monte.tsv")
  let seed ← match rows.head? with
    | some ["seed", raw] => unhexIO raw
    | _ => throw (IO.userError "setup: Monte seed")
  let mut current := seed
  let mut outer := 0
  for row in rows.tail do
    match row with
    | [index, expected] =>
      check (index == toString outer) "setup: Monte count sequence"
      let mut a := current
      let mut b := current
      let mut c := current
      for _ in [:1000] do
        let next := api.hash (a ++ b ++ c)
        a := b
        b := c
        c := next
      check (independentHex c == expected) s!"T9/Monte-{outer}"
      current := c
      outer := outer + 1
    | _ => throw (IO.userError "setup: Monte row")
  check (outer == 100) "setup: Monte expected 100 counts"
  let million := ByteArray.mk ((Array.replicate 1000000 (97 : UInt8)))
  assertDigest api million
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" "T9/million-a"
  return count + outer + 1

private def slices (input : ByteArray) (sizes : List Nat) : List ByteArray := Id.run do
  let mut offset := 0
  let mut out := []
  for n in sizes do
    let stop := min input.size (offset + n)
    out := input.extract offset stop :: out
    offset := stop
  out := input.extract offset input.size :: out
  return out.reverse

private def streamed (api : HashApi) (chunks : List ByteArray) : ByteArray :=
  api.finish (chunks.foldl api.update api.init)

private def splitProperties (api : HashApi) (input : ByteArray) (label : String) : IO Nat := do
  let before := independentHex input
  let expected := api.hash input
  let boundaries := if input.size ≤ 4096 then List.range (input.size + 1) else
    [0, 1, 2, 31, 32, 54, 55, 56, 57, 62, 63, 64, 65, 66, 118, 119, 120, 121, 127, 128,
      129, 4095, 4096, 4097, input.size / 2, input.size - 65, input.size - 64,
      input.size - 63, input.size - 1, input.size]
  let mut count := 0
  for cut in boundaries do
    let parts := [ByteArray.empty, input.extract 0 cut, ByteArray.empty,
      input.extract cut input.size, ByteArray.empty]
    check (streamed api parts == expected) s!"{label}/split-{cut}"
    count := count + 1
  let mut seed : UInt64 := 0x256003
  for i in [:16] do
    let mut pattern := []
    for _ in [:32] do
      seed := next seed
      pattern := (seed.toNat % 129) :: pattern
    check (streamed api (slices input pattern) == expected) s!"{label}/pattern-{i}"
    count := count + 1
  if input.size ≤ 4096 then
    let oneBytes := input.data.toList.map (fun b => ByteArray.mk #[b])
    check (streamed api oneBytes == expected) (label ++ "/one-byte-chunks")
    count := count + 1
  check (independentHex input == before) (label ++ "/stream-input-unchanged")
  return count

private def readerProperties (api : HashApi) (dir : System.FilePath) : IO Nat := do
  let headBytes := bytes 7 65
  let suffix := bytes 8 4097
  let chunks ← IO.mkRef [headBytes, ByteArray.empty, suffix]
  let calls ← IO.mkRef 0
  let read := do
    calls.modify (· + 1)
    match ← chunks.get with
    | [] => throw (IO.userError "reader-called-after-empty")
    | b :: rest => chunks.set rest; pure b
  let digest ← api.ofReader read
  check (digest == api.hash headBytes) "T10/reader-stops-at-first-empty"
  check ((← calls.get) == 2) "T10/reader-call-count"
  for n in [0, 1, 2] do
    let seen ← IO.mkRef 0
    let badRead := do
      let i ← seen.get
      seen.set (i + 1)
      if i == n then throw (IO.userError "u3-reader-sentinel")
      else pure headBytes
    let result ← try
      let d ← api.ofReader badRead
      pure (.ok d : Except String ByteArray)
    catch e => pure (.error e.toString)
    match result with
    | .ok _ => check false s!"T10/reader-error-after-{n}: returned headBytes digest"
    | .error e =>
      check ((e.splitOn "u3-reader-sentinel").length > 1)
        s!"T10/reader-error-after-{n}: propagated original error"
    check ((← seen.get) == n + 1) s!"T10/reader-error-after-{n}: stops at error"
  let successChunks ← IO.mkRef [headBytes, suffix, ByteArray.empty]
  let successRead := do
    match ← successChunks.get with
    | [] => throw (IO.userError "success reader exhausted")
    | b :: rest => successChunks.set rest; pure b
  check ((← api.ofReader successRead) == api.hash (headBytes ++ suffix)) "T10/reader-fold"
  let file := dir / "hash-file.bin"
  IO.FS.writeBinFile file (headBytes ++ suffix)
  try
    check ((← api.file file) == api.hash (headBytes ++ suffix)) "T10/sha256File"
  finally
    IO.FS.removeFile file
  let missing ← try
    let _ ← api.file (dir / "u3-file-does-not-exist")
    pure false
  catch _ => pure true
  check missing "T10/sha256File-missing-propagates"
  let directory ← try
    let _ ← api.file dir
    pure false
  catch _ => pure true
  check directory "T10/sha256File-directory-propagates"
  return 9

private def stateProperties (api : HashApi) : IO Nat := do
  let headBytes := bytes 11 63
  let left := bytes 12 65
  let right := bytes 13 129
  let initial := api.init
  let shared := api.update initial headBytes
  let a := api.update shared left
  let b := api.update shared right
  check (api.finish a == api.hash (headBytes ++ left)) "T10/state-left-branch"
  check (api.finish b == api.hash (headBytes ++ right)) "T10/state-right-branch"
  check (api.finish shared == api.hash headBytes) "T10/state-shared-unmodified"
  check (api.finish initial == api.hash ByteArray.empty) "T10/state-init-unmodified"
  check (api.finish shared == api.finish shared) "T10/finish-repeat"
  check (api.finish (api.update shared ByteArray.empty) == api.hash headBytes) "T10/update-empty"
  check (api.finish (api.update shared left) == api.hash (headBytes ++ left))
    "T10/update-after-finish"
  let input := bytes 0x256 1048576
  let expected := api.hash input
  let before := independentHex input
  let jobs := (List.range 16).map fun i => Task.spawn fun _ =>
    if i % 2 == 0 then api.hash input
    else streamed api (slices input [i, 0, 55, 1, 63, 64, 65, 4096, 0])
  for job in jobs do check (job.get == expected) "T10/concurrent-Tasks"
  check (independentHex input == before) "T10/concurrent-input-unchanged"
  return 24

def differential (api : HashApi) (dir : System.FilePath) : IO Nat := do
  let rows ← loadRows (dir / "hash.tsv")
  check (rows.length == 142) "setup: sha256sum vectors expected 142"
  let mut count := 0
  for (row, index) in rows.zipIdx do
    match row with
    | [name, raw, expected] =>
      let input ← unhexIO raw
      assertDigest api input expected name
      -- All split points for small boundaries; generated splits cover larger inputs.
      if index < 14 then count := count + (← splitProperties api input name)
      else
        check (streamed api (slices input [0, 1, 55, 56, 63, 64, 65, 4096]) == api.hash input)
          (name ++ "/generated-splits")
      count := count + 1
    | _ => throw (IO.userError "setup: sha256sum row shape")
  let allBytes := ByteArray.mk (((List.range 256).map UInt8.ofNat).toArray)
  for input in [ByteArray.empty, allBytes, bytes 0xabcdef 4097] do
    check (api.hex input == independentHex input) "T10/hex-independent-all-bytes"
    check ((api.hex input).length == input.size * 2) "T10/hex-two-lowercase-digits"
    check ((api.hex input).toList.all fun c =>
      ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')) "T10/hex-alphabet"
  count := count + (← readerProperties api dir) + (← stateProperties api) + 9
  return count

end TestsU3.HashSuite
