---
paths:
  - "tests/store/model/post-writer-guard.py"
  - "Fvapi/Store/DevBudget.lean"
  - "Fvapi/Store/DevRuntime.lean"
  - "Fvapi/Store/DevCommand.lean"
  - "Fvapi/Store/Prepare.lean"
  - "Fvapi/Store/TraversalAdm.lean"
---

# Post-writer guard check (E-A40 C3)

- `tests/store/model/post-writer-guard.py` = the contract check on the retained-admission guard (E-A54: `DevBudget.chargedBytes` at apply/batch/modelBatch, `admissionBytes` at enqueue; no sudo; ≈ 21 s on vflab): from the repo root `python3 -I tests/store/model/post-writer-guard.py .lake/build/bin/fvapi BLIND_DIR` (BLIND_DIR = the extracted `wt/tester-11` suite). One fresh driver session per probe; minima by binary search on `batch_retained_bytes` (outcomes are monotone in L). Variants U (resolve, own audit unstaged: V04a), S (staged), U2/S2 (+ a claim naming the same audit, K = 2), C (request body staged after enqueue: an absent→present extension), C′ (staged before). Assertions: R1 one contract across backends, R2 an enqueued ticket drains ok (never rc 70 `accepted_batch_reservation`), R3 every variant ok at MAX, R4 floors (the `RECORDED` post-writer charges), R5 U ≤ S, U2 ≤ S2, C ≤ C′, R6 growth-free minima = `RECORDED`.
- Firing record (lane a39a06c, driver ed023a27): rc 1 with exactly 12 FAIL lines — R1 U batch, R1 U2 batch, R1 U drain@e, R1 C drain@e, R2 U pure, R2 C pure, R4 U model batch, R4 U2 model batch, R4 U pure enqueue, R4 U model enqueue, R4 C pure enqueue, R4 C model enqueue — and 36 PASS. Green record (lane b927292, driver b98569e5): rc 0, 48 PASS (values = the sheet § C3b pre-registration). The U4A-close store-control stage runs it.
- `RECORDED` = the constants of an exact `--predict` run (rc 0, every prediction met) on driver ed023a27 + the 68eeba1 fixture bytes. It changes only through such a run in the unit that changes the charge formula or the fixture, never in the unit the script grades. `--predict` rc 3 = a diagnosis error ⇒ re-read the code before any fix — except the owed re-record: since C3b (lane b927292) `--predict` exits 3 with exactly the 10 MISS that encode the unfixed mechanism and prints a RECORDED differing at D_C alone (40,342 vs 40,207); C3c (the next charge-formula unit) re-records predictions + RECORDED.
- An edit to `DevBudget`, `TraversalAdm`, the admission sites in `DevRuntime` (`apply`, `batch`, `modelBatch`, `enqueue`, `drain`), `DevCommand.ownAudit`/`resolved`/`expectedAudit`, `prepareRecords` or the script reruns the default mode, plus `--predict` when the charge formula changes.
- Harness facts: the pure backend answers `open` with `invalid`, so the setup miss runs at L; a minimum whose L − 1 refusal came from the setup aborts (rc 2, setup-bound). rc 70 is graded inside the session (`finish(assert_rc=False)`, then the evidence record's rc + stderr). `apply` exists on the pure backend alone.
