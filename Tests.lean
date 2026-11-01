import Fvapi

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
