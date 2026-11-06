# fvapi API v1 — interface reference (agent-read; binding through `.agent/spec.md` `Decisions` → `Interface`)

Scope this phase: library lookups, bundles, existing checkers, new-proof requests as rows; one founder caller.

## Transport + common rules

- HTTPS through Caddy on vflab (internal CA, pinned by the client) → `fvapi serve` on loopback. HTTP/1.1, keep-alive. Routes under `/v1/`.
- Auth: `Authorization: Bearer fvapi_<id>_<secret>` on every route except `GET /v1/health`; missing or wrong → 401 `unauthorized`; the body is never read before auth.
- JSON bodies use the profile specified by `docs/contracts/U3-codecs.md` J1–J3: UTF-8 scalar strings, decoded-name duplicate rejection, depth ≤ 32 including the root container, ≤ 65,536 decoded UTF-8 bytes per string or key. Integer tokens are `0` or an optional minus followed by a nonzero decimal digit and further decimal digits, magnitude ≤ 9007199254740991. Negative zero, fractions, exponents, excessive integers, invalid UTF-8, unpaired surrogate escapes, a leading BOM and trailing non-whitespace are syntax failures. Error priority: lexical depth > 32 → 413 `too_large`; syntax failure → 400 `malformed`; an over-cap decoded string or key → 413 `too_large`; a duplicate decoded key → 400 `duplicate_key`; then route validation. Check inputs are exact bytes (≤ 65,536); content-addressed transfers (`/v1/bundles/`) are exact bytes, the typed reference distinguishing an archive from a certificate export; these byte routes bypass the JSON codec. Over a cap → 413 `too_large`.
- Every JSON response is one object; errors = `{"error": <code>, "detail": <text>}`.
- Lists page by cursor: `?cursor=<opaque>&limit=<n>` (default 100, max 1000; byte-bounded); a page carries `next_cursor` until the last page; a cursor list's pages read one store generation (`rows/changes` = a sequence feed, § Routes). Query strings carry unreserved bytes alone (`[A-Za-z0-9._~-]`), never percent-escapes (§ Decision order).
- Compatibility: v1 changes are additive; a response may name `required_features[]`; a client that does not know one fails closed with outcome `unsupported`.
- Private-library entries and bundles carry `terms: "provisional: internal evaluation only"`.

## Outcomes (shared by HTTP, CLI, MCP, `Fvapi.Client`)

| Operation | Outcome field(s) | Values |
|---|---|---|
| lookup | `outcome` | `hit` · `miss` |
| caller-side verify | `verdict` + `causes[]` | `pass` · `fail` |
| check | `verdict` · `verification.status` · `coverage` | `accept` \| `reject` · `kernel_certificate` \| `compiled_evaluation` \| `failed` · `full` \| `partial` |
| request | `row.state` | `queued` (a repeated `idempotency_key`: its row's current state) |
| any | `error` | `unauthorized` `malformed` `duplicate_key` `unknown_key` `empty_query` `unknown_entry` `unknown_bundle` `unknown_row` `miss` `no_checker` `bad_transition` `not_admitted` `too_large` `busy` `unsupported` `internal` |

Client outcomes `bad_response` + `unsupported`: § Decision order.

A `compiled_evaluation` status always carries the label `compiled evaluation (trusts the Lean compiler)`; a `partial` coverage is never reported as full success (CLI exit 7); `verification.status: failed` is a verification failure (CLI exit 1), never a reject.

## Wire types (exact; reviewed relation `FvapiSpec/Wire.lean`, contract `docs/contracts/U3-codecs.md` W)

Notation: `f: T` required; `f?: T` optional = absent or a `T` — JSON `null` is not absence and belongs to no type below except `any`; `[T]a..b` = array of a…b items; `"s"` = exactly that string; `A | B` = one of. A request record admits no member it does not list; a response record ignores members it does not list, at every level (v1 additive). Byte counts = decoded UTF-8 bytes. Admissibility is a predicate on the complete message: every message is J1 `Valid` as a whole (root-inclusive depth ≤ 32, integer + string bounds, distinct keys).

Scalars:
- `nat` = integer 0…2^53−1 · `pos` = 1…2^53−1 · `ms` = `nat`, Unix time in milliseconds.
- `ident` = 1–128 ASCII bytes: one byte = `[a-z0-9]`; longer = first + last byte `[a-z0-9]`, every byte between `[a-z0-9._-]` (entry ids, spec ids, entry kinds, feature names).
- `sha256` = `[0-9a-f]{64}` · `profile_id` = `"sha256:"` + sha256 · `digest` = tag `":"` sha256, tag = `[a-z0-9]{1,16}`; known tag now: `sd1` (statement digest v1 = `docs/digest-sd1.md`, computed caller-side by `fvapi digest`); a digest is a routing key: equal digests never imply compatible theorems.
- `token` = `[A-Za-z0-9._~-]{1,128}` (row, answer + caller ids, idempotency keys; opaque) · `cursor` = `[A-Za-z0-9_-]{1,1024}` (opaque).
- `label` = printable ASCII 0x21–0x7E, 1–256 bytes · `spdx` = printable ASCII 0x20–0x7E, 1–256 bytes, no leading or trailing space.
- `text[a,b]` = any string of a…b bytes · `source` = 1–65,536 bytes, no U+0000, ≥ 1 scalar other than space, tab, LF, CR (Lean source) · `lean_name` = 1–1,024 bytes, no U+0000–U+001F or U+007F · `abs_path` = 1–4,096 bytes, first byte `/`, no U+0000 (lexical types: Lean elaboration + safe path resolution belong to their consumers) · `any` = a J1 value, `null` included, whose placement keeps the complete message `Valid`.
- Every grammar matches the complete string.

Records:
- `EntryRef` = `{id: ident, revision: pos}` · `RowRef` = `{id: token, state: RowState}` · `Keys` = `{spec_id?: ident, artifact_sha256?: sha256, statement_digest?: digest}`.
- `BundleRef` = `{sha256: sha256, path, packed_bytes: pos, unpacked_bytes: pos}`, path = `"/v1/bundles/"` + sha256; names a deterministic archive.
- `Subject` = `{name: text[1,256], artifact_sha256?: sha256}` · `Target` = `{spec_id: ident, statement_digest: digest, module: lean_name, declaration: lean_name}` · `Checker` = `{spec_id: ident, declaration: lean_name, coverage: Coverage}`.
- `EntrySummary` = `{id: ident, revision: pos, title: text[1,256], kind: ident, claim: text[1,1024], subject: Subject, targets: [Target]1..256, toolchain: label, licence_spdx: spdx, terms?: text[1,1024], has_checker: bool}`; kinds admitted now: `theorem`, `checker`, `refutation` (a client accepts any ident).
- `EntryRevision` = EntrySummary's members + `{checker?: Checker, bundle: BundleRef, admitted_ms: ms}`; has_checker ⇔ checker present.
- `Matches` = `{count: nat, items: [EntryRef]0..1000, next_cursor?: cursor}`: one page of a cursor-bound collection; count = the collection's total, constant across its pages. Local rules (W checks): items ≤ count; next_cursor ⇒ items nonempty ∧ items < count; on a first page (`other_matches`) next_cursor ⇔ items < count. Membership, order + completeness across pages = U5. `other_matches` = every match except the hit.
- `KeyMatch` = `{key: "spec_id" | "artifact_sha256" | "statement_digest", value: that key's scalar, matched: [EntryRef]0..100, matched_count: nat, next_cursor?: cursor}`: the first page of every match of that key; matched ≤ matched_count; next_cursor ⇔ matched < matched_count (a first page); later pages read through `matches` (`Matches` with count = matched_count).
- `Verification` = `{status: "kernel_certificate", label: "kernel certificate", certificate: {export_sha256: sha256, path}}` (path = `"/v1/bundles/"` + export_sha256: the exact Lean export bytes, not an archive) | `{status: "compiled_evaluation", label: "compiled evaluation (trusts the Lean compiler)"}` | `{status: "failed", label: "verification failed"}`.
- `RowState` = `"queued" | "being_proved" | "added" | "declined"` · `Coverage` = `"full" | "partial"` · `Verdict` = `"accept" | "reject"`.
- `Attempt` = `{number: pos, state: "active" | "released" | "expired" | "closed", claimed_ms: ms, expires_ms: ms, ended_ms?: ms}`; ended_ms ⇔ state ≠ active (U13 may amend).
- `Row` = `{id: token, revision: pos, seq: nat, origin: "request" | "miss", state: RowState, keys: Keys, statement?: source, note?: text[0,65536], count: pos, attempt_count: nat, attempts: [Attempt]0..1000, attempts_next_cursor?: cursor, entry_revision?: EntryRef, reason?: text[1,4096], created_ms: ms, updated_ms: ms}`. attempts = one page of the row's attempt history, newest first (lists + mutation replies embed the first page, ≤ 100; `row` pages the rest, ≤ 1000); attempts ≤ attempt_count; attempts_next_cursor ⇒ attempts nonempty ∧ attempts < attempt_count; on a first page attempts_next_cursor ⇔ attempts < attempt_count. History order + completeness = U13. entry_revision ⇔ state added; reason ⇔ state declined; origin request ⇒ statement present ∧ count = 1 ∧ keys ∈ {`{}`, `{artifact_sha256}`}; origin miss ⇒ keys nonempty.
- `KernelStatus` = `{name: KernelId, lineage: "lean" | "nanoda" | "con", status: "accept" | "reject" | "decline" | "crash" | "timeout", feature?: text[0,65536]}`; lineage = U2 P1's function of name; feature ⇔ decline, holding the captured text as is (blank included: P1 judges blankness, the diagnostic keeps it).
- `Receipt` = `{build: label, verification_profile: profile_id, comparator: label, kernels: [KernelStatus]1..16, at_ms: ms}` (U8 + U12 may amend).
- `Answer` = `{id: token, at_ms: ms, caller_id: token}` + either `{operation: "lookup", outcome: "hit" | "miss", keys: Keys (nonempty), entry?: EntryRef}` (entry ⇔ hit) or `{operation: "check", entry: EntryRef, input_sha256: sha256, verdict: Verdict, verification: Verification, coverage: Coverage}` (U17 may amend).
- Error body = `{error: code, detail: text[0,4096]}` + its route-specific members below. Any response may carry `required_features?: [ident]0..32` (no repeats) at its root.

## Routes

Route ids name routes in tests + the dev driver. `limit` = pos ≤ 1000, default 100. Query values are their scalar's bytes as written (no percent-escapes); integers use JSON's spelling without `-`. Body modes: JSON = lookup, request, claim, release, decline, resolve, admit; bytes = check; none = every GET.

| Route (id) | Query · body | Success | Route-specific errors |
|---|---|---|---|
| `GET /v1/health` (health) | — | 200 `{status: "ok", version: label, toolchain: label, profile: profile_id, catalog_revision: nat}` | no auth (never 401) |
| `GET /v1/me` (me) | — | 200 `{caller_id: token}` | |
| `GET /v1/catalog` (catalog) | cursor?, limit? | 200 `{catalog_revision: nat, entries: [EntrySummary]0..1000, next_cursor?: cursor}` | |
| `GET /v1/entries/{id}` (entry) | revision?: pos | 200 EntryRevision | 404 `unknown_entry` |
| `POST /v1/lookup` (lookup) | limit? (other_matches page) · Keys, ≥ 1 member | 200 `{outcome: "hit", entry: ident, revision: pos, bundle: BundleRef, other_matches: Matches}` | 400 `empty_query`, `unsupported` (digest tag); 404 `miss` + `{keys: [KeyMatch]1..3 (one per supplied key), row: RowRef}` |
| `GET /v1/lookup/matches` (matches) | cursor (an `other_matches` or `KeyMatch` next_cursor), limit? | 200 Matches: that cursor's collection; total, order + generation stay fixed across its pages | |
| `GET /v1/bundles/{sha256}` (bundle) | — | 200 the exact content-addressed bytes: an archive (BundleRef) or a Lean export (certificate); the client checks sha256 before use and picks the parser from the reference type | 404 `unknown_bundle` |
| `POST /v1/check/{id}` (check) | spec: ident, revision: pos · exact input bytes (≤ 65,536) | 200 `{verdict: Verdict, output: any, input_sha256: sha256, verification: Verification, coverage: Coverage, entry: ident, revision: pos, bundle: BundleRef}`; status failed = the compiled verdict stands unverified (CLI exit 1); a checker that produced no verdict = 500 `internal` | 404 `unknown_entry`; 409 `no_checker`; 409 `unknown_entry` when spec + revision name no checker of the entry |
| `POST /v1/requests` (request) | `{statement: source, artifact_sha256?: sha256, note?: text[0,65536], idempotency_key?: token}` | 202 `{row: RowRef}`: a new row is queued; a repeated idempotency_key with an identical normalized request returns its row as it stands now; the same key with a different request → 400 `malformed` (detail: idempotency_key reused with a different request) | |
| `GET /v1/rows` (rows) | state?: RowState, cursor?, limit? | 200 `{rows: [Row]0..1000, next_cursor?: cursor}` | |
| `GET /v1/rows/changes` (changes) | since: nat, limit? | 200 `{rows: [Row]0..1000, last_seq: nat, more: bool}`: a sequence feed, not a snapshot list — each call reads one committed generation; since is exclusive; rows by increasing seq; last_seq = the last emitted seq (since, when empty); more = that generation holds further changes → call again with since = last_seq; a page with more = true holds ≥ 1 row. W checks within one page: seq strictly increasing, last_seq = the last row's seq when rows is nonempty, more ⇒ rows nonempty; the relation to the request's since + mirror completeness = U13 + the client | |
| `GET /v1/rows/{id}` (row) | attempt_cursor?, limit? (attempts page) | 200 Row with that attempts page (no attempt_cursor = the newest page) | 404 `unknown_row` |
| `POST /v1/rows/{id}/claim` · `/release` (claim, release) | `{}` | 200 Row | 404 `unknown_row`; 409 `bad_transition`; a claim expires and can be released |
| `POST /v1/rows/{id}/decline` (decline) | `{reason: text[1,4096]}` | 200 Row | 404 `unknown_row`; 409 `bad_transition` |
| `POST /v1/rows/{id}/resolve` (resolve) | `{statement: source}` | 200 Row | 404 `unknown_row`; 409 `bad_transition` |
| `GET /v1/answers` (answers) | cursor?, limit? | 200 `{answers: [Answer]0..1000, next_cursor?: cursor}` (lookups + checks, console recorder) | |
| `POST /v1/admin/admit` (admit) | `{row?: token, package: {sha256: sha256, path: abs_path}}` | 200 `{entry: ident, revision: pos, admission: Receipt}`; kernel policy alone, against the challenge recorded in the row or entry | 404 `unknown_row`; 422 `not_admitted` + `{statuses: [KernelStatus]0..16, causes: [AdmissionCause]1..32}` |

AdmissionCause = a U2 P3 cause code | `package_mismatch` (bytes ≠ the supplied sha256) | `invalid_package` (structurally invalid source package) | `revision_exists` (a conflicting publication under an existing entry revision) | `missing_challenge` (the row or entry lacks the independent challenge replay needs); these pre-replay causes may carry no kernel statuses; an unexpected runtime or store failure = 500 `internal`, never a kernel cause (U12 orders the prechecks + publishes nothing on any failure).

Every route also answers 400 `malformed` · `duplicate_key` · `unknown_key`, 401 `unauthorized` (except health), 413 `too_large`, 500 `internal`, 503 `busy`, each with the plain error body.

## Decision order

Server, per request, after U7's routing + framing and authentication (a protected route answers 401 `unauthorized` before reading its body or applying these stages; health is exempt). The first failing stage wins:
1. Query syntax: an absent or empty query = no items. Else split on `&`; every item = exactly one `=` between a nonempty name and a nonempty value, each of bytes `[A-Za-z0-9._~-]`; any malformed item → 400 `malformed` (the whole query is checked first); then a repeated name → 400 `duplicate_key`. No percent-decoding, no `+` conversion (`a=1&a=2&x=%` → `malformed`; `a=1&a=2` → `duplicate_key`).
2. Body by mode: JSON → the J3 outcome (413 `too_large`, 400 `malformed`, 400 `duplicate_key`), then a non-object root → 400 `malformed`; none → empty bytes pass, other bytes → 400 `malformed`; bytes (check) → over 65,536 bytes → 413 `too_large`, else the bytes pass unchanged.
3. A query name the route does not list, or a body member its record does not list (at every record reached through a member of the expected JSON kind) → 400 `unknown_key`.
4. A required member or query value absent, or a present one outside its type → 400 `malformed`.
5. Route rules: lookup without a key → 400 `empty_query`; a digest tag the server does not know → 400 `unsupported`.
These stages yield a normalized typed request. The owning route unit then decides cursor validity (invalid, expired, foreign, or issued before a service restart → 400 `malformed`; cursors are process-local), resource existence, checker binding, row transitions and admission (404 / 409 / 422 per route).

Client, per response (the first failing stage wins):
1. bundle + 200 → the exact bytes, stages 2–4 skipped (hash check + parsing = the client's next obligation). Any other response: a J3 `ok` with an object root, else `bad_response`.
2. `required_features`: a malformed declaration → `bad_response`; a name the client does not know (v1 clients know none) → `unsupported`.
3. The route lists the HTTP status, and the body matches that status's record: the success record, or an error body whose code the route lists for that status → else `bad_response`.
4. The records' cross-member rules → else `bad_response`.

Client outcomes: `bad_response` = a response the wire relation rejects (public code `bad_response`, CLI exit 5; parser diagnostics may ride in `detail`); `unsupported` = an unknown required feature or a well-formed 400 `unsupported` (CLI exit 6); every other well-formed error keeps its documented outcome (`miss` = exit 3).

## Ranking (several matches)

Candidates = entries whose proven targets satisfy every supplied key. Coverage first, then newest revision, then entry id, as a total order: layer 1 = the candidates no other candidate's proven-target set strictly contains; layer k+1 = the same over the candidates left after layers 1…k; within a layer, newest revision first, then lowest entry id. (A pairwise comparator would cycle: A={x,y} beats B={x} by coverage, B beats C={z} and C beats A by recency.) The first candidate is the answer; the rest, in this order, are `other_matches`. Consequence: A ⊋ B ⇒ A precedes B.

## CLI (`fvapi`)

`catalog` · `show ID` · `lookup [--spec ID] [--sha256 H] [--digest D]` · `fetch ID|SHA -o DIR` · `verify DIR --challenge FILE [--axioms a,b,c]` · `check ID INPUT --spec S --revision R [--verify] [--require-certificate]` · `request FILE [--sha256 H] [--note T]` · `digest FILE [THEOREM]` · `rows [sync|claim ID|release ID|decline ID REASON|resolve ID FILE]` · `me` · `mcp` · `serve` · `admin admit …`.

Exit codes: 0 success (hit, PASS, accept with `coverage: full`) · 1 verification FAIL (caller-side `fail`, `verification.status: failed`, or `--require-certificate` with a `compiled_evaluation` answer) · 2 usage · 3 miss · 4 checker reject with `coverage: full` · 5 transport or server error · 6 unsupported (an unknown required feature, or the server's 400 `unsupported`) · 7 partial (`coverage: partial`, any verdict) — a partial answer never maps to a success code. Precedence when several apply to one check answer: 1 (verification failed, or `--require-certificate` unmet) > 7 (partial) > the verdict (0 accept, 4 reject); 5 + 6 arise before any answer exists.

## MCP (`fvapi mcp`, stdio JSON-RPC)

Tools: `lookup`, `fetch_and_verify`, `check`, `request`, `digest` — same semantics and outcome fields as the CLI; verification runs on the caller's machine.
