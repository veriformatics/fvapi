---
paths:
  - "prototype/fvapi/**"
---

# fvapi prototype

- Repo is public ⇒ library content (entries, proofs, study names, theorem text from private sources) never enters git, history included: entry metadata lives in gitignored `prototype/fvapi/seed.local.json`; fixtures stay synthetic or public-fva. Scan before commit: `git log -p origin/main..HEAD | rg -i '<study/theorem fingerprints>'` → 0.
- `deploy.sh` code sync runs `--delete` (retired files must leave vflab); the store sync must not: vflab builds checkers into `/srv/data/fvapi/checkers/` and appends `demand.jsonl` + `answers.jsonl` there.
- Live catalog order is alphabetical ⇒ the only checker (`vf.contrast-2x2`) sorts last; UI + client pick the checker by `check != null`, never by position. The mock serves 3 entries; vflab is what the user sees ⇒ re-screen UI changes on vflab.
- `seed.py` resolves a statement by its full name = enclosing `namespace` stack + written name; a missing name raises (a short-name fallback once published a wrong name).
- Client re-check trusts its own axiom allowlist (`--axioms` > `FVAPI_AXIOMS` > Lean's 3 standard); a bundle's `expect_axioms` is displayed, never trusted.
- Run the CLI on vflab via `bash prototype/fvapi/fvapi-on-vflab.sh <subcommand>` (non-interactive SSH lacks uv/lean on PATH).
