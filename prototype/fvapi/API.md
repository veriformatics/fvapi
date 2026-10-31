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
- `source` = `{repo, commit, paths[]}`; `licence` = `{spdx, third_party[]: {name, spdx, source}, terms?}`. The server adds `terms = "provisional: internal evaluation only; final terms set before outside delivery"` when `spdx` starts with `LicenseRef-Veriformatics`, including catalog detail, lookup entries and bundle manifests. This provisional notice does not change third-party licences.
- `closure[]` = `{path, sha256, bytes}` — files the bundle delivers.
- `replay` = `{status: real | recorded, command, expect_axioms[], transcript | null, note}`. `recorded` = PROTOTYPE stub: transcript copied from an earlier run at `source.commit`, not re-run by fvapi.
- `check` = `{input_schema, example_input, exit_codes, recheck}` | `null` — present on entries the server can run on caller input. `recheck` = `{build: [[argv]…], run: [argv with literal "{input}"]}`, run in the extracted bundle dir with `LEAN_PATH` = bundle dir + `lean --print-libdir`; the client's `--recheck` uses it alone (no entry file names in client code).

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

Lookup match: `spec_id` = entry `id`; `artifact_sha256` = `subject.artifact.sha256`; `statement` = whitespace-normalised equality with any `statements[].text`. All supplied keys must match the same entry. A key matching nothing, or keys matching different entries → 404 miss + demand log. `detail` explains each key's match in plain words; `mismatch[]` = `{key, value, matched_entry: <id> | null}` for each supplied key (`lookup-conflict.json`). Shared artifact/statement values may match several entries: a hit requires an entry common to all keys; the first catalog entry in that intersection wins. `matched_entry` names the first catalog match for that key; `detail` lists all matches. `matched_on` on hits stays the first supplied key (compatibility), with all keys checked.

Checks: server runs the entry's compiled checker on the input (temp dir, 10 s timeout, CPU only) → `verdict` (`accept|reject`), raw checker `output` JSON, `exit_code`, `elapsed_ms`, `ran_on`, plus `recheck` = how the caller re-runs the same checker locally from the bundle.

## Client (`fvapi` CLI)

`fvapi [--api URL] catalog | show ID | lookup [--spec ID] [--sha256 H] [--statement TEXT] | fetch ID -o DIR | replay DIR [--axioms a,b,c] | check ID INPUT.json [--recheck] [--axioms a,b,c]`
- `lookup`: supply at least one key. All supplied keys must match the same entry.
- `show` + `replay`: print `licence.terms` when present.
- `replay DIR`: verify every closure sha256 vs manifest → statement text present byte-identical at `file:line` → `real`: run `replay.command` in DIR, parse `#print axioms` lines, require an audit for every statement and every reported axiom in the **client-owned allowlist** → PASS/FAIL table, rc 0/1. Default allowlist = `{propext, Classical.choice, Quot.sound}`. `--axioms a,b,c` replaces it; otherwise `FVAPI_AXIOMS` replaces it when set. An empty override allows no axioms. A disallowed axiom → FAIL rc 1 naming it. The bundle's `expect_axioms` prints as `bundle declares: …` only; it never widens the client's list. `recorded`: print `RECORDED (not re-run)` + transcript, rc 3.
- `check --recheck`: server verdict → fetch bundle → the same proof replay + axiom audit as `replay`, with `--axioms` > `FVAPI_AXIOMS` > default → on audit pass, build the checker locally + re-run it on the same input. Audit pass + identical local/server verdict JSON → rc 0; audit failure or disagreement → rc 1. Audit failure names the failing check/axiom and stops before the checker runs. Table + `--json` output include the audit and the checker comparison when run; a checker build/run error retains the audit report. Both stages use the same host or container context.
- `replay DIR --container [IMAGE]` and `check ID INPUT.json --recheck --container [IMAGE]`: run Lean/checker commands with rootless podman, no network or home mount, in a temporary bundle copy; host-side hashes, statements and replay axiom judgments stay unchanged. Default image = `fvapi-recheck:lean-4.35.0`, built locally with `bash prototype/fvapi/recheck/build.sh` (Lean core + Std; no Mathlib, recorded fva entries stay recorded); registry publication needs confirmation.
- PROTOTYPE shortcut: without `--container`, replay runs `lean` unsandboxed (bundle = our own entry). IMPLEMENT: Comparator-style sandbox.
