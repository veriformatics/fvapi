# U4A Tier B — history storage in place (S2): unit contract

Tier: kernel (store representation + its proofs; no downstream re-check). Law: `.claude/rules/store.md`,
`.claude/rules/hist-probe.md`, `.claude/rules/c8b.md`. Ruling: `.agent/spec.md` `Decisions` → Store (History storage).

## Change

`State`'s nine history fields (`entries`, `origins`, `revisions`, `audits`, `answers`, `admissions`, `deliveries`,
`descriptors`, `authority`) and each row's nested `attempts` become `Hist α` = a newest-first cons list with O(1) push and an O(1) cached length
(`size` + its proof `size_eq`; amendment = store walks SW-K8, `docs/contracts/U4A-storewalk.md`);
the chronological view `Hist.toList` is noncomputable (compile barrier: a compiled use fails to build). Production
functions consume `Hist` directly; proofs reason through `Hist.toList`. Reference implementation = spike S2
(`wt/builder-39` @ 0e27647, kept until C2 passes); the unit re-implements under these rows.

Why S2 over S1 (typed twins beside the frozen functions, `wt/builder-38` @ 180279c): one production State
representation (S1 keeps a runtime/reference correspondence frontier: every new State-dependent runtime path needs its
commutation); E-A40 cost twins + native evidence bind to the ordinary production functions; the State-dependent
store-walk rows change one path. Not reasons: the G2 memory grade (same pass/fail pattern), G5 wall time (descriptive),
the spike inventories (mixed units; no effort ratio). Fewer bridges ≠ a smaller trusted base.

## Frozen before representation code (step 0)

- M1 root/module manifest (base 349a2e8; line numbers below at that base): fully qualified C2 roots — at least
  `FvapiProof.Store.Model.productionSurfaceConforms` (`FvapiProof/Store/SurfaceProduction.lean:13`), `startup_exact`
  (`FvapiProof/Store/StartupExact.lean:519`), `snapshot_exact` (`FvapiProof/Store/SnapshotExact.lean:438`) + the
  demand/forecast roots of the shipped call-path inventory, every name resolved; complete module targets
  `FvapiProof/Store/Model/Blockers.lean`, `FvapiProof/Store/CheckpointCounterexample.lean` + the spike's direct reds
  (ModelCursorDemand, SurfaceApplyAssembly, StartupPostRead, StartupSound); each root's baseline type + the
  meaning-bearing predicate/bridge definitions it depends on (e.g. `BatchAgree`).
- M2 spec tree `FvapiSpec/Store/**` at 349a2e8 + the erratum allowlist (C1).
- M3 representation census: the one authoritative production State type, its allowed holder/wrapper types, the
  compiled frame roots of the driver.
- M4 acceptance matrix (C5 C6 C8 C11): per row the compiled entry + callees, fixture topology, held prior/proposed
  roots, grid + caps, cuts, expected byte expressions, functional proof root. Frozen: `docs/contracts/U4A-tierb-m4.md`;
  its stock preflight (M4 §0) runs before the first S2 commit.
- M5 detector qualification: each reversal detector (below) fails on its plant — added premise, removed conclusion
  conjunct, changed predicate behind an unchanged header, missing root, unapproved spec-body edit, a second runtime
  representation — and an approved representation edit passes through its stated equivalence route.

## Rows (each = obligation → acceptance check)

| id | obligation | acceptance check |
|---|---|---|
| C1 | Semantic target: the reviewed store behavior on arbitrary histories; baseline public roots + premises kept; `FvapiSpec/Store/**` changes only per store.md | M2 diff = the allowlist alone; known edit: `noncomputable` on `FvapiSpec/Store/Formats.lean` `checkedInput`, annotation only, body byte-identical ⇒ an erratum row + steward ruling, or a design leaving FvapiSpec byte-identical; every new/changed `Hist` primitive + order-sensitive or scalar history reader has a named unconditional refinement to its frozen chronological `List` meaning over a domain incl. duplicates, out-of-order records, ties, Nat underflow + past-end prefixes, with no `State.Valid`, uniqueness or order premise the original lacks |
| C2 | First checkpoint = functional closure of M1 against the unchanged spec + premises | every M1 root builds + axiom audit ⊆ {propext, Classical.choice, Quot.sound} (planted axiom fires); a missing or dropped root or a blocked module fails C2; changed definitions inventoried + transitive dependents re-elaborated; statement-faithfulness review (astra lane) of every new/changed bridge + changed statement; reversal detectors pass |
| C3 | Actual driver binding: the dev allow-all configuration is not a live lawful-policy witness (`¬ structuralPolicy.Laws`, `FvapiSpec/Store/Review1.lean:110`, pre-existing); generic surface conformance does not specialize to it | a named closed bridge for the S2 configured driver `DevRuntime.modelBatch` (`Fvapi/Store/DevRuntime.lean:359` at 349a2e8) → `batchEvaluation` (`:328`) → `decideBatchPreparedDemand config.policy sha256 … commands commandParser (prepareRecords historyHead? …)` → `evaluatedBatch` (seal, state installation, rendering), the forecast/real continuation + every other declared driver entry covered; the same `config.allow` behavior for true + false (`Config.policy` = every field `config.allow`, `Fvapi/Store/DevConfig.lean:108–115`) + every declared error/resource path; a lawful-policy witness only where it denotes that same policy + domain, else a faithful command-restricted bridge |
| C4 | Observable demand: `BatchAgree` (`FvapiProof/Store/ModelDemand.lean:300–304` at 349a2e8) = terminal projection (no command tags, acquisition outcomes + counts, error-path entropy remainder; `consumed` not compared) | the complete observable demand/step relation + its proof root, or before Tier B acceptance an open `.agent/review.md` row (owner MAIN, closure unit, exact observable fields, required proof root, acceptance command) that blocks the Self-verification + IMPLEMENT-close claims; Tier B's credited demand theorem = the terminal projection; a separate ruling on `consumed`, which cannot waive tags, acquisitions or error-path entropy |
| C5 | Resource target: scalar + admission history readers and persistent appends allocate no OLD-sized spine copy or per-OLD-element temporary; append work = O(new) | frozen G2 flatness (`hist-probe.py` sweeps) + G3 transitive OLD-element review (generated equality/instance callees + stored callbacks), red baselines + copy controls unchanged; requested output projections + checkpoint-uncovered suffixes = distinct bounded terms owned by the frozen G3 allowance + the K2/K3 store-walk contracts; conversion or input scratch never relabelled as output; a charged OLD copy does not pass the unchanged grade + stays inside U4A's E-A40 obligation; Keys equality = closure-free `@[csimp]` (generated `instDecidableEqKeys.decEq` allocates an `instDecidableEqString` closure per comparison) + native evidence + the predeclared ablation (f2 drop = 24·K bytes per cut); membership wrappers = an O(1) charge; `Hist.flatMap` worst-case accumulated-output copying + full-input temporary removed; `Hist.drop` = a charged suffix copy, no exemption; M4 §1's T-rowcheck + T-headcheck (admission-path validation scratch) stay open C5/G3 findings until the store-walk N6 change or a recorded exception |
| C6 | Residual allocation findings F3/K3, F4, F5 | each an M4 row, every declared cell passing (failed/incomplete cells stay in the verdict): F3 → K3 (tail invariant before the list is built, running total, refusal/threshold path charged); F4 → pinned runtime allocation of the overflow literals + nested `attemptCount`; F5 → indexed or fused delivery validation + an unconditional functional refinement, empty + nonempty delivery histories |
| C7 | Coalescing reader time | its algorithm + a proved bound, or the contract declines a time guarantee (time stays empirical) |
| C8 | Closing evidence | the acceptance manifest covers every changed driver entry + command class, pure + model/demand paths, outcomes success / refusal / semantic error / transport error / suspension / resumption, OLD/NEW/shared histories, each with its functional root + resource check or a named assembly obligation; original G2 grids + cases mandatory; nested + delivery cells on predeclared grids + caps; no unrun capacity cell renamed feasible; every skipped/incomplete cell reported; complete count + byte traces; R = 3 cold/warm; 5,178 blind cases + the model1025 witness; arbitrary-state differential (ruling: M4 §6a image/driver differential over the replay-reachable domain + §6b arbitrary logical States = C1's closed `_listMeaning` refinements as the property test, each root credited only after the `.claude/rules/tiers.md` statement-faithfulness review with its vacuity probe; a changed function without a closed refinement → an in-process differential cell); whole proof library green + root/axiom verification; final-driver C8b + every invalidated native/frame record |
| C9 | Sequencing | the store-walk proposal + its cost reach the user before the first structure-dependent E-A40 memory proof; the cost corpus (`Fvapi/Store/{Cost,CostTyped,CostCompose}.lean`: 15 definitions modelling list copies, e.g. `extendCost`; `FvapiProof/Store/CostTyped.lean`) parks until then unless an M1 root imports it (then a representation-only repair, statements unchanged); E-A40 proved once on the combined storage + store-walk implementation; U4A's bound scope stays |
| C10 | Gate runners | runner inventory for these rows; each rejects a planted unexpected command rc + a planted count/verdict mismatch with a nonzero exit, its clean control exits 0; cleanup or a final success cannot overwrite an earlier failure; inventory + firing commands + results recorded |
| C11 | Nested attempt histories: `Row.attempts` is copied by every attempt update (`attempts := old.attempts ++ …`) and mapped by every `attemptCount` | `Hist Attempt` (O(1) push, newest-first latest), closure-free scalar readers; its own shared-root writer/reader cohort with OLD attempt count varied independently of outer history length: newest / oldest / absent selection, duplicate version/number semantics, refusal + overflow paths; P-T / P-R nested-spine controls realized + firing under the same grade; synthetic + reachable-driver cells labelled apart; closes when these cells + C1's refinements pass |

## Reversal (detectors frozen + qualified in step 0; checked at C2)

- R-a an added hypothesis, narrowed domain, lost result conjunct or weakened predicate on any M1 root or its
  meaning-bearing dependency definitions (a type or definition diff fails until its retained meaning is shown by the
  stated refinement/equivalence proof + independent statement review).
- R-b an M2 diff outside the allowlist (`checkedInput`: annotation only).
- R-c an extra authoritative runtime State representation or a whole-State runtime ↔ logical materializer outside the
  M3 allowlist, found by the census of compiled State/holder types + reachable converters/callbacks from the driver
  roots; noncomputable proof views are not a second production representation.
Any of them ⇒ stop and compare a same-target S1 completion plan. A ledger of newly exposed red modules rides to C2;
ordinary module errors do not reverse. Hidden allocation through generic closures stays C5's transitive grade.

## Credit labels until closed

C3 open ⇒ the surface theorem binds the lawful-policy surface only; C4 open ⇒ demand credit = terminal projection;
C5/C6/C11 open ⇒ the G2/G3 reds stand; C8 open ⇒ no unit acceptance.
