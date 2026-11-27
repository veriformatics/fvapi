---
paths:
  - "tests/store/model/a3-cases.py"
---

# SW-A3 targeted cases (`tests/store/model/a3-cases.py`)

- Run on vflab from the repo root with the blind tree staged at `.lake/blind`:
  `python3 -I tests/store/model/a3-cases.py DRIVER .lake/blind [T1 T2 T3]`; rc 0 = every selected case passed, 1 = a
  case failed (its error printed), 2 = usage. Cases = the `| SW-A3 |` test clauses the blind suite of record leaves
  undriven: T1 = C6 + C10 (model: reload, post-reload coalesce, successor attempt-bearing release), T2 = C7 (pure:
  same-batch stale → valid claim), T3 = C8 (model: a cut before a request's id draw between a claim and a release;
  continue = the uninterrupted serial result). Every batch goes through the blind suite's oracle-checked World.
- A3 is a proved refactor, so the cases pass on pre-A3 drivers too: their credit = the mutants they kill. Firing
  record (lane eaa54d44; mutants = workspace-only patches of the clean tree, frozen in `~/gate/fvapi-a3mut-NAME`):
  clean ad2aba4a + pre-A3 6cdb120e = T1, T2, T3 pass; startpos 6e25d756 (reconstruct
  positions := {}) = T1 FAIL; sealpos 54c0b2fb (sealBatchA3 extends by nothing) = T1 FAIL; oldest 536df21b
  (latestRowA3 = the spine's last) = T1, T2, T3 FAIL; observe faddf094 (observe extends by nothing) = T1 + T3 FAIL
  (the decision's tentative overlay is `observe before proposal ov` too, so the mutant hides a claim's NEW attempt
  position from its own construction check); every other case passes on each mutant.
- Change law: an edit to a3-cases.py, or to the overlay, position or seal code it covers (`Fvapi/Store/A3Overlay.lean`,
  `Fvapi/Store/AttemptPositions.lean`, `sealBatchA3`, `reconstruct`'s positions), reruns it on the clean driver and on
  every mutant: each case still passes clean and still fails on its mutant.
