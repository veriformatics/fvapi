---
paths:
  - "tests/store/model/a2-cases.py"
  - "Fvapi/Store/PointSidecars.lean"
  - "Fvapi/Store/A3Overlay.lean"
  - "Fvapi/Store/Seal.lean"
  - "Fvapi/Store/Startup.lean"
---

# SW-A2 targeted cases (`tests/store/model/a2-cases.py`)

- Run on vflab from the repo root with the blind tree staged at `.lake/blind`:
  `python3 -I tests/store/model/a2-cases.py DRIVER .lake/blind [T1 T2 T3]`; rc 0 = every selected case passed, 1 = a
  case failed (its error printed), 2 = usage. Cases = the `| SW-A2 |` test clauses the blind suite of record leaves
  undriven: T1 = C12 + C16 (model: a miss's answer id and row id both stay allocated across close + open; tape
  [x, y, x, y, z] ⇒ the fresh request takes z), T2 = C14 + C21 (pure: one batch, caller A takes x, caller B's
  candidate x collides with A's same-batch id), T3 = C15 (pure: a miss refused on its answer draw reserves no id; the
  same batch's request takes x). Every batch goes through the blind suite's oracle-checked World.
- A2 is a proved refactor, so the cases pass on pre-A2 drivers too: their credit = the mutants they kill. Firing
  record (lane f1ffee5a; mutants = workspace-only patches of the clean tree, frozen in `~/gate/fvapi-a2mut-NAME`):
  clean b3dd2ba3 + pre-A2 ad2aba4a = T1, T2, T3 pass; noorig a57b1b50 (`PointSidecars.extend` skips NEW origins) =
  T1 + T2 FAIL; noans 2d27ec18 (skips NEW answers) = T1 FAIL; startnone a79a7f0f (`reconstruct` points := {}) = T1
  FAIL; ovpoints 0c7dd214 (`A3Overlay.extend` keeps the old points) = T2 FAIL; every other case passes on each mutant.
  sealnone 07ea1d1b (`sealBatchPoints` keeps the old points) + noidem 24109474 (the overlay skips NEW idempotency
  bindings) pass T1–T3: the 4 blind cases below kill them (sealnone = D06-shared-committed-staged-namespace FAIL,
  noidem = C21-batch-created-replay-reject-following-success FAIL; noorig fails D06-shared too; noans, startnone + ovpoints pass all 4). T3 (C15) kills none =
  characterization, uncredited: no SW-A2 line reaches it (the refused miss yields no proposal; `preparedLoopBy`
  keeps `state` + `ov` on a refused decision).
- The 4 blind cases = C01-caller-idempotency-isolation, C21-batch-created-replay-reject-following-success,
  D06-miss-row-then-answer-failure-atomic + D06-shared-committed-staged-namespace of the suite of record
  (`wt/tester-12` @ 934bc19), run by `tests/store/tierb/blind-lane.sh` (`.claude/rules/tierb-reversal.md`) with
  BLIND_TAR = `git archive 934bc19 TestsU4` (44 entries) in the workspace's `.lake/`, BLIND_TREE =
  3511ab38c80317f8b9b310758aa90e7b2eaab7da1413924b3530c1346a431720, EXPECT=4, CASES = `^(` + the 4 ids joined by
  `|` + `)$`. Its log names a failed case by its row + failure text alone (noidem's C21 printed `T2 ''`) ⇒ case ids +
  statuses = `.lake/blind/run.jsonl` (rewritten each run).
- Change law: an edit to a2-cases.py, or to the point-sidecar, overlay or seal code it covers
  (`Fvapi/Store/PointSidecars.lean`, `A3Overlay.extend`/`observe`, `sealBatchPoints`, `reconstruct`'s points),
  reruns it on the clean driver and on every mutant, + the 4 blind cases on sealnone + noidem: each case still
  passes clean and still fails on its mutant. An edit to the covered code that is comment-only (its diff touches
  comment lines alone) or leaves the clean driver's sha256 unchanged reruns nothing: the cases grade compiled
  behavior alone.
