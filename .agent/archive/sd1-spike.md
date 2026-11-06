# U5 sd1 spike — `statement_digest` rule evidence (archive; `Decisions` → `Statement digest` cites it)

Code + full evidence: local tag `spike-sd1` = f441eba (`spike/sd1/`; branch `wt/builder-34`, kept until U5 close). Frozen check = `CHECK.md` v2.1 (sha256 682582bb…), arms = `ARMS.md` (555c459b…), base 4f99b05; MAIN rulings = `LEAD-DIRECTIVES.txt` 1–17. Selector evidence `SEL.evidence.json` sha256 388deb556f04eb0a6b36bd03d426655da9d5a0650c86fe4d3f98f428e0f27170. Appraisal = scientist-6 (C3 supported; C1, C2, C4, C5, C6 partly); ruling review = consultant-41/42/43 (approve with changes, all applied).

## Environment (all arms; `ENVIRONMENT.md` + `environment/environment.json` hold full identities)

Lean 4.35.0 (compiler eb6cafb, runtime manifest 953aa1e7… = `verify/profile.json`), profile id sha256:4534c7e9…; Mathlib v4.35.0 @ 56a0058 (manifest 6fcb8417…) through the pinned capsule (key dddd0b82…); six kernels + comparator as the verification profile; caller allowlist propext, Classical.choice, Quot.sound. vflab, process-cold + filesystem-warm caches.

## Results (permitted wording)

- Selection: A1 mechanically selected under the recorded check interpretations (G1–G6 + caller budget true); A2 screened out + A3 pruned (never run) at S1 (directive 12, scientist-5) — neither empirically dominated.
- G6: 548,025 declarations hashed in the exact imported environment (548,013 theorems, 12 axioms) — hashing support, not 548,025 qualified re-check paths.
- M2: a fixed stratified 2,000-pair sample of 6,325,104 same-environment directed equal-digest pairs → 1,990 comparator accepts, 3 rejects, 7 unresolved. Design-weighted reject point bounds ≈ 0.15199–0.20275 %; descriptive 95 % envelope ≈ 0.01859–0.89915 % (unresolved assigned both ways). Finite pair-population comparator observations: no workload error, recall or safety probability; comparator accepts ≠ kernel-verified deliveries.
- Cost (digest core, three resident-environment empty-cache census passes): largest p99 0.845727 ms, max 14.842403 ms; startup/import/sort/output excluded, teardown-inclusive per-declaration time unconfirmed. 25 fresh fixture pairs: largest paired RSS delta 4,772 KiB (4.66015625 MiB); largest absolute full-process peak ≈ 6.111 GiB; whole-process wall 0.37–2.54 s. Observed vflab phases, never caller latency, a size-class guarantee or an SLO.
- Conformance: 77 vector cases (committed as `docs/digest-sd1/`) + 172 matching cross-runner manifest rows (G3 CI run 41956342821; vflab manifest sha256 f89b6e61…).

## Qualifications (F1–F7)

- CHECK:32's literal dependency-byte condition unconfirmed: G3 established 172-row manifest equality (MAIN directive 16), not full imported-artifact byte equality; G3's CI was a dedicated manifest workflow, not the product gate or scanners.
- Outer batch envelopes exceeded ENVIRONMENT's 1,800 s wording; per-call criteria stayed separate.
- CHECK:15's root-binding-stop wording vs M2 index 407: kept as unresolved (internal-name binding decoder failure), not a stop.
- 7 binding-unresolved outcomes (6 candidate-axiom roots + 1 internal-name decoder failure) = caller-binding gaps, not digest failures; the root-in-dependency-closure collision class stays unqualified.
- Same-environment M2 cannot estimate cross-environment or cross-release drift (`.agent/deferred.md`).
- Selected-only lookup loses a later compatible answer after a false route (S4 G5: no answer after a bad top pick; explicit alternatives recover it).
- No production encoder proof, host/source stability or A2/A3 comparison follows. The tag keeps committed code + evidence; ignored remote raw artifacts (M2 exports, census streams on vflab) are not retained by it.
