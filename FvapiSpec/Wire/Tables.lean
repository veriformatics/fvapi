import Fvapi.Wire.Schema

/-! Reviewed instances, in `docs/api.md` order. Kept separate from executable instances. -/
namespace FvapiSpec.Wire

open Fvapi.Wire

private def s := Schema.scalar
private def r (n : String) (t : Schema) : Field := (n, true, t)
private def o (n : String) (t : Schema) : Field := (n, false, t)
private def enum (xs : List String) := s (.oneOf xs)
private def arr (lo hi : Nat) (t : Schema) := Schema.array lo hi t
private def rec (fs : List Field) (rs : List Rule := []) := Schema.record fs rs

-- Records (§ Wire types).
def entryRef := rec [r "id" (s .ident), r "revision" (s .pos)]
def rowState := enum ["queued", "being_proved", "added", "declined"]
def rowRef := rec [r "id" (s .token), r "state" rowState]
def keys := rec [o "spec_id" (s .ident), o "artifact_sha256" (s .sha256),
  o "statement_digest" (s .digest)]
def bundleRef := rec [r "sha256" (s .sha256), r "path" (s (.text 1 128)),
  r "packed_bytes" (s .pos), r "unpacked_bytes" (s .pos)] [.path "sha256" "path"]
def subject := rec [r "name" (s (.text 1 256)), o "artifact_sha256" (s .sha256)]
def target := rec [r "spec_id" (s .ident), r "statement_digest" (s .digest),
  r "module" (s .leanName), r "declaration" (s .leanName)]
def coverage := enum ["full", "partial"]
def checker := rec [r "spec_id" (s .ident), r "declaration" (s .leanName), r "coverage" coverage]
def entrySummaryFields : List Field := [r "id" (s .ident), r "revision" (s .pos),
  r "title" (s (.text 1 256)), r "kind" (s .ident), r "claim" (s (.text 1 1024)),
  r "subject" subject, r "targets" (arr 1 256 target), r "toolchain" (s .label),
  r "licence_spdx" (s .spdx), o "terms" (s (.text 1 1024)), r "has_checker" (s .bool)]
def entrySummary := rec entrySummaryFields
def entryRevision := rec (entrySummaryFields ++ [o "checker" checker, r "bundle" bundleRef,
  r "admitted_ms" (s .nat)]) [.presenceBool "checker" "has_checker"]
def matchesWithPage (first : Bool) := rec [r "count" (s .nat), r "items" (arr 0 1000 entryRef),
  o "next_cursor" (s .cursor)] [.page "count" "items" "next_cursor" first]
def matchesRecord := matchesWithPage false
def firstMatchesRecord := matchesWithPage true
def keyMatch := rec [r "key" (enum ["spec_id", "artifact_sha256", "statement_digest"]),
  r "value" (s (.text 1 128)), r "matched" (arr 0 100 entryRef), r "matched_count" (s .nat),
  o "next_cursor" (s .cursor)] [.keyValue, .page "matched_count" "matched" "next_cursor" true]
def certificate := rec [r "export_sha256" (s .sha256), r "path" (s (.text 1 128))]
  [.path "export_sha256" "path"]
def verification := Schema.tagged "status" [
  ("kernel_certificate", rec [r "status" (enum ["kernel_certificate"]),
    r "label" (enum ["kernel certificate"]), r "certificate" certificate]),
  ("compiled_evaluation", rec [r "status" (enum ["compiled_evaluation"]),
    r "label" (enum ["compiled evaluation (trusts the Lean compiler)"])]),
  ("failed", rec [r "status" (enum ["failed"]), r "label" (enum ["verification failed"])])]
def verdict := enum ["accept", "reject"]
def attempt := rec [r "number" (s .pos),
  r "state" (enum ["active", "released", "expired", "closed"]),
  r "claimed_ms" (s .nat), r "expires_ms" (s .nat), o "ended_ms" (s .nat)]
  [.presenceString "ended_ms" "state" "active" false]
def rowWithAttempts (maximum : Nat) (first : Bool) := rec [
  r "id" (s .token), r "revision" (s .pos), r "seq" (s .nat),
  r "origin" (enum ["request", "miss"]), r "state" rowState, r "keys" keys,
  o "statement" (s .source), o "note" (s (.text 0 65536)), r "count" (s .pos),
  r "attempt_count" (s .nat), r "attempts" (arr 0 maximum attempt),
  o "attempts_next_cursor" (s .cursor), o "entry_revision" entryRef,
  o "reason" (s (.text 1 4096)), r "created_ms" (s .nat), r "updated_ms" (s .nat)]
  [.page "attempt_count" "attempts" "attempts_next_cursor" first,
    .presenceString "entry_revision" "state" "added" true,
    .presenceString "reason" "state" "declined" true, .rowOrigin]
-- Embedded rows start at the newest attempt; row GET can carry a later page.
def row := rowWithAttempts 1000 false
def embeddedRow := rowWithAttempts 100 true
def kernelStatus := rec [
  r "name" (enum ["leanchecker", "leanchecker-paranoid", "lean4lean", "nanoda", "con-leche",
    "con-ron"]), r "lineage" (enum ["lean", "nanoda", "con"]),
  r "status" (enum ["accept", "reject", "decline", "crash", "timeout"]),
  o "feature" (s (.text 0 65536))]
  [.lineage, .presenceString "feature" "status" "decline" true]
def receipt := rec [r "build" (s .label), r "verification_profile" (s .profileId),
  r "comparator" (s .label), r "kernels" (arr 1 16 kernelStatus), r "at_ms" (s .nat)]
def answerCommon : List Field := [r "id" (s .token), r "at_ms" (s .nat), r "caller_id" (s .token)]
def answer := Schema.tagged "operation" [
  ("lookup", rec (answerCommon ++ [r "operation" (enum ["lookup"]),
    r "outcome" (enum ["hit", "miss"]), r "keys" keys, o "entry" entryRef])
    [.keysNonempty "keys", .presenceString "entry" "outcome" "hit" true]),
  ("check", rec (answerCommon ++ [r "operation" (enum ["check"]), r "entry" entryRef,
    r "input_sha256" (s .sha256), r "verdict" verdict, r "verification" verification,
    r "coverage" coverage]) [])]
def admissionCause := enum ["challenge_mismatch", "forbidden_axiom", "kernel_missing",
  "kernel_rejected", "kernel_crashed", "kernel_timeout", "unnamed_unsupported",
  "insufficient_independent_kernels", "profile_mismatch", "kernel_identity_mismatch",
  "export_failed", "comparator_error", "input_mismatch", "package_mismatch", "invalid_package",
  "revision_exists", "missing_challenge"]

def featuresField : Field := o "required_features" (arr 0 32 (s .ident))
def responseRecord (fs : List Field) (rs : List Rule := []) : Schema :=
  rec (fs ++ [featuresField]) (rs ++ [.uniqueStrings "required_features"])

def withFeatures : Schema → Schema
  | .record fs rs => responseRecord fs rs
  | other => other

def errorBody (codes : List String) (extra : List Field := [])
    (rules : List Rule := []) : Schema :=
  responseRecord ([r "error" (enum codes), r "detail" (s (.text 0 4096))] ++ extra) rules

def requestPackage := rec [r "sha256" (s .sha256), r "path" (s .absPath)]
def requestBody := rec [r "statement" (s .source), o "artifact_sha256" (s .sha256),
  o "note" (s (.text 0 65536)), o "idempotency_key" (s .token)]
def admitBody := rec [o "row" (s .token), r "package" requestPackage]

private def q (name : String) (kind : Scalar) (required : Bool := false) : QueryField :=
  { name, kind, required }
private def limit : QueryField := ⟨"limit", .boundedNat 1 1000, false, some "100"⟩
private def paging : List QueryField := [q "cursor" .cursor, limit]
private def ok (status : Nat) (schema : Schema) : ResponseTable :=
  { status, schema := withFeatures schema }
private def err (status : Nat) (codes : List String) (extra : List Field := [])
    (rules : List Rule := []) : ResponseTable :=
  { status, schema := errorBody codes extra rules }

def commonErrors (route : Route) : List ResponseTable :=
  [err 400 (["malformed", "duplicate_key", "unknown_key"] ++
    if route = .lookup then ["empty_query", "unsupported"] else [])] ++
  (if route = .health then [] else [err 401 ["unauthorized"]]) ++
  [err 413 ["too_large"], err 500 ["internal"], err 503 ["busy"]]

-- Routes (§ Routes): each row carries request mode and status-indexed response mode.
def reviewedTable : Route → RouteTable
  | .health => ⟨[], .none, rec [], [ok 200 (rec [r "status" (enum ["ok"]),
      r "version" (s .label), r "toolchain" (s .label), r "profile" (s .profileId),
      r "catalog_revision" (s .nat)])] ++ commonErrors .health⟩
  | .me => ⟨[], .none, rec [], [ok 200 (rec [r "caller_id" (s .token)])] ++ commonErrors .me⟩
  | .catalog => ⟨paging, .none, rec [], [ok 200 (rec [r "catalog_revision" (s .nat),
      r "entries" (arr 0 1000 entrySummary), o "next_cursor" (s .cursor)])] ++
      commonErrors .catalog⟩
  | .entry => ⟨[q "revision" .pos], .none, rec [],
      [ok 200 entryRevision, err 404 ["unknown_entry"]] ++ commonErrors .entry⟩
  | .lookup => ⟨[limit], .json, keys, [ok 200 (rec [r "outcome" (enum ["hit"]),
      r "entry" (s .ident), r "revision" (s .pos), r "bundle" bundleRef,
      r "other_matches" firstMatchesRecord]), err 404 ["miss"]
      [r "keys" (arr 1 3 keyMatch), r "row" rowRef] [.uniqueField "keys" "key"]] ++
      commonErrors .lookup⟩
  | .matches => ⟨[q "cursor" .cursor true, limit], .none, rec [],
      [ok 200 matchesRecord] ++ commonErrors .matches⟩
  | .bundle => ⟨[], .none, rec [], [⟨200, .bytes, s .any⟩,
      err 404 ["unknown_bundle"]] ++ commonErrors .bundle⟩
  | .check => ⟨[q "spec" .ident true, q "revision" .pos true], .bytes, s .any,
      [ok 200 (rec [r "verdict" verdict, r "output" (s .any), r "input_sha256" (s .sha256),
        r "verification" verification, r "coverage" coverage, r "entry" (s .ident),
        r "revision" (s .pos), r "bundle" bundleRef]), err 404 ["unknown_entry"],
        err 409 ["no_checker", "unknown_entry"]] ++ commonErrors .check⟩
  | .request => ⟨[], .json, requestBody,
      [ok 202 (rec [r "row" rowRef])] ++ commonErrors .request⟩
  | .rows => ⟨q "state" (.oneOf ["queued", "being_proved", "added", "declined"]) :: paging,
      .none, rec [], [ok 200 (rec [r "rows" (arr 0 1000 embeddedRow),
        o "next_cursor" (s .cursor)])] ++ commonErrors .rows⟩
  | .changes => ⟨[q "since" .nat true, limit], .none, rec [],
      [ok 200 (rec [r "rows" (arr 0 1000 embeddedRow), r "last_seq" (s .nat), r "more" (s .bool)]
        [.changes])] ++ commonErrors .changes⟩
  | .row => ⟨[q "attempt_cursor" .cursor, limit], .none, rec [],
      [ok 200 row, err 404 ["unknown_row"]] ++ commonErrors .row⟩
  | .claim => ⟨[], .json, rec [], [ok 200 embeddedRow, err 404 ["unknown_row"],
      err 409 ["bad_transition"]] ++ commonErrors .claim⟩
  | .release => ⟨[], .json, rec [], [ok 200 embeddedRow, err 404 ["unknown_row"],
      err 409 ["bad_transition"]] ++ commonErrors .release⟩
  | .decline => ⟨[], .json, rec [r "reason" (s (.text 1 4096))],
      [ok 200 embeddedRow, err 404 ["unknown_row"], err 409 ["bad_transition"]] ++
      commonErrors .decline⟩
  | .resolve => ⟨[], .json, rec [r "statement" (s .source)],
      [ok 200 embeddedRow, err 404 ["unknown_row"], err 409 ["bad_transition"]] ++
      commonErrors .resolve⟩
  | .answers => ⟨paging, .none, rec [], [ok 200 (rec [r "answers" (arr 0 1000 answer),
      o "next_cursor" (s .cursor)])] ++ commonErrors .answers⟩
  | .admit => ⟨[], .json, admitBody, [ok 200 (rec [r "entry" (s .ident), r "revision" (s .pos),
      r "admission" receipt]), err 404 ["unknown_row"], err 422 ["not_admitted"]
      [r "statuses" (arr 0 16 kernelStatus), r "causes" (arr 1 32 admissionCause)]] ++
      commonErrors .admit⟩

-- Internal failure → route-valid status/code (§ Routes + W2).
def reviewedError (route : Route) : Failure → Option Error
  | .malformed => some ⟨400, "malformed"⟩
  | .duplicateKey => some ⟨400, "duplicate_key"⟩
  | .unknownKey => some ⟨400, "unknown_key"⟩
  | .unauthorized => if route = .health then none else some ⟨401, "unauthorized"⟩
  | .tooLarge => some ⟨413, "too_large"⟩
  | .internal => some ⟨500, "internal"⟩
  | .busy => some ⟨503, "busy"⟩
  | .emptyQuery => if route = .lookup then some ⟨400, "empty_query"⟩ else none
  | .unsupportedDigest => if route = .lookup then some ⟨400, "unsupported"⟩ else none
  | .lookupMiss => if route = .lookup then some ⟨404, "miss"⟩ else none
  | .missingEntry => if route = .entry ∨ route = .check then
      some ⟨404, "unknown_entry"⟩ else none
  | .missingBundle => if route = .bundle then some ⟨404, "unknown_bundle"⟩ else none
  | .missingRow => if route ∈ [.row, .claim, .release, .decline, .resolve, .admit] then
      some ⟨404, "unknown_row"⟩ else none
  | .noChecker => if route = .check then some ⟨409, "no_checker"⟩ else none
  | .checkerBindingMismatch => if route = .check then some ⟨409, "unknown_entry"⟩ else none
  | .badTransition => if route ∈ [.claim, .release, .decline, .resolve] then
      some ⟨409, "bad_transition"⟩ else none
  | .notAdmitted => if route = .admit then some ⟨422, "not_admitted"⟩ else none

end FvapiSpec.Wire
