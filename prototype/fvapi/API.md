# fvapi prototype — API v0 contract (seam for server, client, console)

Disposable PROTOTYPE. Shape = what the user inspects; IMPLEMENT redesigns freely.

- Host = vflab, `http://192.168.40.241:8441` (LAN only, no auth). Store = `/srv/data/fvapi/` (`FVAPI_STORE`).
- Principle: fvapi sells search, never trust ⇒ every answer carries what the caller needs to re-check it (statement text, proof closure files + sha256, replay command, expected axioms, licence). Server verdicts are leads; the client re-runs.
- No LLM at request time: lookups, proved checkers, CPU automation. A lookup miss → logged as demand, never routed to an agent.
- Library content (seed entries, proofs) = private ⇒ never committed; `seed.py` copies it from local sources into the store.
- Every JSON response = one object; errors = `{"error": <code>, "detail": <text>}` + 4xx/5xx. Fixtures under `fixtures/v0/` = the exact shape per route (values illustrative; server returns real values).

## Entry (catalog item)

Fields (`fixtures/v0/catalog-vf.contrast-2x2.json`):
- `id` — `<source>.<slug>`; `title`; `kind` ∈ `checker | version-proof | refutation | relation`; `claim` = one plain sentence of what the proof establishes.
- `statements[]` = `{name, file, line, text}` — the Lean statement(s) the caller must read + match (Comparator-style challenge).
- `subject` = `{name, version, artifact: {name, sha256, bytes} | null}` — version proofs are keyed by artifact sha256.
- `toolchain` (`leanprover/lean4:v4.35.0`), `requires[]` (`Std` | `mathlib@v4.35.0` | `fva@<sha>`).
- `source` = `{repo, commit, paths[]}`; `licence` = `{spdx, third_party[]: {name, spdx, source}}`.
- `closure[]` = `{path, sha256, bytes}` — files the bundle delivers.
- `replay` = `{status: real | recorded, command, expect_axioms[], transcript | null, note}`. `recorded` = PROTOTYPE stub: transcript copied from an earlier run at `source.commit`, not re-run by fvapi.
- `check` = `{input_schema, example_input, exit_codes}` | `null` — present on entries the server can run on caller input.

## Routes

| Method + path | Body | 200 | Other |
|---|---|---|---|
| `GET /v0/health` | — | `health.json` | — |
| `GET /v0/catalog?kind=&q=` | — | `catalog.json` (`entries[]` = summaries: `id title kind claim subject toolchain replay_status licence_spdx`) | — |
| `GET /v0/catalog/{id}` | — | full entry | 404 `unknown_entry` |
| `POST /v0/lookup` | `{spec_id?, artifact_sha256?, statement?}` (≥1 key) | `lookup-hit.json` | 404 `lookup-miss.json` (miss logged); 422 `empty_query` |
| `GET /v0/bundles/{id}.tar.gz` | — | gzip tar: `manifest.json` (= entry) + closure files at their `path` | 404 |
| `POST /v0/checks/{id}` | caller input JSON (entry's `check.input_schema`) | `check-accept.json` / `check-reject.json` (a reject is still 200) | 404; 409 `no_checker` (entry has `check: null`); 413 > 64 KiB |
| `GET /v0/demand` | — | `demand.json` (misses newest first + `by_key` counts) | — |
| `GET /v0/answers` | — | `answers.json` (answer log newest first: lookups + checks) | — |
| `GET /` | — | HTML index of console variants | — |
| `GET /console/{variant}/` | — | static files of `console/variants/{variant}/` | 404 |

Lookup match: `spec_id` = entry `id`; `artifact_sha256` = `subject.artifact.sha256`; `statement` = whitespace-normalised equality with any `statements[].text`. First hit wins.

Checks: server runs the entry's compiled checker on the input (temp dir, 10 s timeout, CPU only) → `verdict` (`accept|reject`), raw checker `output` JSON, `exit_code`, `elapsed_ms`, `ran_on`, plus `recheck` = how the caller re-runs the same checker locally from the bundle.

## Client (`fvapi` CLI)

`fvapi [--api URL] catalog | show ID | lookup (--spec ID | --sha256 H | --statement TEXT) | fetch ID -o DIR | replay DIR | check ID INPUT.json [--recheck]`
- `replay DIR`: verify every closure sha256 vs manifest → statement text present byte-identical at `file:line` → `real`: run `replay.command` in DIR, parse `#print axioms` lines, every axiom ∈ `expect_axioms` → PASS/FAIL table, rc 0/1; `recorded`: print `RECORDED (not re-run)` + transcript, rc 3.
- `check --recheck`: server verdict, then fetch + build the checker locally + re-run it on the same input; agree → rc 0, disagree → rc 1.
- PROTOTYPE shortcut: replay runs `lean` unsandboxed (bundle = our own entry). IMPLEMENT: Comparator-style sandbox.
