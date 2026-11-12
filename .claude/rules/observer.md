---
paths:
  - "tests/store/model/fresh-*"
  - "tests/store/model/FreshControls.lean"
---

# Fresh-live observer (E-A40 C6)

- `tests/store/model/fresh-observe.py` = the birth-aware fresh-live allocation observer (sudo bpftrace ⇒ vflab only, never CI); semantics + row format = its docstring. Qualification = `python3 -I tests/store/model/fresh-controls.py` from the repo root, rc 0: 16 region rows exact (c-a + c-b = 12 libc C controls, lean = 4) + each group's frame findings (`findings`: c-a none, c-b `cross=1`, c-c = the concurrent control's two rows `overlap … =1`, lean none). Plants `--plant comparator | birth | realloc-entry | overlap-reset | map-full`, each rc 1; firing record: comparator → `reuse` alloc, birth → `pre_free` −65,536 + `realloc_pre`, realloc-entry → `realloc_fail` 0, overlap-reset → c-c findings lose row #1, map-full (c-a alone) → the `Map full` stderr line with every row still exact. An unknown plant → rc 2. An edit to the observer or any control reruns the clean run + every plant; an edit to `fresh-probe.py` reruns `--routes` + one frame per backend.
- C rows follow from the observer's stated semantics ⇒ never edited. Lean rows are compiler predictions ⇒ changed only with `.lake/build/ir` evidence in the commit body.
- Lean region exports are called through closures read from refs: a direct call lets the C compiler inline the export and drop its symbol (the observer then exits 2: missing region symbol).
- Driver frames = `fresh-probe.py` over one committed region set per program (`fresh-regions-{a,b,c}.txt`): one bpftrace program loads ≤ 10 regions on vflab, 11 → E2BIG at load (bpftrace exits nonzero ⇒ fail closed). rc 1 on any finding (FINAL cross ≠ 0, a row with overlap ≠ 0, no FINAL row) or stderr problem — never relaxed. A region off the frame's path prints no row (`captureSections` = observation start; model-only regions in a pure frame).
- Route coverage = `fresh-probe.py … --routes`: every named candidate allocator entry of the exe + its libc counted, keyed `exe:SYM` | `libc:SYM` (the exe's own `free_sized` stays apart from libc's); rc 1 on a nonzero unprobed entry or none counted. Driver ed023a27 nonzero: libc free, malloc, realloc; exe mi_free, mi_free_size, mi_malloc. An allocation path inlined past every named entry stays invisible to the observer + the census alike (native residual).
- BEGIN prints `symbols probed=… absent=…`: an optional allocator entry missing from a binary is listed, never silently skipped. bpftrace stderr passes through. bpftrace 0.25 prints `Attached N probes` (BEGIN + END counted) and `WARNING: Map full` (exit 0) on stderr; the observer fails closed on a count mismatch or any lost/failed/error/map-full text.
