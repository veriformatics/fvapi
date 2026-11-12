---
paths:
  - "tests/store/model/resident-views.py"
  - "Fvapi/Store/DevBudget.lean"
  - "Fvapi/Store/DevRuntime.lean"
  - "Fvapi/Store/Queue.lean"
---

# Resident-view check (E-A40 C3c, erratum E-A55)

- `tests/store/model/resident-views.py` = the contract check on enqueue admission behind a waiting ticket whose installation supersedes a selected object the later ticket reaches (no sudo; ≈ 12 s on vflab): from the repo root `python3 -I tests/store/model/resident-views.py .lake/build/bin/fvapi BLIND_DIR` (BLIND_DIR = the extracted `wt/tester-11` suite). It imports `post-writer-guard.py` by path (Suite, probe, World builders) and the blind suite's `TestsU4.{image,candidates,oracle}` (read-only): one fresh driver session per probe, minima by binary search on `batch_retained_bytes`.
- Fixture: two provision batches, export, R0 = the selected generation's `authority.root`; t2 = admit whose staged receipt `evidence` names R0; t1 = request; batch_commands 1 ⇒ t1's installation drops R0 from the selected view before t2 runs. Variants: H (drain twice), HD (t1 cancelled = detached, then t2 enqueued), HC (close settles both through `drain`).
- Assertions: R1 one contract (e + the outcome at e equal across backends); R2 pure d = e; R3 the outcome at e completes on each backend (never rc 70 `accepted_batch_reservation`, busy or stopped).
- Firing record (lane 4804776, driver b98569e5): rc 1 with exactly 9 FAIL lines — {R1, R2, R3 pure} × {H, HD, HC} — and 3 PASS (R3 model × 3); e 47,900 on both backends in every variant; pure d 48,178 (d − e = 278); pure at e rc 70; model at e: H + HD `drained res:created | err:{"tag": "caller_reference"}`, HC `closed`. Green record (lane 77af911, driver 192774d9bfa6262d; unchanged at 0e7169a): rc 0, 12 PASS; e = d = 75,897 in every variant on both backends; outcome at e: H + HD `drained res:created | err:{"tag": "caller_reference"}`, HC `closed`; pure = model. Its assertions are relations, so an enqueue that never grants residency credit also passes it (scratch build, lane 4804776 with the enqueue resident set forced to ∅: rc 0, 12 PASS, e 75,897); the credit a head ticket keeps (E-A55: R = the selected view when no ticket waits) is graded by `post-writer-guard.py` default R6 e S, which fails on that build with exactly R6 e S pure + model (13,739 vs 13,690). The U4A-close store-control stage runs it (with `enqueue-sources.py` + `post-writer-guard.py`).
- An edit to `DevBudget` (`admissionResident` = the enqueue resident set, `admissionBytes`, `chargedBytes`), the admission sites in `DevRuntime` (`enqueue`, `drain`, `batch`, `closeQueue`), `Queue` or the script reruns it, with `enqueue-sources.py` + `post-writer-guard.py` (its default run grades the head ticket's residency credit).
