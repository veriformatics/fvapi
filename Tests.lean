import Fvapi
import Fvapi.Verify.Replay.Decision

open Fvapi.Cli
open Fvapi.Verify
open Fvapi.Hash
open Fvapi.Json

/-- One case: its name, whether it held, and its wall-clock in milliseconds. -/
structure Outcome where
  name : String
  ok : Bool
  ms : Nat

/-- The decode error of `t`, `none` on success. -/
def errorOf (t : String) : Option DecodeError :=
  match decode t.toUTF8 with
  | .ok _ => none
  | .error e => some e

def check (name : String) (ok : Unit → Bool) : IO Outcome := do
  let t0 ← IO.monoMsNow
  let held := ok ()
  let t1 ← IO.monoMsNow
  IO.println s!"{if held then "PASS" else "FAIL"} {name}"
  return ⟨name, held, t1 - t0⟩

def mappedKernel : KernelSpec := {
  id := .conRon, pinned := ⟨"fixture", ""⟩, args := ["{export}"], timeoutMs := 1
  statusMap := [(0, .accept), (3, .reject), (4, .decline)]
  declinePattern := some "^UNSUPPORTED:(.*)$"
  crashPattern := some "deep recursion detected", configTemplate := none }

def kernelValue (args : List String) (template : Option Value := none) : Value :=
  .object <| [("name", .str "nanoda"), ("executable", .str "/fixture"),
    ("sha256", .str (String.ofList (List.replicate 64 '0'))),
    ("args", .arr (args.map .str)), ("timeout_ms", .int 1),
    ("status_map", .object [("0", .str "accept")])] ++
    template.toList.map (fun v => ("config_template", v))

def hexRun (n : Nat) (c : Char) : Value := .str (String.ofList (List.replicate n c))

/-- A minimal schema-1 profile (parse-level; host identity is `checkHost`'s). -/
def baseProfile : List (String × Value) := [
  ("version", .int 1), ("toolchain", .str "leanprover/lean4:v4.35.0"),
  ("runtime", .object [("sha256", hexRun 64 'a')]), ("export_format", .str "fvapi.export.v1"),
  ("exporter", .object [("executable", .str "{lean_prefix}/bin/leanexport"),
    ("sha256", hexRun 64 'b')]),
  ("comparator", .object [("executable", .str "{lean_prefix}/bin/lake"), ("sha256", hexRun 64 'c'),
    ("source", .str "src/Check.lean"), ("source_sha256", hexRun 64 'd'), ("targets", .arr [])]),
  ("canaries", .object [("source_repo", .str "repo"), ("source_commit", hexRun 40 'e'),
    ("set_sha256", hexRun 64 'f'), ("known_sha256", hexRun 64 '0'), ("files", .object [])]),
  ("policy_version", .int 1),
  ("caps", .object [("export_ms", .int 1), ("comparator_ms", .int 1), ("memory_bytes", .int 1)]),
  ("kernels", .arr [kernelValue ["{export}"]])]

/-- The field `parseProfile` names for `ms` (its id recomputed), `ok` when it parses. -/
def profileField (ms : List (String × Value)) : String :=
  match parseProfile (.object (("id", .str (profileId (.object ms))) :: ms)) with
  | .ok _ => "ok"
  | .error p => p.field

def setField (k : String) (v : Value) (ms : List (String × Value)) : List (String × Value) :=
  ms.map fun m => if m.1 == k then (k, v) else m

/-- Prints PASS|FAIL per case, then the slowest case; exits with the failure count. -/
def main : IO UInt32 := do
  let results ← [
    check "cli: --version prints the version on stdout, rc 0" fun _ =>
      dispatch ["--version"] == ⟨.stdout, s!"fvapi {Fvapi.version}\n", 0⟩,
    check "cli: help + --help print usage on stdout, rc 0" fun _ =>
      dispatch ["help"] == ⟨.stdout, usage, 0⟩ && dispatch ["--help"] == ⟨.stdout, usage, 0⟩,
    check "cli: no argument prints usage on stderr, rc 2" fun _ =>
      dispatch [] == ⟨.stderr, usage, 2⟩,
    check "cli: an unknown command prints usage on stderr, rc 2" fun _ =>
      dispatch ["frobnicate"] == ⟨.stderr, usage, 2⟩ &&
        dispatch ["--version", "x"] == ⟨.stderr, usage, 2⟩
    -- Kernel policy controls (docs/contracts/U2-trust.md P1).
  , check "policy: leanchecker accept + five valid declines fails (no independent accept)" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.leancheckerParanoid, .decline "f"⟩,
        ⟨.lean4lean, .decline "f"⟩, ⟨.nanoda, .decline "f"⟩, ⟨.conLeche, .decline "f"⟩,
        ⟨.conRon, .decline "f"⟩] == .fail,
    check "policy: the three lean-lineage kernels accept + three valid declines fails" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.leancheckerParanoid, .accept⟩, ⟨.lean4lean, .accept⟩,
        ⟨.nanoda, .decline "f"⟩, ⟨.conLeche, .decline "f"⟩, ⟨.conRon, .decline "f"⟩] == .fail,
    check "policy: leanchecker accept + nanoda accept passes" fun _ =>
      verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩] == .pass,
    check "policy: missing leanchecker fails" fun _ =>
      verdict [⟨.nanoda, .accept⟩, ⟨.conLeche, .accept⟩] == .fail,
    check "policy: any timeout, crash or reject fails" fun _ =>
      [KernelStatus.timeout, .crash, .reject].all fun s =>
        verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩, ⟨.conRon, s⟩] == .fail,
    check "policy: empty result list fails" fun _ => verdict [] == .fail,
    check "policy: a blank or whitespace decline feature fails" fun _ =>
      ["", " ", "\t "].all fun f =>
        verdict [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩, ⟨.conRon, .decline f⟩] == .fail,
    check "policy: accepting lists accepting kernels once each, in profile order" fun _ =>
      accepting [.conRon, .leanchecker, .nanoda]
        [⟨.nanoda, .accept⟩, ⟨.leanchecker, .accept⟩, ⟨.conRon, .decline "x"⟩] ==
        [.leanchecker, .nanoda]
    -- Replay's pure adapters: exit maps decide accept/reject; stderr only names mapped declines.
  , check "regex: fixture anchors, exact capture, empty/space declines, per-line matching" fun _ =>
      Regex.search "^UNSUPPORTED:(.*)$" "noise\nUNSUPPORTED:x\n" == some "x" &&
        Regex.search "^UNSUPPORTED:(.*)$" "UNSUPPORTED:" == some "" &&
        Regex.search "^UNSUPPORTED:(.*)$" "UNSUPPORTED: \t" == some " \t" &&
        Regex.search "^UNSUPPORTED:(.*)$" "prefix UNSUPPORTED:x" == none,
    check "regex: lean4lean optional quote, ranges + greedy capture, crash literal" fun _ =>
      Regex.search "unknown constant '?([A-Za-z0-9_.']+)" "error: unknown constant 'Nat.missing" ==
        some "Nat.missing" &&
        Regex.search "unknown constant '?([A-Za-z0-9_.']+)" "unknown constant Foo_2" ==
          some "Foo_2" &&
        Regex.search "deep recursion detected" "error: deep recursion detected" == some "",
    check "regex: quantified groups, negated classes, escaped literals + malformed subset" fun _ =>
      Regex.search "^(ab)+$" "abab" == some "ab" &&
        Regex.search "^([a-c]*[^0-9]?)\\.$" "abcx." == some "abcx" &&
        ["(", "[", "[z-a]", "(a)(b)", "*x", "a|b", "\\"].all fun s =>
          (Regex.compile s).toOption.isNone,
    check "replay status: accept/reject mappings ignore a decline-looking line" fun _ =>
      Replay.mapStatus mappedKernel (some 0) false "UNSUPPORTED:x" == .accept &&
        Replay.mapStatus mappedKernel (some 3) false "UNSUPPORTED:x" == .reject &&
        Replay.mapStatus mappedKernel (some 4) false "UNSUPPORTED:x" == .decline "x",
    check "replay status: missing/unmapped/signal exits crash; deadline flag wins" fun _ =>
      [none, some 9, some 124, some 137, some 143].all (fun rc =>
        Replay.mapStatus mappedKernel rc false "UNSUPPORTED:x" == .crash) &&
        Replay.mapStatus mappedKernel (some 0) true "" == .timeout &&
        Replay.mapStatus mappedKernel (some 137) true "" == .timeout,
    check "replay status: unnamed decline fails policy; pinned crash pattern overrides rejection"
        fun _ =>
      ["no feature mapping", "UNSUPPORTED:", "UNSUPPORTED: "].all (fun s =>
        !(Replay.mapStatus mappedKernel (some 4) false s).admissible) &&
        Replay.mapStatus mappedKernel (some 3) false "deep recursion detected" == .crash &&
        Replay.mapStatus mappedKernel (some 4) false "deep recursion detected" == .crash &&
        Replay.mapStatus { mappedKernel with declinePattern := none }
          (some 4) false "UNSUPPORTED:x" == .crash &&
        Replay.mapStatus mappedKernel (some 0) false "deep recursion detected" == .accept,
    check "replay status: no decline capture is a crash + unnamed_unsupported" fun _ =>
      Replay.adaptStatus mappedKernel (some 4) false "no feature mapping" ==
        (.crash, some "unnamed_unsupported") &&
        Replay.adaptStatus { mappedKernel with declinePattern := none }
          (some 4) false "UNSUPPORTED:x" == (.crash, some "unnamed_unsupported"),
    check "replay status: matched blank capture stays a decline + unnamed_unsupported" fun _ =>
      ["", " ", "\t\r"].all fun feature =>
        Replay.adaptStatus mappedKernel (some 4) false ("UNSUPPORTED:" ++ feature) ==
          (.decline feature, some "unnamed_unsupported"),
    check "replay verdict: complete unique runs pass; duplicate/extra/missing fail" fun _ =>
      let rs := [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩]
      let expected := [KernelId.leanchecker, .nanoda]
      Replay.judge expected {} rs == ([], .pass) &&
        [rs ++ rs, rs ++ [⟨.conRon, .accept⟩], rs.drop 1].all fun bad =>
          let (causes, v) := Replay.judge expected {} bad
          causes.contains "kernel_missing" && v == .fail,
    check "replay verdict: snapshot/export/comparator/setup failures defeat acceptance" fun _ =>
      let rs := [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩]
      let expected := [KernelId.leanchecker, .nanoda]
      let cases : List (Replay.Facts × String) := [
        (⟨[], false, true, none⟩, "challenge_mismatch"),
        (⟨[], true, false, none⟩, "export_failed"),
        (⟨[], true, true, some "comparator_error"⟩, "comparator_error"),
        (⟨["profile_mismatch"], true, true, none⟩, "profile_mismatch")]
      cases.all fun (facts, cause) =>
        let (causes, v) := Replay.judge expected facts rs
        causes.contains cause && v == .fail,
    check "replay verdict: each kernel failure cause + insufficient independence" fun _ =>
      let expected := [KernelId.leanchecker, .nanoda, .conRon]
      let cases : List (KernelStatus × String) := [(.reject, "kernel_rejected"),
        (.crash, "kernel_crashed"), (.timeout, "kernel_timeout"),
        (.decline " \t", "unnamed_unsupported")]
      cases.all (fun (status, cause) =>
        let (causes, v) := Replay.judge expected {}
          [⟨.leanchecker, .accept⟩, ⟨.nanoda, .accept⟩, ⟨.conRon, status⟩]
        causes.contains cause && v == .fail) &&
        (Replay.judge [.leanchecker, .nanoda] {}
          [⟨.leanchecker, .accept⟩, ⟨.nanoda, .decline "x"⟩]).1.contains
            "insufficient_independent_kernels" &&
        (Replay.judge [.leanchecker, .nanoda] {}
          [⟨.leanchecker, .decline "x"⟩, ⟨.nanoda, .accept⟩]).1.contains
            "insufficient_independent_kernels",
    check "replay comparator: pinned diagnostics; setup/signal/deadline remain errors" fun _ =>
      Replay.comparatorCause (some 1) false "error: Illegal axiom detected: 'sorryAx'" ==
          some "forbidden_axiom" &&
        Replay.comparatorCause (some 1) false
          "error: Const does not match between challenge and target 'Fvapi.Subject.double'" ==
            some "challenge_mismatch" &&
        Replay.comparatorCause (some 1) false
          "Challenge and solution theorem statement do not match: 'claim'" ==
            some "challenge_mismatch" &&
        Replay.comparatorCause (some 1) false
          "Challenge and solution constant kind don't match: 'claim'" ==
            some "challenge_mismatch" &&
        [none, some 2, some 143].all (fun rc =>
          Replay.comparatorCause rc false "parse failure" == some "comparator_error") &&
        Replay.comparatorCause (some 0) true "" == some "comparator_error" &&
        Replay.comparatorCause (some 0) false "Illegal axiom detected:" == none,
    check "profile: argv reaches export directly or via a config value, not a config key" fun _ =>
      (Read.kernel "kernels[0]" (kernelValue ["{export}"])).toOption.isSome &&
        (Read.kernel "kernels[0]" (kernelValue ["{config}"]
          (some (.object [("export_file_path", .str "{export}")])))).toOption.isSome &&
        [kernelValue [], kernelValue ["file"], kernelValue ["{config}"],
          kernelValue ["{config}"] (some (.object [("{export}", .str "file")]))].all fun v =>
            match Read.kernel "kernels[0]" v with
            | .error p => p.field == "kernels[0].args"
            | .ok _ => false
    -- SHA-256 known answers (FIPS 180-2 examples) through HACL* (docs/contracts/U3-codecs.md S3).
  , check "sha256: FIPS 180-2 'abc', empty, 448-bit message" fun _ =>
      hex (sha256 "abc".toUTF8) ==
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" &&
        hex (sha256 .empty) ==
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" &&
        hex (sha256 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".toUTF8) ==
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    check "sha256: streaming over uneven chunks = one-shot" fun _ =>
      let data := ByteArray.mk ((List.range 1000).map (·.toUInt8)).toArray
      let chunked := (List.range 143).foldl
        (fun s i => Sha256.update s (data.extract (7 * i) (7 * i + 7))) Sha256.init
      Sha256.finish chunked == sha256 data &&
        Sha256.finish (Sha256.update (Sha256.update Sha256.init "ab".toUTF8) "c".toUTF8) ==
          sha256 "abc".toUTF8
    -- Profile values the pinned tools implement + executable identity (U2 P2).
  , check "profile: export_format, policy_version, canaries shape, absolute executables" fun _ =>
      profileField baseProfile == "ok" &&
        profileField (setField "export_format" (.str "fvapi.export.v2") baseProfile) ==
          "export_format" &&
        profileField (setField "policy_version" (.int 2) baseProfile) == "policy_version" &&
        profileField (setField "canaries" (.object [("source_repo", .str "repo"),
          ("source_commit", hexRun 40 'e'), ("set_sha256", hexRun 64 'f'),
          ("known_sha256", hexRun 64 '0')]) baseProfile) == "canaries.files" &&
        profileField (setField "canaries" (.object [("source_repo", .str "repo"),
          ("source_commit", .str "abc"), ("set_sha256", hexRun 64 'f'),
          ("known_sha256", hexRun 64 '0'), ("files", .object [])]) baseProfile) ==
          "canaries.source_commit" &&
        profileField (setField "exporter" (.object [("executable", .str "bin/leanexport"),
          ("sha256", hexRun 64 'b')]) baseProfile) == "exporter.executable"
    -- JSON profile controls (docs/contracts/U3-codecs.md J3–J4; the blind suite is TestsU3).
  , check "json: members sorted, canonical text, jq escapes" fun _ =>
      (match decode "{\"b\":1,\"a\":[true,null,\"\\u007f/\\ud83d\\ude00\"]}".toUTF8 with
        | .ok v => (print v).data.toList ==
            "{\"a\":[true,null,\"\\u007f/😀\"],\"b\":1}".toUTF8.data.toList
        | .error _ => false),
    check "json: precedence — depth before syntax, syntax before caps + duplicates" fun _ =>
      let rep (n : Nat) (s : String) := String.join (List.replicate n s)
      errorOf ("x" ++ rep 33 "[") == some .tooLarge &&
        errorOf ("\"" ++ rep 33 "[") == some .malformed &&
        errorOf ("\"" ++ rep 65537 "a" ++ "\"x") == some .malformed &&
        errorOf ("{\"a\":\"" ++ rep 65537 "a" ++ "\",\"a\":1}") == some .tooLarge &&
        errorOf "{\"a\":1,\"\\u0061\":2}" == some .duplicateKey,
    check "json: integers ±(2^53 − 1) only, no -0 / 01 / 1.0 / 1e0" fun _ =>
      (match decode "-9007199254740991".toUTF8 with
        | .ok v => v == .int (-9007199254740991)
        | .error _ => false) &&
        ["9007199254740992", "-0", "01", "1.0", "1e0", "+1"].all fun t =>
          errorOf t == some .malformed
  ].mapM id
  let failed := (results.filter (!·.ok)).length
  match results.foldl (fun acc r => if r.ms ≥ acc.ms then r else acc) ⟨"", true, 0⟩ with
  | slowest => IO.println s!"slowest: {slowest.name} ({slowest.ms} ms)"
  IO.println s!"tests: {results.length - failed} passed, {failed} failed"
  return failed.toUInt32
