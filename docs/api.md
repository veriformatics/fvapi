# fvapi API v1 — interface reference (agent-read; binding through `.agent/spec.md` `Decisions` → `Interface`)

Scope this phase: library lookups, bundles, existing checkers, new-proof requests as rows; one founder caller.

## Transport + common rules

- HTTPS through Caddy on vflab (internal CA, pinned by the client) → `fvapi serve` on loopback. HTTP/1.1, keep-alive. Routes under `/v1/`.
- Auth: `Authorization: Bearer fvapi_<id>_<secret>` on every route except `GET /v1/health`; missing or wrong → 401 `unauthorized`; the body is never read before auth.
- JSON bodies follow the fvapi JSON profile: UTF-8, duplicate keys rejected, integers only (|n| < 2^53), depth ≤ 32, strings ≤ 64 KiB. Check inputs are exact bytes (≤ 64 KiB); bundles are archive bytes. Over a cap → 413 `too_large`.
- Every JSON response is one object; errors = `{"error": <code>, "detail": <text>}`.
- Lists page by cursor: `?cursor=<opaque>&limit=<n>` (default 100, max 1000; byte-bounded); a page carries `next_cursor` until the last page; pages read one store generation.
- Compatibility: v1 changes are additive; a response may name `required_features[]`; a client that does not know one fails closed with outcome `unsupported`.
- Private-library entries and bundles carry `terms: "provisional: internal evaluation only"`.

## Outcomes (shared by HTTP, CLI, MCP, `Fvapi.Client`)

| Operation | Outcome field(s) | Values |
|---|---|---|
| lookup | `outcome` | `hit` · `miss` |
| caller-side verify | `verdict` + `causes[]` | `pass` · `fail` |
| check | `verdict` · `verification.status` · `coverage` | `accept` \| `reject` · `kernel_certificate` \| `compiled_evaluation` \| `failed` · `full` \| `partial` |
| request | `row.state` | `queued` |
| any | `error` | `unauthorized` `malformed` `duplicate_key` `unknown_key` `empty_query` `unknown_entry` `unknown_bundle` `unknown_row` `miss` `no_checker` `bad_transition` `not_admitted` `too_large` `busy` `unsupported` `internal` |

A `compiled_evaluation` status always carries the label `compiled evaluation (trusts the Lean compiler)`; a `partial` coverage is never reported as full success (CLI exit 7); `verification.status: failed` is a verification failure (CLI exit 1), never a reject.

## Routes

| Route | Request | Success | Errors / notes |
|---|---|---|---|
| `GET /v1/health` | — | 200 `{status, version, toolchain, profile, catalog_revision}` | no auth |
| `GET /v1/catalog` | paged | 200 `{catalog_revision, entries[], next_cursor?}`; summary = `id revision title kind claim subject targets[] toolchain licence_spdx terms? has_checker` | |
| `GET /v1/entries/{id}[?revision=r]` | — | 200 full entry revision | 404 `unknown_entry` |
| `POST /v1/lookup` | `{spec_id?, artifact_sha256?, statement_digest?}`, ≥ 1 key | 200 `{outcome:"hit", entry, revision, bundle:{sha256, path, packed_bytes, unpacked_bytes}, other_matches:{count, items[]:{id, revision}, next_cursor?}}` | 404 `{error:"miss", detail, keys[]:{key, value, matched[]}, row}`; 400 `empty_query` · `malformed` · `duplicate_key` · `unknown_key` |
| `GET /v1/lookup/matches?cursor=` | — | 200 next page of `other_matches` | cursor from a lookup answer |
| `GET /v1/bundles/{sha256}` | — | 200 deterministic archive | 404 `unknown_bundle`; the client checks sha256 before use |
| `POST /v1/check/{id}?spec=<spec_id>&revision=<r>` | exact input bytes | 200 `{verdict, output, verification:{status, label, certificate?:{export_sha256, path}}, coverage, entry, revision, bundle}` | 409 `no_checker`; 409 `unknown_entry` when `spec` + `revision` do not name a checker the entry carries |
| `POST /v1/requests` | `{statement, artifact_sha256?, note?, idempotency_key?}` (`statement` = Lean source of the wanted theorem) | 202 `{row:{id, state:"queued"}}` | same `idempotency_key` → same row |
| `GET /v1/rows[?state=]` | paged | 200 `{rows[], next_cursor?}`; row = `{id, origin: request\|miss, keys, statement?, count, state, attempts[], entry_revision?, reason?, seq}` | |
| `GET /v1/rows/changes?since=<seq>[&limit=n]` | — | 200 `{rows[], last_seq, more}` (paged like every list) | incremental mirror; `more: true` → call again with `since=last_seq` |
| `GET /v1/rows/{id}` | — | 200 row | 404 `unknown_row` |
| `POST /v1/rows/{id}/claim` · `/release` · `/decline` · `/resolve` | `{}` · `{}` · `{reason}` · `{statement}` | 200 row | 409 `bad_transition`; a claim expires and can be released |
| `GET /v1/answers` | paged | 200 answer history (lookups + checks) for the console recorder | |
| `POST /v1/admin/admit` | `{row?, package:{sha256, path}}` | 200 `{entry, revision, admission}` | 422 `{error:"not_admitted", statuses}`; kernel policy alone, against the challenge recorded in the row or entry |

## Ranking (several matches)

Candidates = entries whose proven targets satisfy every supplied key. Order: coverage first (A before B when A's proven-target set strictly contains B's), then newest revision, then entry id. The first candidate is the answer; the rest are `other_matches`.

## CLI (`fvapi`)

`catalog` · `show ID` · `lookup [--spec ID] [--sha256 H] [--digest D]` · `fetch ID|SHA -o DIR` · `verify DIR --challenge FILE [--axioms a,b,c]` · `check ID INPUT --spec S --revision R [--verify] [--require-certificate]` · `request FILE [--sha256 H] [--note T]` · `digest FILE [THEOREM]` · `rows [sync|claim ID|release ID|decline ID REASON|resolve ID FILE]` · `me` · `mcp` · `serve` · `admin admit …`.

Exit codes: 0 success (hit, PASS, accept with `coverage: full`) · 1 verification FAIL (caller-side `fail`, `verification.status: failed`, or `--require-certificate` with a `compiled_evaluation` answer) · 2 usage · 3 miss · 4 checker reject with `coverage: full` · 5 transport or server error · 6 unsupported (unknown required feature) · 7 partial (`coverage: partial`, any verdict) — a partial answer never maps to a success code.

## MCP (`fvapi mcp`, stdio JSON-RPC)

Tools: `lookup`, `fetch_and_verify`, `check`, `request`, `digest` — same semantics and outcome fields as the CLI; verification runs on the caller's machine.
