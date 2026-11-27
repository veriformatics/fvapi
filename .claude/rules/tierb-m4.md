---
paths:
  - "tests/store/tierb/m4-*"
  - "tests/store/tierb/M4ReaderProbe.lean"
  - "tests/store/tierb/state-diff.py"
  - "tests/store/tierb/native-records.sh"
---

# Tier B M4 runners (contract `docs/contracts/U4A-tierb-m4.md`: §0 harnesses, §7 qualification, §8 rulings)

- Run on vflab from the repo root (`tools/vflab-run`): one observer job at a time, none beside a build
  (`.claude/rules/observer.md`); driver-only jobs (`state-diff.py`) may overlap. Exit maps = each runner's header: 0
  pass, 1 finding / failed / incomplete cell, 2 usage; `m4-run.sh`, `native-records.sh` + `m4-qual.sh` never reset an
  earlier failure.
- `m4-probe.py` = D + RP over `tests/store/model/hist-probe.py` (imported unchanged; f1/f2 + V5 keep its law). D =
  the §2 shape registry (`SHAPES`: setup → measured batch → effects; roles writer/reader/alloc/iter; per-phase minima E/F/R):
  model sessions = programs A/B/C + count programs, pure sessions = program P with PARENT `dispatchOperation` (the
  observer refuses PARENT = START). An arm passes `--symbols FILE` (its census-resolved roles + registered traces; a
  `minima` key → rc 2: floors live in the grader), recorded before its first graded run. Role `iter` = HIT points
  `SYM+OFF` (`.claude/rules/observer.md`): one count program per point (hitn per phase + `count iter total E,F,R`),
  each pinned to its instruction by `Shape.pins` (objdump text, whitespace-collapsed; census + count print `pin … ok|
  FAIL`, FAIL = bad) ⇒ a rebuild that moves code fails closed; rebind offsets + pins from the new disassembly.
  `--profile lazy-alloc` (M4 §9
  R14; default `stock`) = the arm's allocator floors: alloc role exactly [U `allocatedHas`, B `allocatedHas___boxed`]
  (else rc 1), per-entry U|B floors f1r (0,1,1)|(0,1,1), W3 (0,1,1)|(0,2,2), f3c (0,0,0)|(0,2,2), f1r-pure P 1|1,
  f3c-pure P 0|2; `census` binds U + B = present, distinct addresses, no direct call/jmp between them (a nested entry
  counts twice); rebind after any codegen change. `hist f1|f2 H … --hist-symbols FILE` = hist-probe's count run +
  exact roles (writer 4, reader 10, alloc 6 | stock 3) + trace = the map's PREDICTED trace (arm map
  `m4-arm-hist.json`: the S2 spike record); a mismatch = a matrix error → ruling, never a refit. RP = `rp
  n2s|n3s|t1err` over `fvapi-store-m4-reader-probe`: the probe's final
  status line (`--status`) = the plain run's line + `rc=0`, checked on the observed run — bpftrace's own exit never
  carries the probe's.
- `M4ReaderProbe.lean`: one exported `@[noinline]` function per region, called twice through ref'd closures (cold,
  then warm graded); every input + callback result is built before the region (an `Attempt` built inside cost the
  stock evolve region 64 B: §8 R5); export names stay fixed across arms (an arm swaps the attempt representation).
- Model backend capacity: one ≤ 1,024-name temporaries tape per session (`DevConfig.lean:26`) ⇒ model grids stop at
  f3 n 64, f4 A 64; past it a setup batch answers `known_not_committed` / `stopped` (the World's committed-counters
  check stops the cell) or the measured batch `error:stopped`; larger grids = `-pure` cells (§8 R1).
- `state-diff.py` (§6a: `gen`, `corrupt`, `build`, `cycle`, `diff`, `feasibility`): an import frame carries one
  attachment per stored file, ≤ 1,024 (`DevProtocol.lean:59`) ⇒ every image fits one frame (fit loop, §8 R6); cycle
  sessions draw ids from 1,000,001; the bound World's counters = the open summary's; a corrupted record outside the
  opened closure still opens ⇒ World seeding skips unparsable records. Corpus of record `~/gate/fvapi-sd-corpus-192774d9`
  (`build DIR STOCK BLIND 100 512`, MANIFEST 4c413a7b…); mini `~/gate/fvapi-sd-mini` (`build DIR STOCK BLIND 4 80`,
  MANIFEST b672655b…).
- `native-records.sh`: builds `fvapi` + `fvapi-store-input-probe` first (a failed build = exit 1 before any child);
  c8b children take their identity env from the caller (`.claude/rules/c8b.md`); absent ⇒ no `c8b` line ⇒ that child
  fails.
- Qualification = `m4-qual.sh STOCK BLIND PROBE PLANT MINI ARM ARMPLANT OUT`: 55 checks, each `qual NAME rc want
  ok|FAIL`; PLANT = STOCK's tree with `attemptCount` + 1 (`Fvapi/Store/Model.lean`), kept built at
  `~/gate/fvapi-sd-plant-d0c6b4e` (identity = sha256 prefix 446fbcdd; no SHA256SUMS); ARM = the frozen arm driver;
  ARMPLANT = ARM's tree + `m4-armplant.py apply` (both allocators gate `candidate == "f"×32 && used candidate`: valid
  hex outside the fixture tape, U + B stay compiled + reachable, never entered; built with `lake build fvapi` alone,
  restore = the tree's files, rebuilt driver = ARM's hash; `check` confirms the gate in both files); R14 plants grade
  the log's named cause through `m4-qual-logs.py` (`skip`, `forward`, `trace`), not the exit alone.
  Separate jobs: the full §6a stock-vs-stock diff + the full `native-records.sh` run (c8b env).
- Firing record (first lane e6560a5; re-fired at 236ce32 = qualification #5 and at c936bc0 = qualification #7, PROBE =
  the frozen arm probe 2cfbf32f; stock 192774d9, PLANT 446fbcdd, MINI b672655b): `m4-qual fails=0`, 33/33 at the
  expected exit, each for its named cause: rp-clean = an N2s region at exact=0 (count 0, evolve 0, latest 16, shape
  32 B; §9 R12); the t1err plants run on {10², 900}; d-minimum = latestAttempt E 0 < 1; d-unresolved = the planted symbol's E 0 < 1; d-trace +
  run-trace = subn ≠ the registered trace; rp-exit/-first = the probe status rc=3 (every size | the first); rp-once =
  1 call; rp-region = the driver as PROBE (observer exit 2, the plain run's usage exit 2, no FINAL row); run-first =
  repeat:f1r's trace mismatch, then a clean rp:t1err ⇒ m4-run bad=1; run-verdict + nr-verdict = no verdict line (a
  fake python3); nr-child + nr-first = c8b:stock without PS; nr children = resident-views (c8-frames grades against
  the recorded stock IR ⇒ red on any non-stock build); sd-plant = 4 differing; sd-first = 1 differing + 1
  rejection; sd-floor = 4 < 100. Qualification #8 (lane c3eda97; ARM 06a8a520, ARMPLANT 0974e1bb): `m4-qual
  fails=0`, 55/55: d-minima-key = rc 2 (`minima` key refused); l-census = U@1e43e0 B@1e44d0 distinct, crossing 0;
  l-bind-u + l-bind-x = the boxed route FAIL + `lazy-alloc binding` PROBLEM; h-skip = ARMPLANT alloc 0 ≠ 6; fwd-clean
  = no `bad window`; fwd-trace = f1's `subn … want` line, none on f2; p-count-* (f1r, W3, f3c, f3c-pure) = U = B = 0 +
  exactly the positive floors FAIL, tags + digests = ARM's (`skip ok`); stock counts rc 0 with f3c-pure allocatedIds
  P 2 ≥ 2 (§9 R14 (c)). R14 (h) on a3b56f8f: the five lazy-alloc counts = the floors exactly, hist f1/f2 H 100 = the
  predicted traces. Qualification #9 (lane 41c772e; same STOCK, PLANT, MINI, ARM, ARMPLANT): `m4-qual fails=0`, 55/55.
  Pin firing (census = nm + objdump alone): a copy of driver 45b270a2 with SCAN+0x4e's ModRM byte 0x76 → 0x7e
  (`%r14` → `%r15`, same length) → census QA-arev rc 1 naming that pin alone, clean rc 0; `insn` at a mid-instruction
  offset = "". Gate stages python + shell clean; a shellcheck directive carries its reason on the
  line above it. Full §6a corpus stock vs stock rc 0 (§8 R6). T1 shapes close + reopen after the measured batch
  (`m4 NAME X=x reopen ok|<decision>:<error>`, a refusal = exit 1 = plant (iii)'s second detector): stock
  T1/T1-op/T1-by at 236ce32 = the stock record byte for byte + `reopen ok` at every X; at c936bc0 stock T1 + T1@4 +
  T1-opN red, T1-opC green (1,120 ×4), the T1-op pair contrast [12,787,712, 1,120] = the record.
- Region symbols: each §2/§3 region = a compiled symbol the census resolves on that binary. `@[noinline]` stops
  Lean's inliner alone: clang -O3 inlines a thin wrapper (one call + allocations) and `--gc-sections` drops it
  (leanc: `-ffunction-sections`, hidden visibility, no LTO) ⇒ `nm` the driver + probe for every region symbol before
  a graded run; a region function carries its work (`refreshViews` = its 8 kinds written out, = the fold by
  `refreshViews_fold`).
- An arm's sweep needs its registered traces (`--symbols FILE` key `trace`; missing ⇒ rc 2 "no registered … trace
  (record it with count)"): count mode on the frozen arm driver records them first. `m4-run.sh DRIVER BLIND PROBE OUT
  [--symbols F] [--profile P] [--hist-symbols HF] [CELL…]` forwards the options to every cell; cells `census:S`,
  `count:S` (the grid's first point), `histcount:f1|f2` beside `sweep:S`, `repeat:S`, `hist:f1|f2`, `rp:…`; the closing
  record (§9 R14 (f)) = one driver's count receipts + census + byte/repeat cells; hist sweeps R = 1 per H, hist repeat
  ×2. Arm driver of record =
  `~/gate/fvapi-arm-06a8a520/{fvapi, fvapi-store-m4-reader-probe, fvapi-store-hist-reader-probe, SHA256SUMS, SOURCE}`
  (lane c3eda97's build; `sha256sum -c` before each use); its matrix of record (default cell set, `--symbols
  m4-arm.json --profile lazy-alloc --hist-symbols m4-arm-hist.json`) = 114 cells, 113 pass, the one fail = sweep:N6-A
  (A k0/k1 NOT-GROWING = the N6 contract's record, declared before the run); hist:f1 + hist:f2 flat on the arm.
  Superseded: a3b56f8f (lane b2526c3; matrix kmx 59/66).
- Strata + cohorts (M4 §9 R10/R11): a `SHAPE@N` cell = one fixed-NEW-width stratum, flat within, never compared across
  (T1 {100, 400, 900} / T1@4 {1000, 1010, 1020}; rp:t1err {10², 900} / rp:t1err@4 {1000, 1020}); T1-opN / T1-opC =
  fixed-branch cohorts (X = 100·H + t; RV − BC exactly flat within each); the original T1-op pair = expect `pair`
  (semantic + reopen check, RV − BC recorded); `graded()` gives `pair` the RV/BC/C windows of `tail-op`.
- §9 controls (b2526c3 tree, workspace-only `Seal.lean` patches; `plantKeep` = an opaque `@[noinline]` consumer that
  keeps the planted work in the emitted C; archive `.scratch/u4/w3/tierb-preflight/kp-job.tgz`), each prediction
  declared before its run and met: tailcopy + reencode → T1, T1-opN, T1-opC, T1-by rc 1; ckptonly → T1-opN rc 0, T1-opC
  + T1-by rc 1; wholehist → T1 + both cohorts rc 1 (flat in t, +2·192·ΔH B); preguard → rp:t1err + @4 rc 1 (+24·ΔH B,
  `.corrupt .graph` kept); total1 → c2-check build rc 1 + reopen `.corrupt .graph` ⇒ T1 rc 1; sealhoist → T1 rc 0, and
  the §4 G3 seal-boundary row rejects it (blind review: both hoisted seals fail NO-OLD, both clean seals pass).
- SW-A3 post-fix cells (lane eaa54d44): QA-obp-fix (R open misses), QA-coal-fix (k coalesces, m = 1), QA-coalm-fix
  (m pads, k = 1; in-part search ≤ 1,024 items = proved by K2Parts.apply_shape, not measured), QA-arev-fix (k, a = 2),
  QA-H-fix (H unrelated rows; grades A3's lookups alone) = `m4-run.sh` cells census:S + countsweep:S (no sweep/repeat:
  their allocation is not flat by design). `countsweep` = `count` per X + every role's per-phase entry increments equal
  across X. `forbid_re` = full-match regexes over the driver's `nm` (spec suffixes drift across builds): every match
  probed and held at 0 entries, no match = absent = 0. QA-arevB (B fresh misses + one claim) = a measurement: `measure`
  roles strictly increasing over X + `predict`'s exact pre-registered per-phase values (the batch-base NEW authority
  walk = SW-N6a's charged Q term). Minima = ≥ 1 on the unboxed lookup symbol in each phase where it is entered (the
  `___boxed` twin forwards into it). Firing record (frozen drivers ~/gate/fvapi-a3b-ad2aba4a clean,
  ~/gate/fvapi-s0-8f78609 pre-A3, ~/gate/fvapi-a3plant-{obp,coal,latest,arev} = workspace-only scan-restoring plants):
  clean all six pass + QA-arevB [0,54,54] at B = 8 and [0,594,594] at B = 32 = predicted; pre-A3 all six FAIL with the
  old scans entered; plant coal = countsweep NOT-FLAT (rowIsCurrentScan 32 → 128, Keys_decEqFast) + forbid FAIL; plant
  arev = forbid_re present + entered FAIL (the clean driver prints `absent ok`); plants obp + latest fail exactly their
  cells; each plant's predicted-pass cell passes. The red shapes QA-obp / QA-coal / QA-arev = the red record (lanes
  fef5b85, f7eb4bd, 41c772e); on A3 drivers they fail by design. Qualification #10 (lane eaa54d44; same STOCK,
  PLANT, MINI, ARM, ARMPLANT): `m4-qual fails=0`, 55/55.
- Change law: an edit to any of these runners reruns `m4-qual.sh` in its commit (every plant at its expected exit);
  an edit to a §2 shape or §3 region also reruns its stock cell (`m4-run.sh … CELL`) + compares it to the stock record.
