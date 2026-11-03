import Fvapi.Verify.Replay

open Fvapi Fvapi.Json Fvapi.Verify.Replay

private def need (ok : Bool) (name : String) : IO UInt32 := do
  if ok then
    IO.println s!"PASS replay-io: {name}"
    return 0
  IO.eprintln s!"assertion: replay-io: {name}"
  return 1

private def outerError (root : System.FilePath) : IO UInt32 := do
  let buffer ← IO.mkRef ({} : IO.FS.Stream.Buffer)
  let stream := IO.FS.Stream.ofBuffer buffer
  let writes ← IO.mkRef 0
  let first : IO Unit := do
    let n ← writes.modifyGet fun n => (n, n + 1)
    if n == 0 then throw <| IO.userError "controlled one-shot stdout failure"
  let faulty := { stream with
    putStr := fun s => first *> stream.putStr s
    write := fun b => first *> stream.write b }
  let rc ← IO.withStdout faulty (run {
    packagePath := root, inventoryPath := root / "absent-inventory.json"
    profilePath := root / "unused-profile.json", expectedSource := root / "unused-source"
    axioms := [], json := true })
  let bytes := (← buffer.get).data
  let envelope := match decode bytes with
    | .ok v => (v.get? "error" >>= Value.asStr?) == some "replay_error" &&
        (v.get? "verdict" >>= Value.asStr?) == some "fail"
    | .error _ => false
  need (rc != 0 && (← writes.get) ≥ 2 && envelope)
    "one-shot stdout fault reaches outer replay_error + fail + nonzero"

private def frozenSet (root : System.FilePath) : IO UInt32 := do
  IO.FS.writeFile (root / "original.txt") "original\n"
  let frozen ← freeze root
  IO.FS.writeFile (root / "original.txt") "changed\n"
  IO.FS.writeFile (root / "added.txt") "added\n"
  need (!(← unchanged root frozen true)) "added path never hides a changed frozen byte"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["outer", root] => outerError root
  | ["freeze-set", root] => frozenSet root
  | mode :: directory :: ms :: command :: rest =>
    unless mode == "process" || mode == "pid2" do
      IO.eprintln "setup: replay-io: process mode"; return 2
    let some ms := ms.toNat? | IO.eprintln "setup: replay-io: timeout_ms"; return 2
    let directory : System.FilePath := directory
    if mode == "pid2" then
      unless (← IO.FS.readFile "/proc/self/stat").startsWith "1 (" do
        IO.eprintln "setup: replay-io: PID1 required before private allocator reset"; return 2
      -- Runtime threads get high ids before exec; leave authentic pid2 for the first child.
      IO.FS.writeFile "/proc/sys/kernel/ns_last_pid" "1"
    let r ← runProcess directory directory "probe" ms 2147483648 command rest.toArray
    let pgid ← try IO.FS.readFile (directory / "probe.pgid") catch _ => pure ""
    let value := .object [
      ("rc", (r.rc.map fun n => Value.int n).getD .null), ("timed_out", .bool r.timedOut),
      ("stderr", .str r.stderr), ("pgid", .str pgid.trimAscii.toString)]
    IO.println (String.fromUTF8! (print value))
    return 0
  | _ => IO.eprintln "setup: replay-io: outer|freeze-set|process"; return 2
