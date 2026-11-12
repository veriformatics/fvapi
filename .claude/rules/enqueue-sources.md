---
paths:
  - "tests/store/model/enqueue-sources.py"
  - "Fvapi/Store/DevBudget.lean"
  - "Fvapi/Store/DevRuntime.lean"
  - "Fvapi/Store/DevCommand.lean"
  - "Fvapi/Store/TraversalAdm.lean"
---

# Enqueue-source check (E-A40 C3b, erratum E-A54)

- `tests/store/model/enqueue-sources.py` = the contract check on enqueue admission when a source is absent at enqueue (no sudo; ≈ 10 s on vflab): from the repo root `python3 -I tests/store/model/enqueue-sources.py .lake/build/bin/fvapi BLIND_DIR` (BLIND_DIR = the extracted `wt/tester-11` suite). It imports `post-writer-guard.py` by path (Suite, probe, World builders): one fresh driver session per probe, minima by binary search on `batch_retained_bytes`.
- Variants: W(N) = a request whose content `body` ref asserts 1 B, the N-byte body staged after enqueue (N = 4,096 + 65,536); W′ = the same ref asserting N; M = W + `query` asserting N at the body's digest (the largest assertion bounds the payload, not the first); P = queued U2 (t1 resolve naming its own unstaged audit, t2 claim naming it; batch_commands 1); R = a provision naming a challenge record absent at enqueue.
- Assertions: S1 one contract (e + the drain outcome at e equal across backends); S2 pure d = e; S3 e W(4,096) = e W(65,536); S4 a drain at e completes on both backends (never rc 70 `accepted_batch_reservation`, busy or stopped); S5 R refused busy(batch_retained_bytes) with no ticket while its record is absent, pending once staged, then settled.
- Firing record (lane e49008c, driver ed023a27): rc 1 with exactly 16 FAIL lines — {S4 pure, S1, S2} × {W4096, W65536, W'4096, M4096, P} + S5 R (absent = pending) — and 6 PASS (S4 model × 5, S3); e W 7,239, e W′ = e M 7,245, e P 9,083 on both backends; d W 11,200 / 72,640, d W′ 11,518, d M 11,206, d P 15,932. Green record (lane b927292, driver b98569e5): rc 0, 22 PASS — e = d on both backends: W(4,096) = W(65,536) 7,552, W′ 11,653, M 11,525, P 17,226; R refused busy with no ticket, then pending once staged and settled. The U4A-close store-control stage runs it (with `post-writer-guard.py`).
- An edit to `DevBudget`, `TraversalAdm`, the admission sites in `DevRuntime` (`apply`, `batch`, `modelBatch`, `enqueue`, `drain`), `DevCommand.ownAudit`/`resolved`/`expectedAudit` or the script reruns it.
