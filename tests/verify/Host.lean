import Fvapi.Verify.Host

open Fvapi Fvapi.Verify

private def check (name : String) (action : IO Bool) : IO Nat := do
  try
    if ← action then
      IO.println s!"PASS host: {name}"
      return 0
    else
      IO.eprintln s!"assertion: host: {name}"
      return 1
  catch e =>
    IO.eprintln s!"assertion: host: {name}: subject IO failed: {e}"
    return 1

private def fields (pre : System.FilePath) (p : Profile) (runtime : Bool)
    (wanted : List String) : IO Bool := do
  let got := (← checkHost pre p runtime).map (·.field)
  return got.all wanted.contains && wanted.all got.contains

def main (args : List String) : IO UInt32 := do
  let [pre, tree, path] := args | IO.eprintln "setup: host: prefix tree profile"; return 2
  let p ← match Json.decode (← IO.FS.readBinFile path) with
    | .error e => IO.eprintln s!"setup: host: profile JSON {repr e}"; return 2
    | .ok v => match checkProfile .service v with
      | .error e => IO.eprintln s!"setup: host: profile {repr e}"; return 2
      | .ok p => pure p
  let pre : System.FilePath := pre
  let mut failed := 0
  failed := failed + (← check "Ttargets set: first primitive + backquoted builtin only" do
    let got := comparatorTargets (← IO.FS.readFile (pre / p.comparatorSource))
    let wanted := ["Nat.add", "Nat.sub", "Quot"]
    pure (got.all wanted.contains && wanted.all got.contains))
  failed := failed + (← check "Ttree exact relative files; symlinks excluded" do
    pure ((← regularFiles tree) == #["a/b.txt", "top"]))
  failed := failed + (← check "Tmanifest independent exact digest" do
    pure ((← runtimeDigest pre) == p.runtimeSha256))
  failed := failed + (← check "Tmanifest matching pins + runtime" (fields pre p true []))
  let wrongRuntime := { p with runtimeSha256 := String.ofList (List.replicate 64 '0') }
  failed := failed + (← check "Tmanifest runtime mismatch" (
    fields pre wrongRuntime true ["runtime.sha256"]))
  failed := failed + (← check "runtime=false ignores runtime alone" (
    fields pre wrongRuntime false []))
  failed := failed + (← check "runtime=false still checks exporter" (fields pre
    { wrongRuntime with exporter := { p.exporter with sha256 := wrongRuntime.runtimeSha256 } }
    false ["exporter.sha256"]))
  let wrongToolchain := { p with toolchain := "leanprover/lean4:v0.0.0" }
  failed := failed + (← check "Ttoolchain exact mismatch field" (
    fields pre wrongToolchain false ["toolchain"]))
  failed := failed + (← check "Hdiag missing source retains toolchain" (fields pre
    { wrongToolchain with comparatorSource := "src/absent.lean" }
    false ["toolchain", "comparator.source"]))
  failed := failed + (← check "Hdiag source digest retains toolchain" (fields pre
    { wrongToolchain with comparatorSourceSha256 := wrongRuntime.runtimeSha256 }
    false ["toolchain", "comparator.source_sha256"]))
  failed := failed + (← check "Hdiag target set retains toolchain" (fields pre
    { wrongToolchain with comparatorTargets := p.comparatorTargets ++ ["Fixture.extra"] }
    false ["toolchain", "comparator.targets"]))
  failed := failed + (← check "Hdiag runtime retains toolchain" (fields pre
    { wrongToolchain with runtimeSha256 := wrongRuntime.runtimeSha256 }
    true ["toolchain", "runtime.sha256"]))
  IO.println s!"host: 12 cases, {failed} failed"
  return if failed == 0 then 0 else 1
