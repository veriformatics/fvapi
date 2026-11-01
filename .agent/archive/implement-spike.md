# IMPLEMENT orientation — stack spike evidence (archive; `Decisions` cite it)

Code + full evidence: local tags `spike-v2-server` (e886811), `spike-v2-client` (db138fc), `spike-v3.2-server` (20bf94e), `spike-v3.2-client` (516e6ce). Checks: v3.1 (sha eeb5f834…) for the v2 runs, v3.2 (sha be63e58b…, appraised by a scientist before the runs, results appraised after). Hosts: vflab = i7-7820HQ 4C/8T, 60 GiB; desktop = i7-8650U 4C/8T, 62 GiB; Lean 4.35.0.

## Grades

| ID | Grade | Evidence |
|---|---|---|
| F0 | pass, conditional | coverage tables name every residual (codec, IO, Std.Http, HACL* FFI, compiler/runtime); certificate path open |
| F1 / F1-B | pass / memory fail | 14 controls + byte-bound counters pass on the 64 KiB-receive server; 64 synchronized near-full bodies → RSS +259–283 MB vs a +40 MiB trigger |
| F2 | replay pass, semantics open | per-claim exports (proof root + full closure + comparator's fixed targets) vs independent challenges: all six kernels ACCEPT (server root + 28 client roots); whole-package `lake check --paranoid` drove nanoda to 48 GB RSS on the Std closure |
| F3 | pass | worker loop / surviving descendant / pipe flood → 504 in 5.19–5.49 s, ownership boundaries emptied |
| F4 | fail (tested client) | the v2 client encoded an unsatisfiable canary predicate and printed FAIL on the valid bundle; facts satisfy the later policy; fault bundles FAIL, mutants killed |
| F5 / M7 | open | first representation (String JSON decoder): 1 KiB > 60 s; kernel-shaped rerun: 60/60 builds of 1–64 KiB certificates exhausted 8 GiB; a 1 B malformed-input reject closed (22.6 MB export, caller replay 32.7–33.9 s); probe: an indexed-ByteArray scan of the 1 KiB input exhausts 4 GiB while a streaming Nat/List scan finishes in ≈ 0.4 s |
| F6 | pass | `fva trust` built from a clean fva clone at 71991fe: clean claim sets PASS, planted `sorry` / custom axiom / recursive `partial` FAIL with exact tags |
| F7 | pass | per checker on 72 known-false canaries: only the documented lean4#15704 prelude replacement is accepted by Lean-family kernels, rejected by con-leche + con-ron; no TIMEOUT |
| M1 | 1-byte receive fail; 64 KiB receive pass | 20 req/s fixed arrivals on vflab: 64 KiB receive p99 3.5–19.3 ms in all 25 windows (566,768 correct responses, 0 timeouts); 1-byte receive missed 50 ms in every fixed profile |
| M2 | open | 1,000-request pilot flat; full retention run moved to the server unit |
| M3 / M4 / M5 | pass | cold start 0.35–0.61 s, 7.9–8.1 MB binary; 512 MiB bundle ≈ 110 MiB/s at 36–40 MiB RSS; clean build vflab 6.49 s |
| M6 | pass (baseline server scope) | full closure inventories, 0 application escape hatches; the final server variant's new modules are outside that count |
| M8 | path shown | Mathlib-scale export needs comparator's fixed target set; with it comparator rc 0, all six ACCEPT, 10.75 s |

## Appraisal notes that bind later units

- The 50 ms result is a finite LAN/corpus result, not a production SLO; idle CPU weight gave no demonstrated protection against a concurrent load.
- No safe connection-admission number follows from F1-B; the server unit measures receive size × concurrency jointly.
- The certificate failure is a kernel-execution representation problem first (indexed byte arrays), not evidence that small JSON certificates are infeasible; no size or time promise follows.
