---
paths:
  - "Fvapi/Store/CostFrame.lean"
  - "FvapiProof/Store/CostFrame.lean"
  - "Fvapi/Store/DevRuntime.lean"
  - "Fvapi/Store/DevModel.lean"
  - "Fvapi/Store/Queue.lean"
  - "tests/store/model/C1Roots.lean"
  - "tests/store/model/C8Kinds.lean"
  - "tests/store/model/c8-frames.py"
  - "tests/store/model/c8-frames.recorded"
---

# Command frames (E-A40 C8a-1)

- `Fvapi/Store/CostFrame.lean` (ns `Fvapi.Store.Cost`; sole importer `FvapiProof/Store/CostFrame.lean`, no driver
  module) = each command-admission frame as its carry + C4 phase lists, one per full path. A phase = a C4 child
  (c, r, p): r = C1's `rootRetained` at its exact cut (`Phase.schema` S 16 B; `released` M-A, M-F, E-P when the
  enqueue proceeds, P-G = 0; E-A `rootRetained .enqueueAnalysis retained c`; D-I misfit = the new spine), else `kept`
  (P-A: r := c, the resident set + writer inputs stay live across W1) or a HOLD parameter; an own event = its bytes.
  Frames: modelBatch; batch/apply (+ the drain's nested batch, prelude 0); enqueue + cancelled (E-P keeps the
  parser's 16 B `Except` cell, `ctorCell`); drain pure | poisoned | model (the loop child; carry₀ = the selected spine,
  counted there alone); closeStore model | no model | pending (`closeQueueEvents` = its drains + its 16 B result
  cell); continue.
  `frameBound carry fulls response` = carry + the max over full paths of `regionPeak (path ++ [.own response])`.
- Theorems (`FvapiProof/Store/CostFrame.lean`, 41 named): T1 `exit_le`; T2 `frame_le` (a prefix + one response
  interval) + `frame_stop_le` (a stop inside a phase) ⇒ every frame point (entry, C4 run points, exit) ≤ `frameBound`;
  T3 closed forms `modelBatch_peak`, `batch_peak`, `enqueue_peak` + `enqueue_peak_scalar` (retained < 2^63),
  `cancelled_peak`, `drain_peak`, `poisoned_peak` (none for close, continue, the model drain: all HOLD); T4 `loop_le`
  under `Released`, `loopBound_le`, `drainLoop_le` (misfits on prefixes n, n − 1, … from a carry ≤ the n-ticket spine);
  T5 `nested_child` (drain → batch, close → closeQueue, continue → closeStore), `loop_child`, `prefix_loop_child`; T6
  `frameBound_mono`, `loopBound_mono`, per-frame `*_mono` (same shape; not admission monotonicity); T7 `drain_carry` =
  μ's queue form at the synthesized header `drainHeader` (RHS Σ certified ticket μ, never Σ `retained`); closed checks
  `modelBatch_released` 122, `loop_rebased` 148 < `loop_flat` 172, `cancelled_token` +16.
- Limits: arithmetic over declared phases, never a native-memory claim (native = C8b). The path lists bind to the
  compiled driver mechanically through C8a-2 (below); T5's multi-path / early-exit child at `frameBound 0` stays owed to
  assembly.
  Premises + parameters stay HOLD, never closed here: `Released` (each loop iteration enters within base + the previous
  exit retention), `hcons` (`fittingPrefix` builds one cell per selected ticket), every c/p + HOLD r (writers, program
  footprint, forecast p, analysis evaluation, closeQueue's drains, own-event twins), μ's `hadm`/`Agree`/`hhead`/
  `hheader`, rule L (a region's exit frees what its result cannot reach: C1 + C8b evidence, never a Lean premise).
  C8a-1 + C8a-2 + C8b = prerequisites of the E-A40 bound, not the bound.
- Axiom audit (scratch until U4A close's claim registration ports it into the gate): `bash
  .scratch/resume-1112/verify5-run.sh` on the w4 mirror (`AxiomUnionNamed.lean`: every theorem ⊆ {propext,
  Classical.choice, Quot.sound}, the 41 names + earlier cost names as required hits, a planted axiom must be reported).
- Rerun: an edit to either CostFrame file, `CostRegion`, `CostRoots`, `CostCarry`, or a frame function (`DevRuntime`
  modelBatch, modelDrainPrefix, batch, apply, enqueue, drain, closeQueue, closeStore, dispatch, dispatchOperation;
  `DevModel` continue; `Queue.fittingPrefix`) → `tools/vflab-run python3 -I tests/store/model/c8-frames.py` rc 0 +
  rebuild + the axiom audit, in the same commit. A changed RECORDED line = `--record` + its review in that commit; a
  CostFrame byte change = statement re-review, then re-pin `COSTFRAME_SHA`.

# C8a-2 coverage map (`C1Roots.lean --frames`, wrapper `c8-frames.py`, criterion `.scratch/u4/w3/c8a2-criterion.md`)

- Green = every IR path of each frame function (+ `dispatch`/`dispatchOperation` preludes, the finish closure) is one
  declared template exit; each instruction sits in a step with a named supplier: C1 partition (r by C1 at the same
  start + first release, replayed per path), token span (no-work, scalar results, `projLike`, noAlloc), own (bytes
  parameter), HOLD span (twin over the recorded extent), atomic child (the callee's bound; caller work outside it =
  no-work alone), cell (a 16 B Except wrapper), tail (respond call + wrapper | a child's error wrapper = the frame's
  `response`), EMPTY; frame decls reached only from declared sites over E1's closure; the map's r kinds + supplying
  fields = `C8Kinds.lean` (finite conformance over the pinned CostFrame bytes, not a parametric proof).
- Not covered: twins + own parameters instantiated over the recorded extents (assembly + C8b), native realization incl.
  closed-term first-read initialization (C8b), excluded arms' own bounds (their continuations are walked for frame
  calls alone), T5's multi-path child adapter.
- Edits: C8a-2 code lives only in the `-- C8a-2 BEGIN/END` + `-- C8a-2 main BEGIN/END` blocks of `C1Roots.lean`; the
  wrapper pins C1's part (sha of the stripped file) + its old modes' outputs. A map change = a map repair only where
  CostFrame already covers the IR path; a path CostFrame lacks = a C8a-1 fix (CostFrame + verify + statement
  re-review) in its own commit, never a map widening.
- Firing record (lane 01395be, driver 192774d9): 25 plants = registered cause sets (unassigned, freshleaf, childwork,
  biglit, tailwork → unassigned; reorder, extra → order; crossed, moved, replay → boundary; loop; target, unmapped →
  unmapped; missing; overflow; cycle; unsupported; provenance; omitted, twocells → undeclared; ambiguous; exitr → exit
  r + costframe; kind → costframe; control, smalllit → none). Run: store-control gate stage at U4A close (beside
  `c1-roots.py`); until then a run per change, recorded in the commit body.
