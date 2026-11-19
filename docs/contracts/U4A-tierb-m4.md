# U4A Tier B — M4 acceptance matrix + C10 runner inventory (step 0 M4 of `docs/contracts/U4A-tierb.md`; frozen)

Contract `docs/contracts/U4A-tierb.md` step 0 M4 (C5 C6 C8 C11) + C10. Frozen before representation code: a cell, grid,
cap, predicate or predicted expression changes only by ruling, never in the unit it grades. Base = lane 8f12842
(stock driver 192774d9 = its build); reference = spike S2 0e27647 (red where noted, never an oracle).
Review record (consultant-58 rounds 1–2, advisor, MAIN rematches): the freeze commit body. Stock preflight rulings
(§8, before the first S2 commit) amend §0–§7 in place; each amended spot names its ruling.

## §0 Definitions

- Harnesses (§8 R4): D = `tests/store/tierb/m4-probe.py` (the §2 shape registry, model + pure sessions, per-phase
  minima) over `tests/store/model/hist-probe.py` (imported unchanged; f1/f2 + V5 stay its own; law
  `.claude/rules/hist-probe.md`); RP = `m4-probe.py rp` (byte grade owner: flat | grow | exact=S, the probe's final
  status line checked on the observed run) + `tests/store/tierb/M4ReaderProbe.lean` (exe
  `fvapi-store-m4-reader-probe`: §3 regions N2s/N3s/T1-err; W5 regions join with the arm); W4 stays with
  `hist-probe.py reader` + `HistReaderProbe.lean`; O = `fresh-observe.py` (≤ 3 SUB windows per program,
  `.claude/rules/observer.md`); §6a = `tests/store/tierb/state-diff.py`; aggregation = `tests/store/tierb/m4-run.sh`
  (§2/§3 cells) + `tests/store/tierb/native-records.sh` (§7 native/frame records); G3 = emitted-C review (§4); C2 =
  `tests/store/tierb/c2-check.sh`. Runner law: `.claude/rules/tierb-m4.md`.
- Metrics per window (D): `suba` = bytes of objects born inside the SUB role's calls (callbacks run inside included),
  `subp` = peak of those births live together, `sub` = of them live at the window's CHECK; whole-window
  alloc/peak/live = context. RP (§8 R5): region alloc/peak/live-at-return of the warm call, raw; the §3 constant c
  includes the region's own overhead (no `c_R` subtraction: W5's `length` region, built with the arm, is graded as its
  own W5-scalar cell). Byte unit = the observer's object size (cons 24 B, `some`
  16 B, `Prod` 24 B, closure 24 + 8·captures; stock f1 writer 48·H = 2 cons per H confirms the cons size).
- Grades: flat = (sub, subp, suba) identical across the cell's grid variable at the other variables fixed; exact =
  equality to the frozen expression; slope = Δsuba/Δvariable between two grid points. Every cell: R = 3 fresh identical
  sessions, identical setup/reply digests across R, complete-trace grade, identities (exe, harness, observer, grader,
  blind tree, toolchain commit + lib hash).
- Schedule (model backend; `Fvapi/Store/DevRuntime.lean:328–381`, `Apply.lean:341–417`, `EntropyDemand.lean:14–21,60–79`,
  `Commands.lean:136–143`): `let program := batchEvaluation …` is strict ⇒ phase E (count-mode window E: `call:program`
  → `call:forecast`) runs commands [0, s) whole + command s up to its first entropy draw (parse, guards, `allocatedIds`,
  `needsRow`); s = the first command with `needsRow ∨ needsAnswer` (needsAnswer = lookup | check; needsRow = request
  without replay | lookup without selection or coalescing row). Phases F (`ret:forecast`) and R (`ret:eval`) each re-run
  the remainder: command s from its draw (`propose`, `overflowing`, build, construction) + commands (s, n) whole + the
  batch continuation (`finalizeOutcomes`, `evaluatedBatch`, seal). s = n ⇒ everything incl. the seal runs once in E;
  F/R evaluate a `.done` program. Pure backend: one pass (`decideBatchPrepared`, `DevRuntime.lean:237–282`). Count-mode
  windows E ⊆ F ⊆ R are cumulative from `call:program`; per-phase counts = their differences.
- Positive-count rule: every declared SUB entry carries a minimum per phase (E / F / R increments, §2 column, derived from
  the schedule); count mode records the exact counts; the stock preflight confirms each prediction before any arm cell
  (a mismatch = a matrix error → a recorded MAIN ruling before any arm run, never a silent change). An entry below its
  minimum, or unresolved to a compiled symbol by the census = INCOMPLETE (counts as failed). A failed/incomplete cell
  stays in the verdict; nothing is relabelled feasible or passing. Under an acceptance profile (§9 R14) a role's floors
  are per compiled entry of its declared routes, held by the grader (`m4-probe.py`), never by a symbol map.
- Role map: a graded role = a semantic reader/writer; its compiled symbol(s) per binary are declared before the arm run
  (stock = the base function; arm = the S2 port's function). A callee the arm fuses into its caller is graded through
  the enclosing semantic role: base `currentRows` (called by `coalescingRow`, `Model.lean:249–257`, and the
  `OpenBindingPreserved` decision, `Commands.lean:150–156`) → arm `rowIsCurrent` scans inside those callers (spike
  0e27647 `Model.lean:251–266`, `Commands.lean:153–161`) ⇒ roles = `coalescingRow` + the `OpenBindingPreserved`
  decision, never `currentRows` itself.
- Stock role map (frozen driver 192774d9; `nm --defined-only` + `objdump -d` direct call/jmp sites, record =
  the freeze commit body; symbols carry the `lp_fvapi_` prefix): `Fvapi_Store_extend` 11,
  `coalescingRow` 3, `prefixGeneration` 4, `allocatedIds` 2, `idempotentOrigin` 1, `latestRow` 16, `entryAt` 13,
  `updateRow` 2, `latestAttempt` 2, `attemptCount` 3, `rowShapeDecidable` 2, `attemptEvolutionDecidable` 1 (via
  `attemptAppendDecidable___boxed`), `updateStructureDecidable` 1 (hosts `currentRows` + the `OpenBindingPreserved`
  per-row closure `openBindingPreservedDecidable___lam__0___boxed`; the decision has no standalone symbol),
  `committedChallengeDecidable` 2, `callerBindingsDecidable` 2 (hosts the inlined `IssueEntryRetained` decision + its
  per-entry closure `issueEntryRetainedDecidable___lam__0___boxed`), `deliveryEventsExact` 2, private
  `Apply_0__Fvapi_Store_conflicts` 2 (hosts the `.issue` duplicate scan), descriptor membership =
  `List_elem___at___00Fvapi_Store_meaning_spec__8` (shared: `propose` + `meaning` call it), private
  `Seal_0__Fvapi_Store_refreshViews` 1, `Seal_0__Fvapi_Store_buildCheckpoint` 1, `Apply_0__Fvapi_Store_overflowing` 2,
  `DevRuntime_0__Fvapi_Store_DevRuntime_batch` 2 (pure), `instDecidableEqKeys_decEq` 6, `meaning` 1, `historyHead_x3f` 3,
  `historyItems_x3f` 3, `blockGeneration` 1, `expectedStreamGeneration` 1, `introducedGeneration` 6. A role without a
  standalone symbol = its named host. The arm's symbols are resolved by the same census on the arm binary and recorded
  before its first graded run; a role unresolved there = INCOMPLETE.
- Stock preflight (step 0, before the FIRST S2 commit on the lane, after the runners exist): every §2/§3 cell on the
  stock driver/build records exact per-phase counts, setup seconds, replies + digests, the N3s overflow fields, the f4r
  replies, the T1-err reach (a genuinely sealed root, only the view tampered, `refreshViews` entered once) and the §6a
  feasibility. A prediction the stock evidence refutes = a matrix error → a recorded MAIN ruling made with stock
  evidence alone (no arm code exists yet); after the first S2 commit nothing in this matrix changes except by the
  contract's ruling path.
- Prediction protocol: each exact/slope expression below is frozen with its derivation; the arm's first run confirms or
  refutes it; refuted = red (a change only by ruling on evidence that the prediction errs against the contract).
- Plants: P-T (transient whole-OLD copy) + P-R (retained whole-OLD copy) of the cell's family, realized in emitted C
  (MAIN checks the IR) before their run; expected delta Σ 24·L_j (L_j = the family's OLD length at call j, from the
  setup vector); the grade must turn red (flat → not flat, or exact → mismatch) with a nonzero runner exit.

## §1 Charged-term ledger (every permitted non-flat or nonzero term; owner + E-A40 assembly obligation)

A charged term is measured in its own cell or excluded from the graded role by construction; it never passes a flat
grade. Each obligation id = a row in the E-A40 assembly (owner MAIN, closure unit U4A E-A40 assembly, acceptance =
the composition theorem's term list names it with its bound).

| term | expression | where | owner | obligation |
|---|---|---|---|---|
| T-out | 24·\|out\| per output list cell (+ 16 per `some`) | reply/page projections alone: read pages, snapshot/export pages, reply bodies built from a W5 result; a W5 result used as scratch (a check's or comparison's input, e.g. the `.row` meaning's `attemptValue` map) is never T-out: it carries its own §1 row or stays a G3 finding (C5) | the operation's reply/page byte limit (E-A19) | EA40-OUT |
| T-drop | 24·(N − k) result copy | `Hist.drop` callers | the caller's cost term: each actual suffix caller, both seals' NEW authority suffix included; K3 builds no OLD tail (§9 R10) | EA40-DROP |
| T-ofList | 24·N | List → Hist at startup, recover, import (`fromState`, decoders) | startup/import bound | EA40-STARTUP |
| T-mem | ≤ 64 B per call, N-independent | Decidable `∈` / `∀ x ∈` / `∃ x ∈` over `Hist` | the reader's flat constant | (inside each reader cell) |
| T-K2 | checkpoint rebuild on a threshold crossing | `buildCheckpoint` | store-walk K2 contract | EA40-K2 |
| T-K3 | one sizing print per NEW authority event per seal invocation (model forecast + real = 2; composed once with EA40-FORECAST) | `refreshViews` after K3: its once-per-invocation NEW sizing (§9 R10) | K3 (T1, within a NEW-width stratum) | EA40-K3 |
| T-walk | seal closure walk + decode memo | `sealBatchMemo` | store-walk K1 + K13′ contracts | EA40-WALK |
| T-forecast | the model's forecast pass (a second evaluation) | `modelBatch` | E-A41 forecast | EA40-FORECAST |
| T-queue | retained tickets + the drain's batch | enqueue/drain | C3 drain bridge + `drain_charge_le_queue` | EA40-QUEUE |
| T-rowcheck | O(A) per NEW row-revision root: `historyItems?` flattens every attempts block + `row.attempts.map (attemptValue caller id)` + `relatedLists` record reads (O(R) scan to the matching revision) | construction `ConstructionValid` (`Graph.lean:130–131`) → `meaning` `.row` (`GraphChecks.lean:334–342`); the row record itself = O(1) in A (`rowValue` stores the attempts HEAD, `GraphValues.lean:66–75`) | store-walk proposal N6 row (reclassified) | EA40-ROWCHECK |
| T-headcheck | per head check over n items: one `List.range` per block (24·count, freed per block) + one `some` per item + the decoded directory; time O(n·(index + H·\|roots\|)), attempts O(A·(R·A + H·\|roots\|)) | `historyHead?` → `blockGeneration` → `expectedStreamGeneration` + `introducedGeneration` (`GraphChecks.lean:115–162`); callers: prepare's old attempt head per update (`DevRuntime.lean:218,250,332`), construction `.row` + `.evidence`, attempts read (`Read.lean:264`), startup per stream (`Startup.lean:253–257`) | store-walk proposal N6 + K6 rows (reclassified) | EA40-HEADCHECK |

Time-only terms (no ledger row; graded by allocation alone, time empirical as C7): `overflowing` scans every
revision's attempts per command (`Apply.lean:133–143`, O(R·A), frozen semantics; T2 grades its allocation); the
coalescing reader O(R) per miss (C7). f4w's batch totals grow with A through T-rowcheck + T-headcheck = context, never
a graded role (its SUB roles exclude both by construction); preflight records f4w setup seconds per A.

C5/G3 disposition of T-rowcheck + T-headcheck: OPEN findings (per-OLD-element validation scratch on the admission path;
C5 keeps input scratch distinct from permitted output, and a charged OLD copy does not pass the unchanged grade).
The S2 port keeps the `.row` branch a representation swap (the same O(A) temporaries over `Hist`, never relabelled
T-out). Closure = the store-walk N6 designed change that removes/fuses the temporaries, re-graded by G3 + the N6-A
cell (§2), or a recorded contract ruling; until then C5, and with it unit acceptance, stays open (stated in the
store-walk proposal to the user); a batch-total measurement or a proved cost bound never closes them. Base
`attemptCount` maps a list (`Model.lean:210`): the arm's allocation-free scalar encoding = C11's fix (f4w), not a base
fact.

## §2 Driver cohorts (harness D; model backend unless stated)

Program per cohort = graded windows A (CHECK ret:writer), B (ret:forecast), C (ret:eval) with the cohort's SUB tuple,
plus count-mode programs `phases`, `roles` (≤ 3 SUB windows each). Effects = per measured command (tag + row identity).
Setup batches ≤ 1,024 commands; setup ≤ 600 s (preflight per cell; over = INCOMPLETE); id tape 1,024.

| id | setup (commands, in batch order) | family vector after setup | measured batch → expected effects | SUB roles: entry (min calls) | grid | expectation | controls | functional root |
|---|---|---|---|---|---|---|---|---|
| f1 (W1/W2a, unchanged) | H × request (one idempotency key) | authority = audits = H, origins = rows = 1 | [miss g, miss g @1] → new, coalesce (one row) | writer `extend` (4 = 2 × forecast + real), reader `coalescingRow` (2), `prefixGeneration` (2), alloc `allocatedIds` (2) | H ∈ {10², 10³, 10⁴} | flat; stock = red (writer suba 48·H) | P-T/P-R on authority + audits: Σ 24·L at A k | `FvapiProof.Store.Model.productionSurfaceConforms` |
| f2 (W1/W2a, unchanged) | H/100 cycles: 100 misses (10 groups × 10) + 10 declines between cycles | revisions ≈ 2 per closed row; rows live ≈ 10 | [miss group-0, miss measured-new @1] → coalesce, new | as f1 (original roles; base `currentRows` runs inside the `coalescingRow` role, `Model.lean:249–257`) | H ∈ {100, 200, 300} | flat (S2 red today: suba +7,920 per 100 misses) | P-T/P-R on revisions | as f1 |
| f1r (W2b) | = f1 | = f1 | [request (same key), miss g @1] → replay, new | writer `extend` (3 = E1 F1 R1: the replay draws no id ⇒ s = 1), reader `idempotentOrigin` (E ≥ 1), `latestRow` (E ≥ 1: the replay's `propose`, `Apply.lean:53–57`), alloc `allocatedIds` (E ≥ 1) | H ∈ {10², 10³, 10⁴} | flat | P-T/P-R on origins + authority | as f1 |
| f1r-pure (M01) | = f1 on the pure backend (configure backend = pure, init, setup batches through the pure `batch`) | = f1 | [request (same key), miss g @1] → replay, new; reply digest identical across R + stock vs arm (same tape) | program P (one window: START `call:` pure `batch`, `DevRuntime.lean:237`; CHECK `ret:` same; SUB = f1r's roles; one pass): writer `extend` (2), reader `idempotentOrigin` (≥ 1), `latestRow` (≥ 1), alloc `allocatedIds` (≥ 1) | H ∈ {10², 10³, 10⁴} | flat | P-T/P-R on origins + authority (realized in the pure path's emitted C) | `productionSurfaceConforms` (privateBatch) |
| W3 (C5 Keys equality; restored from v0) | = f2 | = f2 | f2's batch | reader `coalescingRow` (the `Keys` comparisons run inside it; minima as f2) | H ∈ {100, 200, 300} | arm flat; ablation arm (the `Keys` `@[csimp]` removed) = arm + 24·K per cut, K = OLD qualifying revisions compared (contract C5: generated `instDecidableEqKeys.decEq` allocates an `instDecidableEqString` closure per comparison) | the ablation arm = the matched control (must turn red by the predicted 24·K) | planned `@[csimp] theorem Fvapi.Store.Keys.decEq_eq_decEqFast : @Fvapi.Store.instDecidableEqKeys.decEq = @Fvapi.Store.Keys.decEqFast` (the contract's target; the stock emitted C calls `lp_fvapi_Fvapi_Store_instDecidableEqKeys_decEq` at 6 sites) |
| f3a (T3 + admission) | B0: provision profile, provision challenge; B1: request r0; B2: n × admit e_i (challenge = B0's, receipt binding e_i); B3: n × issue-reference d_i (entry e_i, unique receipt, request r0); B4: n × provision x_i | entries = admissions = n, deliveries = n, descriptors = n + 2, authority = 3n + 3 | [admit e_{n+1}, issue d_{n+1} (entry e_{n+1}) @1] → admitted, issued | writer `extend` (2 = E2: admit + issue draw no id ⇒ s = n), reader `committedChallengeDecidable` (E ≥ 1), `issueEntryRetainedDecidable` (E ≥ 1), alloc `deliveryEventsExact` (E ≥ 2: one per construction) + the `.issue` duplicate check (census-resolved, E ≥ 1) | n ∈ {16, 64} (model, §8 R1; `-pure`: {16, 64, 256}) | flat in n | stock red: `IssueEntryRetained` builds an `.obj` per OLD entry, `deliveryEventsExact` a closure per authority event (reviewer-14 F5); P-T/P-R on entries + deliveries | as f1 |
| f3b (provision) | = f3a | = f3a | [provision x_{n+1} (new), provision x_1 (existing: state unchanged)] → provisioned ×2 | writer `extend` (1 = E1: the existing provision returns the state unchanged, `Apply.lean:128–130`; s = n), reader descriptor membership (`∈ s.descriptors`, census-resolved, E ≥ 2) | n ∈ {16, 64} (model, §8 R1; `-pure`: {16, 64, 256}) | flat | P-T/P-R on descriptors | as f1 |
| f3c (hit + check) | = f3a + entry e_1 carries a checker spec | = f3a | [lookup-hit (spec of e_1, selected e_1), check (e_1, spec, input) @1] → answer, answer | writer `extend` (4 = E0 F2 R2: the lookup-hit draws an answer id ⇒ s = 0), reader `entryAt` (F ≥ 1, R ≥ 1), alloc `allocatedIds` (E ≥ 1, F ≥ 1, R ≥ 1) | n ∈ {16, 64} (model, §8 R1; `-pure`: {16, 64, 256}) | flat | P-T/P-R on entries + answers | as f1 |
| f4w (N1/N2 nested) | B0: request t (target row R_t), request p (pad row R_p); then A × [stage attempt fact (number i, version 1, event i, active, claimed 0, expires 100) + update R_t claim (expected revision i)] and (A_max − A) × update R_p (reason toggles p0/p1, no attempt); A_max = 520 | origins = 2, revisions = 522, audits = authority = 522, R_t attempts = A, R_t revision = A + 1 | [update R_t (expected revision A+1) + fact (number A+1, version 1, event A+1), update R_t (expected revision A+2) + fact (number A+1, version 2, event A+2, same claimed/expires) @1] → updated ×2 | updates draw no id ⇒ s = n, all in E: writer `updateRow` (4: 2 per accepted update, the `UpdateStructure` `Row.Shape` conjunct + `propose`, §8 R8), reader `latestAttempt` (E ≥ 2), `attemptCount` (E ≥ 2), the `Row.Shape` decision (`rowShapeDecidable`, `Model.lean:516–518`; E ≥ 2), alloc the `OpenBindingPreserved` decision (E ≥ 2; role map §0) | A ∈ {8, 64} at A_max 520 (model, §8 R1; `-pure`: {8, 64, 512}) | flat in A (stock red: `old.attempts ++` = 24·A per `updateRow` call, `attemptCount` maps 24·A, the `Row.Shape` decision (`attempts.map Attempt.event` + `List.range'`, `Model.lean:235–236`) allocates 96·A + 1,140, peak 48·A + 24, per call: §8 R2) | nested P-T/P-R (whole-attempt copy at `updateRow`): Σ 24·A over its calls; event-list plant at the `Row.Shape` decision: slope 96·A alloc, 48·A peak per call (§8 R2) | as f1 + C1 attempt refinements (§3) |
| f4o (N1 outer independence) | f4w at A = 64 + P × request replays of t's key | + P audits + P authority | as f4w | as f4w | P ∈ {0, 1024} | flat in P | P-T/P-R on authority | as f1 |
| f4r (N3 reachable refusal) | f4w at the grid's A | as f4w | [update R_t (expected revision A+1) + fact (number A+3, version 1, event A+1, active, claimed 0, expires 100): number gap ⇒ `AttemptEvolution` fails inside `commandStructure` ⇒ `.invalid`, pre-command state kept (`Apply.lean:346–347`, `:389–408`); update R_t (expected revision A+1: not A+2) + fact (number A+1, version 1, event A+1, active, claimed 0, expires 100) @1] → error invalid, updated | s = n, all in E: writer `updateRow` (2: the accepted update's two calls; the refused command builds none, §8 R8), reader `latestAttempt` (E ≥ 2), `attemptCount` (E ≥ 2), the `Row.Shape` decision (E ≥ 1: `UpdateStructure` short-circuits at `AttemptAppend` for the refused command, `Commands.lean:158–166`), alloc the `OpenBindingPreserved` decision (E ≥ 2) | A ∈ {8, 64} (model, §8 R1; `-pure`: {8, 512}) | flat in A; replies = the frozen `invalid` error, then success | nested P-R at the refusal's reader (`latestAttempt`) | as f1 |
| N6-A (T-rowcheck + T-headcheck A-sweep; recorded at step 0, graded by the store-walk N6 contract, never a Tier B pass) | = f4w | = f4w | f4w's batch | SUB roles: `meaning` (hosts the `.row` branch: `historyItems?` + `attemptValue` map + `relatedLists`; F/R/E per the schedule: f4w is all E ⇒ E ≥ 2), `historyHead_x3f` (prepare's old attempt head + construction; E ≥ 2) | A ∈ {8, 64} at A_max 520 (model, §8 R1; `-pure`: {8, 64, 512}) | stock + S2 arm: growing in A (the recorded red; predicted ≥ 24·A per call from `historyItems?` + the `attemptValue` objects); after N6's change: its contract's grade | N6's own plants (its contract) | N6 contract (store-walk proposal) |
| T1 (K3; F3) | f1 H with config tail_operations = 1,024, tail_bytes = MAX (genesis checkpoint covers 0 ⇒ uncovered tail T = H) | as f1 | f1's measured batch | `refreshViews` (2 = forecast + real seal; semantic extent, §9 R10: the once-per-invocation NEW sizing + per kind: covered guard, running total, threshold decision, view update), `buildCheckpoint` (0 here) | T ∈ {100, 400, 900} + {1000, 1010, 1020} (fixed-NEW-width strata, §9 R10) | flat in T within each stratum, never compared across strata (only NEW events sized) | (i) OLD suffix plant (materialize the full tail: Σ 24·T) + (ii) OLD re-encode plant (size every tail event: slope ∝ T), each placed before `refreshKind`'s branch test (§9 R11 controls); (iii) wrong-running-total plant (arm variant storing `bytes + 1` as a kind's running total) → rejected by `FvapiProof.Store.TierB.viewsTailExact` failing to build (c2-check build step rc 1) + the planted store's reopen (close → open) failing startup's view comparison (`Startup.lean:270–277` ⇒ `.corrupt .graph`) ⇒ cell exit 1; stock red (attr3: 192.1 MB at a near-limit tail; both strata red, §9 R10) | planned `FvapiProof.Store.TierB.viewsTailExact` (each kind: `view.tailBytes = tailBytes enc (s.authority.toList.drop view.covered)` ∧ `view.tailCount = s.counters.operation − view.covered`) + `refreshViews_preserves` + its consumption by `FvapiProof.Store.StartupExact.startup_exact` (views) |
| T1-op (threshold, operations; §9 R11) | tail_operations = 64, tail_bytes = MAX; setup [H − t, t] (the first batch checkpoints ⇒ `covered` = H − t > 0; the second leaves tail t), H ∈ {256, 512}; cohort N (no checkpoint) t ∈ {32, 62}; cohort C (checkpoint) t ∈ {63, 64}; + the original pair H = 512 [450, 62] / [449, 63] | tail t before | f1's batch (+2 ⇒ t + 2 ≤ 64 = no checkpoint / > 64 = checkpoint) | `refreshViews` (2), `buildCheckpoint` (N: 0; C: 16 = one per index kind per checkpointing seal pass, §8 R8) | the 4 cells of each cohort; the original pair | `refreshViews` − `buildCheckpoint` suba exactly flat within each cohort across H and t (no cross-cohort subtraction, no slack); the original pair = the branch-boundary semantic + reopen check, its cost contrast recorded (diagnostic); `buildCheckpoint` = T-K2, recorded | §9 R11 controls: (i) + (ii) before the branch test (t variation rejects them), a checkpoint-path-only plant, a whole-history plant (H variation rejects it); stock: cohort N red (7,055,552 / 12,787,712 at t 32 / 62, flat in H), cohort C green (1,120 ×4) | as T1 |
| T1-by (threshold, bytes) | per grid point H: f1 H setup, tail_operations = 1,024. Count session: configure tail_bytes = MAX → init → setup → b₀(H) = the views' tail bytes after setup (export: generation record `views`) → f1's batch → e(H) = tail bytes after − b₀(H) (no checkpoint asserted) → close. Graded sessions: configure tail_bytes = b₀(H) + ⌈e(H)/2⌉ BEFORE init (configure is invalid while open, `DevRuntime.lean:87`) → init → the same setup (setup digests = the count session's) → f1's batch. b₀ + e from the stock count session, asserted equal in the arm's count session (C1: byte-identical formats) | as f1 | f1's batch (crosses the byte limit ⇒ checkpoint in both seal passes) | as T1-op | H ∈ {128, 512} | `refreshViews` − `buildCheckpoint` flat in H | plants (i)(ii)(iii) | as T1 |
| T1-err (refreshViews error exit) | RP over a genuine root, driver-unreachable (import → open runs startup's `covered ≤ operation` check first, `Startup.lean:272`): `startup` over a driver-exported f1 H store, its `.entries` view tampered alone to `covered` = the next state's operation + 1 (§8 R3) | — | `sealBatchMemo` on a one-event state → `.error (.corrupt .graph)` (`Seal.lean:112`; the four `appendItems` run first on NEW items alone, `:223–234`) | region = the private `refreshViews` symbol (census-resolved) | H ∈ {10², 900} + {1000, 1020} (fixed-NEW-width strata, §9 R10) | region alloc identical across H within each stratum (§9 R10: the once-per-seal NEW sizing precedes the first kind's covered guard, which throws before that kind's running-total / checkpoint / update work); reply = the exact error | plant (§9 R10): realized pre-guard OLD work (an OLD-spine materialization or OLD re-encode before the guard, realized in the emitted C, `.corrupt .graph` kept, its length/count predeclared) → nonzero exit; the guard-reorder plant is retired (its suffix is empty) | `refreshKind_guard` + `refreshViews_guard` (adapted to the NEW-sizing signature); G3 confirms no OLD-sized allocation before the throw |
| T2 (F4) | f2 H | as f2 | f2's batch | `overflowing` (F2 R2) | H ∈ {100, 200, 300} | every SUB birth inside `overflowing` = 0 at each CHECK (a superset of the GMP/libc route: births attribute per window, never per allocator route, §8 R7); `overflowing` flat (the seal walk's own literal parses are outside this window: store-walk residual, scientist-20 E12) | stock red: ≥ 1 parse per OLD revision (reviewer-14 F4); parse-loop plant; scalar-map copy plant (attemptCount over a copied list) | `productionSurfaceConforms` (literal = `maxNumber`) |
| T3 (F5, D = 0) | f1 H (no deliveries) | as f1 | f1's batch | `deliveryEventsExact` (2 per seal pass: F2 R2, §8 R8) | H ∈ {10², 10³, 10⁴} | flat (stock green: 0 B at every CHECK, §8 R9) | per-authority closure plant | planned `FvapiProof.Store.TierB.deliveryEventsExactFast_eq` (unconditional; empty + nonempty) |

Feasibility on paper: f3a n = 256 ⇒ setup 3 + 3·256 commands in 5 batches; f4w ⇒ 2 + 520 updates + A stages; tape
draws: f1r 2, f3c 2, f2 ≤ 300 (existing cap). Preflight (vflab, stock driver) records setup seconds + the family vector
per cell before any arm cell; a cap failure stays failed.

Model capacity (§8 R1): attempt-bearing claims + admissions draw model temporaries from one ≤ 1,024-name tape per
session ⇒ model grids stop at f3 n = 64 and f4 A = 64. `-pure` cells = f3a-pure, f3b-pure, f3c-pure (n ∈ {16, 64,
256}), f4w-pure + N6-A-pure (A ∈ {8, 64, 512}), f4r-pure (A ∈ {8, 512}): the model row's setup, measured batch,
effects, SUB roles + expectation on the pure backend, graded in program P (f1r-pure's window: START `call:` + CHECK
`ret:` the pure `batch`, PARENT `dispatchOperation` — the observer refuses PARENT = START); minima = the model row's
per-phase sums, except the f3c-pure allocator: P ≥ 2 (pure runs once; §9 R14).

## §3 Synthetic cohorts (harness RP; in-process; warm second call; input `Hist` held across the call)

Callbacks are non-allocating (return values + inputs prebuilt outside the region, §8 R5). Predicted alloc = the
expression (exact slope) + a constant c, 0 ≤ c ≤ 64 B (W5 + N2s), independent of N, m, k (closure/specialization +
region overhead), registered at the first run; a slope or an N-dependence off the expression = red. N3s's region =
the whole update decision ⇒ graded flat in A, c recorded, no 64 B bound (§8 R5). Grid N ∈ {10², 10³, 10⁴, 10⁵}; m (outputs per
element, flatMap) ∈ {0, 1, 4}; k (take/drop/keepPrefix count) ∈ {0, 1, N/2, N}; \|out\| = the result length. Roots =
planned unconditional theorems in namespace `FvapiProof.Store.Hist` (qualified name = that prefix + the listed name;
`h : Hist α`, `xs : List α`, `p : α → Bool`, `f` as the primitive takes it, `n i : Nat`).

| id | primitive (S2 API) | predicted alloc (bytes; derivation) | root (planned, unconditional; List meaning frozen) |
|---|---|---|---|
| W5-ofList | `Hist.ofList (xs : List α)` | 24·N (one reverse) = T-ofList | `toList_ofList : (Hist.ofList xs).toList = xs` |
| W5-push | `Hist.pushMany h xs` | 24·\|xs\| (`reverseAux` onto `newest`); cells \|xs\| ∈ {0, 1, 64} at each N (flat in N) | `toList_pushMany : (h.pushMany xs).toList = h.toList ++ xs` |
| W5-scalar | `length`, `isEmpty`, `any`, `all`, `prefixWhileLength` | 0 | `length_eq : h.length = h.toList.length`, `isEmpty_eq : h.isEmpty = h.toList.isEmpty`, `any_eq : h.any p = h.toList.any p`, `all_eq : h.all p = h.toList.all p`, `prefixWhileLength_eq : h.prefixWhileLength p = (h.toList.takeWhile p).length` |
| W5-find | `findNewest? p`, `find? p`, `getLast?`, `get? i`; cells: p (a prebuilt marker test) hits the newest element / the oldest / none; i ∈ {0, N − 1, N (past end)} | 16 if found else 0 | `findNewest?_eq : h.findNewest? p = h.toList.reverse.find? p`, `find?_eq : h.find? p = h.toList.find? p`, `getLast?_eq : h.getLast? = h.toList.getLast?`, `get?_eq : h.get? i = h.toList[i]?` |
| W5-map | `map f`, `filter p`, `filterMap f` | 24·\|out\| (one cons per output, oldest-first by `foldl` over `newest`) | `map_eq : h.map f = h.toList.map f`, `filter_eq : h.filter p = h.toList.filter p`, `filterMap_eq : h.filterMap f = h.toList.filterMap f` |
| W5-flatMap | `flatMap f` (fixed: `foldl (fun acc x => f x ++ acc) []`) | 24·Σ\|f x\|; m = 0 ⇒ 0 | `flatMap_eq : h.flatMap f = h.toList.flatMap f` |
| W5-take | `take n` | 24·min(n, N) | `take_eq : h.take n = h.toList.take n` |
| W5-drop | `drop n` (one loop over the newest N − k, no `take` + `reverse` pair) | 24·(N − min(n, N)) = T-drop | `drop_eq : h.drop n = h.toList.drop n` |
| W5-keep | `keepPrefix n` | 0 (`Hist` = one-field structure ⇒ unboxed) | `toList_keepPrefix : (h.keepPrefix n).toList = h.toList.take n` |
| W5-mem | Decidable `x ∈ h`, `∀ x ∈ h`, `∃ x ∈ h` | ≤ 64, N-independent (T-mem) | `mem_iff : x ∈ h ↔ x ∈ h.toList` |
| W4 (unchanged) | RP `coalesce`, `member`, `latest`, `prefix`, `extend` over `history n t`, t ∈ {0, n − 1, n} | flat per (region, t); stock coalesce ≤ 10³ | each reader's unconditional refinement to its List meaning |
| N2s (nested readers) | `latestAttempt`, `attemptCount`, the `AttemptEvolution` decision, the `Row.Shape` decision over `Hist Attempt` of length A ∈ {10², 10³, 10⁴, 10⁵}; cases: number newest / oldest / absent; duplicate (number, version) pairs; out-of-order versions; events 1..A (Shape holds) + one event gap (Shape fails) | 0 per reader (flat in A; membership = T-mem) | `FvapiProof.Store.TierB.latestAttempt_listMeaning`, `attemptCount_listMeaning` (frozen List meanings = base `Model.lean:207–210` over `toList`), `attemptEvolution_listMeaning : AttemptEvolution past next ↔ ListMeaning.AttemptEvolution past.toList next` (base `:212–217`), `rowShape_listMeaning : r.Shape ↔ ListMeaning.Row.Shape r` (base `:226–236` over `r.attempts.toList`) |
| N3s (synthetic overflow; in-process only: JSON integers ≤ 2^53 − 1 = `maxNumber` ⇒ the driver parser cannot carry `maxNumber + 1`) | held State, one row R (revision r ≤ 100, state queued) + command update R (action claim, expected revision r, facts.now ≤ `maxNumber`): (a) R.attempts = A attempts, numbers `maxNumber − A + 1 … maxNumber`, version 1, events 1..A (synthetic: not `Row.Valid`), fact (number `maxNumber + 1`, version 1, event A+1, active, claimed 0, expires 100); (b) R.attempts = A attempts, all number 1, versions `maxNumber − A + 1 … maxNumber`, events 1..A, claimed 0, expires 100 (a version chain), fact (number 1, version `maxNumber + 1`, event A+1, claimed 0, expires 100); (c) `attempt_event` = impossible by size (`maxNumber + 1` events) | flat in A; guards pass (`commandWellFormed` bounds no attempt field, `Commands.lean:22–26`; `Attempt.Shape` + `Row.Shape` set no `maxNumber` bound, `Model.lean:199–202,226–236`) ⇒ `overflowing`'s first true check (order `Apply.lean:133–143`) = (a) `.overflow "attempt_number"`, (b) `.overflow "attempt_version"` | `productionSurfaceConforms` (overflow branch) |

Controls: P-T/P-R regions (fired: `.claude/rules/hist-probe.md`); spike `flatMap` (`foldr (acc ++ f x)`) = red at
m ≥ 1 (24·m·N(N+1)/2); full-input-temporary plant (`newest.reverse.flatMap f`) = red at m = 0 (24·N, zero output);
`drop` via `take` + `reverse` = red (48·(N − k)). N2s/N3s matched region plants (each an arm variant graded on its own
reader's RP region, A ∈ {10², 10³}; expected: not flat, +24·A (`Row.Shape`: slope 96·A alloc, 48·A peak, §8 R2) ⇒
`m4-probe.py rp` exit 1, §8 R4):
`latestAttempt` via `newest.reverse` then `find?`; `attemptCount` via a mapped number list; `AttemptEvolution` via
`toList.length`; `Row.Shape` via the event list + `List.range'`; the N3s decision via a list-built `overflowing` scan.
Old extend / writer-only firing never counts for these regions.

C1 frozen List meanings: `FvapiProof.Store.TierB.ListMeaning.<reader>` = the base 8f12842 body over the `toList` views
(byte-identical bodies modulo the field projection); each changed reader's refinement
`FvapiProof.Store.TierB.<reader>_listMeaning` has no premise the base lacks (domain: duplicates, out-of-order records,
ties, Nat underflow, past-end prefixes).

## §4 G3 transitive review (W6, extended to every changed path)

Scope: every compiled function reachable from each §5 entry that reads or writes a history family or `Row.attempts`,
incl. generated equality/instance callees + stored callbacks (`.lake/build/ir/**.c` of the arm). Per function: no
OLD-element allocation | a §1 term id | a finding. Criteria G3-1..G3-5 pass; plants G3-6..G3-8 + P-T/P-R/B13 rejected
(reviewer-14 protocol). Reviewer: sol lane; MAIN rematches every finding against the IR.
Seal boundary (§9 R10), both seals: `fresh` = the suffix after `before.state.authority.length`; only that list reaches
`refreshViews`' sizer; no OLD materialization or re-encode before region entry (generated callees + callbacks
included). Plant: a seal-hoisted OLD copy (the correct `fresh` still passed) → rejected by this row even with T1 green.

## §5 C8 coverage manifest (case → path → root + resource row; impossible combinations named)

Topology: OLD = the reader scans pre-batch history; NEW = the batch appends; shared = a persistent prefix shared by two
states (forecast vs real pass; a refused batch keeps the prior state). Credit labels: C3 open ⇒ store logic binds the
lawful-policy surface only; C4 open ⇒ demand = terminal projection.

| case | driver op (backend) | path / subtype | outcome | topology | functional root (+ label) | resource |
|---|---|---|---|---|---|---|
| M01 | batch (pure) / apply (pure) | request-created, request-replay | success | OLD + NEW | `productionSurfaceConforms` (privateApply/privateBatch) + C3 label | f1r-pure (§2 program P) + G3 |
| M02 | batch (model: `modelBatch`) | request-created, request-replay | success | OLD + NEW + shared | `productionSurfaceConforms` + `FvapiProof.Store.ModelForecast.forecast_normal` + C3 label | f1r |
| M03 | batch (model) | lookup-miss-new, lookup-miss-coalesce | success | OLD + NEW + shared | as M02 + `FvapiProof.Store.ModelDemand.decideBatchPreparedDemand_run` (C4 label) | f1, f2 |
| M04 | batch (model) | lookup-hit, check-answer | success | OLD + NEW | as M02 | f3c |
| M05 | batch (model) | row-update (no attempt) | success | OLD + NEW | as M02 | f2 (declines in setup) + f4w pad updates + G3 |
| M06 | batch (model) | row-update (attempt) | success | OLD + NEW (nested) | as M02 + C1 attempt refinements | f4w, f4o |
| M07 | batch (model) | admit (no row), admit (row + attempt) | success | OLD + NEW | as M02 | f3a (no row); admit-with-row = G3 + f4w nested readers |
| M08 | batch (model) | issue-reference | success | OLD + NEW | as M02 + `deliveryEventsExactFast_eq` | f3a, T3 |
| M09 | batch (model) | provision (new / existing) | success | OLD + NEW / OLD | as M02 | f3b |
| M10 | batch (model) | semantic-failure, noop | success (recorded) | NEW (audit) / none | as M02 | G3 + f1 writer cell (same `extend`) |
| M11 | batch (both) | any command: owner-policy reject, caller binding, intent mismatch, duplicate receipt, expected-revision mismatch | refusal (error result; state unchanged for that command) | OLD + shared | `productionSurfaceConforms` (decide error branches) | f4r (reachable invalid) + G3 |
| M12 | batch (both) | counter/number overflow | semantic error | OLD | as M11 | N3s (synthetic) + T2 |
| M13 | batch (both) | malformed command JSON / schema (`commandParser`, `checked`) | transport error | none | C3 bridge (open: the driver's parser + schema path) — label; blind transport cases | G3 (no history access before the parse) |
| M14 | batch (model) + `continue` | entropy demand pause → resume | suspension, resumption | OLD + shared | `FvapiProof.Store.ModelForecast.continuedRun_paused`, `continuedRun_final`, `continuedRun_error`, `continue_resumes` | G3 + EA40-FORECAST |
| M15 | enqueue / drain / cancel / completion / release-completion / close (both backends; `drain` passes `state.model.isSome`, `DevRuntime.lean:449`) | queue tickets → batch | success, busy (`queue_pending` = a direct apply/batch while tickets wait, `DevRuntime.lean:877–883`), refusal | OLD + NEW | C3 drain bridge (open, label) + `FvapiProof.Store.AdmissionResident.drain_charge_le_queue` (cost) + `productionSurfaceConforms` (privateBatch: the pure drain's batch) | assembly obligation EA40-QUEUE (owner MAIN, U4A E-A40 assembly, acceptance = the composition theorem covers the drain path, pure + model) |
| M16 | init / open / recover; crash → recover (model) | startup | success, corrupt | OLD (rebuilt) | `FvapiProof.Store.StartupExact.startup_exact` | T-ofList (EA40-STARTUP) + G3 |
| M17 | pin / release / read / page / read-object | reads | success, refusal | OLD | `productionSurfaceConforms` (readSnapshot/pageSnapshot/pagePinned/emitPage) + `FvapiProof.Store.ModelCursorDemand.firstPageDemand_run`, `continuePageDemand_run`, `emitBoundPageDemand_run` | T-out (EA40-OUT) + G3 |
| M18 | export | snapshot | success | OLD | `FvapiProof.Store.SnapshotExact.snapshot_exact` | T-out + G3 |
| M19 | import (model; pure = invalid) | fixture image → State | success, refusal | OLD (built) | dev-only loader (installs persistence alone; open → startup replay builds the State ⇒ replay-reachable States alone, `DevRuntime.lean:660–678`): §6a + blind cases | T-ofList + G3 |
| M20 | configure, counter, clock, stage, cut, faults, observe, diagnostic-page/-release | no history family read or written | n/a | none | unchanged (G3 confirms no history access) | G3 |
| M21 | pure backend × open / recover / import / cut / continue / crash / faults | impossible: the pure backend answers `invalid` (`DevRuntime.lean:842–859` cut/continue/crash/faults, `:862–865` open/recover, `importFixture` `:660–663`); close/enqueue/drain + the ticket operations stay valid on pure (M15); `directSupported` (`:877–883`) = the queue-pending guard for a direct apply/batch, not a capability list | — | — | — | — |

Plus (contract C8, unchanged): 5,178 blind cases (wt/tester-11 @ 68eeba1) + the model1025 witness on the closing driver;
the §6 differential; whole proof library green + root/axiom audit (`c2-check.sh --all`); final-driver C8b
(`.claude/rules/c8b.md` Regeneration) + every invalidated native/frame record.

## §6 Arbitrary-state differential (planned runner `tests/store/tierb/state-diff.py`)

§6a image/driver differential (reachable domain). Corpus (seed 0x7153) = 200 images: 100 valid = stock-exported stores
after seeded random valid command sequences (family lengths 0..512 where reachable within one import frame — every
image ≤ 1,024 files, §8 R6 —, duplicate keys, equal timestamps, empty families, attempt chains with version steps,
counters near their limits = tails near the seeded checkpoint threshold + the counter-skew corruption, §8 R6) + 100
corrupted copies (seeded
record/byte mutations of valid images: past-end covered prefixes, counter mismatches, out-of-order attempts,
duplicate records). Per image: import (model) → open (startup replay, `Startup.lean:289` ff.) → each of 8 command lists
(each §5 subtype once) from a fresh import + open → reply headers + post-state `export` digest. Reference = stock
192774d9, candidate = the arm, both model backend. Reported: accepted + rejected counts; a rejected image = the
identical error on both drivers; vacuity floor = ≥ 100 accepted images, else the cell fails. Feasibility: ≤ 1,800
import + open cycles per driver run through startup (O(H²) time: the store-walk proposal's K9 row) ⇒ size
ladder (§8 R6): rung 1 = 50 images, every family ≤ 16 (one with every family empty); rung 2 = 50 images, one dominant
family 65..512 before the fit (claim-dominant = one attempt chain), the others ≤ 16; the stock preflight times the largest image ×1 + projects the corpus;
cap = 4 h per driver run; a projection over the cap shrinks the ≤ 512 rung by recorded ruling before any arm run; a
cap breach during the run = INCOMPLETE (failed), never truncated to pass.

§6b logical-State domain (arbitrary in-memory States, incl. duplicate / out-of-order / past-end histories that replay
cannot build). Domain ruling: C1's closed refinements (`FvapiProof.Store.TierB.<reader>_listMeaning`, every changed
reader/writer, no premise the base lacks) = the property test over every State (`.claude/rules/tests.md`: a closed
proof = its property test). Any changed function without a closed refinement at C2 → an in-process RP differential
cell (seeded generated States with duplicates, out-of-order records, past-end prefixes; the arm function vs the base
body over the computable `toList` bridge, `FvapiSpec/StoreModel.lean`); list = the M2 diff's functions minus C1's
refinement roots, computed at C2. Distinct from replay-built blind cases. §6b credit is conditional: each
`_listMeaning` root passes the `.claude/rules/tiers.md` statement-faithfulness review (astra lane) with its vacuity
probe (no premise the base lacks, no assumption-shaped conclusion, a nontrivial witness per root) before it counts;
this ruling also lands in the contract (C8).

## §7 C10 runner inventory (qualification = commands + expected exits; firing logs recorded in each runner's `paths:` rule)

| runner | clean | planted child rc | planted count/verdict | early fail then clean | status |
|---|---|---|---|---|---|
| `tests/store/tierb/c2-check.sh` (+ `--all`: every FvapiProof/FvapiSpec/FvapiSelf module) | 0 | `--plant rc` (a nonexistent build target; built oleans stale-match) → 1; `--plant census` (bogus import) → 1 | `--plant root` → 1, `--plant reversal` (R-a base row) → 1, `--plant missing` → 1, approved-missing → 1; AxiomAudit `--plant` → 1; usage → 2 | `--plant rc` (later steps pass) → 1 | fired (lane 51f70bf; `.claude/rules/tierb-reversal.md`) |
| `hist-probe.py` (count/repeat/sweep/reader + §2 shapes) | stock f1 count → 0 | nonexistent driver path → ≠ 0; unresolvable `--symbols` entry → ≠ 0 | an entry below its minimum (count mode) → 1; a wrong exact constant → 1; registered-trace mismatch (V5) → 1 | R = 3 with repetition 1 planted to fail → 1 | V5 fired (21bd705); §2 shapes + pure sessions + per-phase minima = `m4-probe.py` D (§8 R4), qualified by `m4-qual.sh` d-* (a wrong exact constant = RP's rp-exact) |
| RP: owner `hist-probe.py reader` (byte grade: flat/grow today, `exact` to add); child = the native `HistReaderProbe` (emits regions) under `fresh-observe.py`/bpftrace | 0 | probe exits nonzero after emitting valid regions → 1 (red-first: `observe.run` checks bpftrace's own status alone, `fresh-observe.py:378–385`; the fix requires the probe's final status line); unresolvable region symbol / attach failure → 1 | a region called once (`calls != 2`) → 1; P-T region → 1; wrong exact expression → 1 | first size planted to fail, later sizes clean → 1 | qualified (`m4-probe.py rp` + `M4ReaderProbe.lean`, §8 R4) by `m4-qual.sh` rp-* |
| `tests/store/model/c8b-graded.sh` | per mode 0 | initial `lake build` (`:71`, `:100`, `:117`) failing while stale outputs match → today exit 0 (red, to record) → fix: builds through `step` → 1 | registry mismatch → 1 (fired) | build plant + clean later steps → 1 | exits 1/2/3/4 fired (A7); build fix fired red-first (lane 51f70bf; `.claude/rules/c8b.md` Build accounting) |
| blind runner: `tests/store/tierb/blind-lane.sh` (port of the scratch blind wrapper + `blind-run.sh`) | passing subset → 0 | a failing case → ≠ 0 (today: `echo "rc=$?"` last ⇒ wrapper 0: red, to record) | case count ≠ manifest → ≠ 0 | failing case first, passing after → ≠ 0 | ported + fired red-first (lane 51f70bf; `.claude/rules/tierb-reversal.md`) |
| `state-diff.py` (§6a) | stock vs stock → 0 | a driver child exiting nonzero without a reply → ≠ 0 | plant driver (one reader mutated) → 1; accepted count below the floor → 1 | first image differs, later images identical → 1 | qualified by `m4-qual.sh` sd-* (mini corpus) + the full corpus stock vs stock → 0 (§8 R6) |
| `tests/store/tierb/m4-run.sh` (every §2/§3 cell × R = 3 + aggregation; + `count:SHAPE` + `histcount:f1\|f2` + the arm hist map forwarded, §9 R14) | clean subset → 0 | a cell child exiting nonzero without its verdict line → 1; a missing verdict line → 1 | one planted failing cell among clean ones → 1; a count below its minimum → 1 | failing cell first → 1 | qualified by `m4-qual.sh` run-* (a count below its minimum = a registered-trace mismatch inside the cell: the complete-trace grade ⊇ the minima) |
| native/frame records invalidated by the closing driver (C8: "every invalidated native/frame record"): owner = the U4A-close store-control gate stage, aggregation runner `tests/store/tierb/native-records.sh` (planned); children = `tests/store/model/c1-roots.py` (`.claude/rules/c1-roots.md`), `c8-frames.py` (`cost-frame.md`), `input-probe.py` (`cost-input.md`), `resident-views.py`, `enqueue-sources.py`, `post-writer-guard.py` (their rules), `c8b-graded.sh` (`c8b.md`); each child keeps its recorded plants | all children clean → 0 | a child exiting nonzero → 1 | a child's verdict line missing or its count mismatched → 1 | first child fails, later children clean → 1 | qualified by `m4-qual.sh` nr-* (a nonzero verdict count misses the same zero-failure pattern as a missing line); full stock run with the c8b env = a separate job (`.claude/rules/tierb-m4.md`) |
| G3 review | judgment | — | plants P-T/P-R/B13 + G3-6..8 rejected | — | per reviewer-14 |

## §8 Stock preflight rulings (MAIN; stock evidence alone; before the first S2 commit)

Stock driver 192774d9 (= the lane build), blind tree 59186ef1, runners + logs + per-cell numbers = the runner commit
body. Each entry = the refuted or unrunnable prediction → the change.

- R1 model capacity (§2 feasibility refuted): attempt-bearing claims + admissions draw model temporaries from one
  ≤ 1,024-name tape per session (`DevConfig.lean:26`; the blind configure default = 1,024) ⇒ f4w A = 128: setup ok,
  the measured batch → `error:stopped` ×2; A ≥ 256: the setup update batch → `known_not_committed` / `stopped`;
  f3a/b/c n ≥ 128: the second 64-admit setup batch does not commit (driver generation 3 / operation 67 vs oracle
  4 / 131). ⇒ model grids f3a/b/c n ∈ {16, 64}, f4w + f4r + N6-A A ∈ {8, 64}, f4o unchanged; `-pure` cells carry the
  frozen grids (§2 note). Largest stock setups: f4w-pure 512 180.1 s, f4r-pure 512 227.4 s, N6-A-pure 512 322.8 s,
  f3x-pure 256 ≤ 38.9 s (cap 600 s).
- R2 `Row.Shape` annotation (§2 f4w, §3 controls): the stock decision allocates 96·A + 1,140, peak 48·A + 24, per call
  (RP N2s warm, A 10²–10⁵ exact), not 48·A ⇒ the event-list plant's expected slope = 96·A alloc, 48·A peak; grades
  unchanged.
- R3 T1-err root (§2): `sealGenesis` + synthetic OLD authority events fail decode (`corrupt payload`) before
  `refreshViews` runs ⇒ root = `startup` over a driver-exported f1 H store (CURRENT + objects), its `.entries` view
  tampered alone. Stock: results [1, 1] (the `.corrupt .graph` exit), `refreshViews` warm (live, peak, alloc) =
  (0, 24, 24) at H 10² + 10³.
- R4 harness names (§0, §7): D = `m4-probe.py` over `hist-probe.py` (imported unchanged); RP = `m4-probe.py rp` +
  `M4ReaderProbe.lean`; W4 stays with `hist-probe.py reader`; §6a = `state-diff.py`; aggregation = `m4-run.sh` +
  `native-records.sh`; qualification = `m4-qual.sh`. §7 mapping: D's "wrong exact constant" = RP's `exact=S` plant;
  inside `m4-run.sh` cells, "a count below its minimum" = a registered-trace mismatch (graded runs carry exact
  per-window counts; minima grade the count programs).
- R5 §3 constant: c ≤ 64 B binds W5 + N2s, inputs + callback results prebuilt outside the region (the stock evolve
  region built its `next` Attempt inside: 48·A + 112 → 48·A + 48 once prebuilt); graded on the raw warm region (no
  `c_R`). N3s's region = the whole update decision (`decide structuralPolicy`): stock 272·A + 16,740 (a) and
  248·A + 16,756 (b), exact at A 10²–10⁵; the intercept = the decision's fixed cost outside the history
  representation ⇒ N3s grade = flat in A, c recorded.
- R6 §6a corpus (the ≤ 512 rung refuted): the dev protocol caps attachments per frame at 1,024
  (`DevProtocol.lean:59`) and an import frame carries one per stored file ⇒ an image past 1,024 files is refused
  (`rc 2`; six families at 35 = 1,006 files imported, at 72 = 2,139 refused). Valid images = built on the pure backend
  + exported (backend-independent), cycled in model sessions (cycle ids from 1,000,001: no collision with the build
  tape; the bound World's counters = the open summary's); each image regenerated from its seed with scaled-down caps
  until ≤ 1,024 files (final caps recorded per image); rungs per §6a; seeded tail limits 64 | 1,024; families stop
  where no open row remains; one corrupted copy per valid image (byte flip | dropped record | past-end view | counter
  skew | out-of-order attempts | duplicated history item, the last two relinked up to a re-selected generation);
  store counters near 2^53 − 1 are unreachable by command sequences; a failed import/open ends its image; accepted =
  opened on both drivers + lines equal, a valid image's lists error-free. Histories past the import cap stay covered
  by §2 (H to 10⁴) + the blind model1025 witness. Stock: build 813 s (files 33..1,021); stock vs stock: valid 100
  accepted, corrupted 96 rejected (identical errors) + 4 accepted on both (3 drop, 1 flip), differing 0, vacuous 0;
  1,576 s / 1,498 s per driver run (cap 4 h).
- R7 T2 grade (§2): the observer attributes births per window, never per allocator route (its mode changes the
  required symbols alone; every present allocator entry is probed, `fresh-observe.py:57–75, 258–282`) ⇒ "GMP/libc
  births inside `overflowing` = 0" is graded as every SUB birth inside `overflowing` = 0 at each CHECK (a superset) +
  flat in H.
- R8 call counts (stock count programs; minima hold, notes corrected): `updateRow` runs twice per accepted update —
  the `UpdateStructure` `Row.Shape` conjunct builds the updated row (`Commands.lean:166`), `propose` builds it again
  (`Apply.lean:100`) ⇒ f4w/f4o/N6-A writer E4 (was 2), f4r E2 (was 1); the nested-append stock red = 2 × 24·A per
  accepted update. `buildCheckpoint` runs once per index kind ⇒ 8 per checkpointing seal pass (T1-op setup 2 = 16,
  T1-by F8 R8; was 2). T3's `deliveryEventsExact` (2) = per pass (F2 R2).
- R9 T3 stock (§2): stock `deliveryEventsExact` allocates nothing at D = 0 — (sub, subp, suba) = (0, 0, 0) at every
  CHECK (A k 0–3, B, C) at H 10², 10³, 10⁴, subn 1–4 (2 per pass, R8), verdicts ok, R = 3 digests + rows equal ⇒
  "stock red: a closure per authority event at D = 0" is refuted: that closure is the S2 spike's (reviewer-14 G3 F5:
  S2's callback allocates a closure per OLD authority event, even with empty deliveries). Instrument control for the
  empty finding: the frozen S2 spike driver 7d8b86d2 on the same cell → births inside `deliveryEventsExact` 64·H + 128
  at A k=0 (H 10², 10³), subp 128, sub 0, replies = stock's ⇒ the observer sees births in this role. T3 keeps its
  grade, roots + plant; stock = green; the cell's red = the per-authority closure plant.

## §9 Post-arm matrix rulings (MAIN; arm diagnostics + stock replays; after the first S2 commit)

Arm evidence = lane 236ce32 (driver 349571cc) + workspace-only variants; stock = 192774d9 (`sha256sum -c`); logs +
numbers = the ruling commit body (archives `.scratch/u4/w3/tierb-preflight/{k3v3,k3d,k3var,k3g,k3f}-job.*`,
gitignored). Review: consultant-62 on MAIN's drafts (2 sound / 4 revise / 2 unsound) + advisor. Each entry = the
frozen check that errs against the contract, its recorded firing, the change; the frozen checks' reds stay recorded.
No arm credit comes from these diagnostics: the closing matrix runs on the frozen arm driver of record.

- R10 K3 semantic region + NEW-width strata (§1 T-drop + T-K3, §2 T1 + T1-err, §4). Firing: sizing at the seals
  (outside the region): T1 flat at 1,472 B while the region omits the per-seal NEW sizing (117,324 B); sizing inside
  (variant S-in): T1 (A k=1 suba) 118,796 / 118,796 / 119,020 B at T = 100 / 400 / 1,000 and T1-err refresh 11,958
  vs 12,014 B at H = 10² / 10³ = NOT-FLAT on the NEW operation numbers' digit width alone; T1-by flat (one width);
  within one width S-in is flat (T1 {100, 400, 900} 118,796 ×3, T1-err {10², 900} 11,958 ×2). C5/C6 forbid OLD-sized
  refresh work, not a NEW counter's extra printed digit ⇒ the unstratified "flat in T | H" errs against the contract.
  Change: both seals pass their exact NEW authority suffix + its encoder to `refreshViews`, which sizes it once per
  invocation before its kind loop (semantic extent = NEW sizing + per kind: covered guard, running total, threshold
  decision, view update; `buildCheckpoint` = T-K2, recorded apart; the symbol census-resolved on driver + probe). T1 +
  T1-err grade flat WITHIN each fixed-NEW-width stratum, never across: T1 {100, 400, 900} + {1000, 1010, 1020}; T1-err
  {10², 900} + {1000, 1020}. Width constancy per stratum = a fixture fact asserted by review: one setup batch
  (`hist-probe.py` BATCH = 1,024 ⇒ a fixed generation), operation numbers 3 | 4 digits by construction. Stock
  feasibility: f1 completes at 1,010 + 1,020 with reopen ok; stock T1 red in both strata (A k=1 suba 20,170,656 →
  173,028,256 B over 100 → 900; 192,138,144 → 195,977,504 B over 1,000 → 1,020; T = 1,000 = the sealed record).
  T1-err: the first kind's covered guard throws `.corrupt .graph` after the NEW sizing, before that kind's running
  total / checkpoint / update work; roots `refreshKind_guard` + `refreshViews_guard`, adapted to the new signature.
  Its frozen plant (the covered check moved after the kind's suffix sizing) is retired: covered = H + 2 on a next
  authority of length H + 1 ⇒ `Hist.drop` = [] ⇒ nothing H-sized to detect. Replacement = realized pre-guard OLD work
  (an OLD-spine materialization or OLD re-encode before the guard, realized in the emitted C, `.corrupt .graph` kept,
  its length/count predeclared, a nonzero byte-grade exit). A seal-hoisted OLD copy runs before the region ⇒ the
  seal boundary = a §4 G3 row (both seals); T-drop charges both seals' NEW suffix; T-K3 = one sizing print per NEW
  authority event per seal invocation (model forecast + real = 2; composed once with EA40-FORECAST).
- R11 T1-op fixed-branch cohorts (§2 T1-op). Firing: arm RV − BC [1,472, 1,088] (S-in [118,796, 118,412]) = a 24 B
  per kind-refresh branch contrast with no OLD work (emitted C,
  `.scratch/u4/w3/tierb-preflight/refreshKind-emitted-c.txt`: the checkpoint branch reuses `buildCheckpoint`'s
  unshared `Except.ok` + pair and allocates `some` + `IndexView` =
  56 B; the view-update branch allocates `IndexView` + pair + `Except.ok` = 80 B, its OLD view being shared; 16
  kind-refreshes per setup) ⇒ the frozen cross-branch equality fails without OLD work, and any cross-branch difference
  is blind to a both-branch OLD-tail copy (24·16·64 vs 24·16·65 B cancels the 384 B contrast: 26,048 B each). Change:
  §2 T1-op = 8 fixed-branch cells, each cohort exactly flat across H and t, no cross-cohort subtraction, no slack; the
  original pair = the branch-boundary semantic + reopen check, its cost contrast recorded. Stock feasibility (scratch
  shapes, X = 100·H + t): every cell reaches its branch (BC 0 ×4 | 16 ×4; the t = 64 setup does not checkpoint),
  reopen ok; cohort N red (7,055,552 / 12,787,712 B at t 32 / 62, flat in H), cohort C green (1,120 B ×4). Controls
  before credit: (i) OLD-tail copy + (ii) OLD re-encode placed before `refreshKind`'s branch test (one build each
  serves T1, T1-by + both cohorts; t variation rejects them), a checkpoint-path-only plant, a whole-history plant (H
  variation rejects it); each realized in the emitted C with its predicted delta declared before its run; plant (iii)
  re-fired on the closing matrix.
- R12 qualification re-base (§7, `m4-qual.sh`): with the NEW sizing inside, the t1err region = 11,958 B (> the c ≤ 64
  of `exact=0`) and width-dependent across 10² / 10³ ⇒ `rp-clean` grades an N2s region (c ≤ 64); every t1err plant +
  run-* cell uses the one-width grid {10², 900}; qualification #6 reruns with the runner edits.
- R13 framing (§0): a role = its semantic extent, declared with the terms its region leaves out (not a symbol alias);
  §8 stays stock-only.
- R14 allocator reach (stock eager id list → arm on-demand membership; review consultant-63 (1 sound / 4 revise
  / 2 unsound on v1; its recommended ruling adopted) + advisor; §0 positive-count rule + role map, §2 f1r /
  f1r-pure / W3 / f3c / f3c-pure alloc minima + the pure-cell note, §7 hist-probe + m4-run.sh rows). Firing (frozen
  arm driver a3b56f8f; records stay): count minima FAIL f1r `allocatedHas` E,F,R [0,1,1] vs [1,0,0], W3 [0,1,1] vs
  [1,1,1], f3c [0,0,0] vs [1,1,1], f3c-pure P 0 vs 1 (f1r-pure P 1 ok on the unboxed entry alone); hist:f1 + hist:f2
  INCOMPLETE at every H (`bad window`: the stock hist map's `allocatedIds`, absent from the arm). Cause: stock
  `allocatedIds` materializes row + answer ids before a command's draw; C5 forbids that OLD-sized list, not a phase.
  On the arm, binding `used := allocatedHas s` constructs a closure (not membership); membership runs per valid
  candidate at the draw through two compiled routes: B = `allocatedHas___boxed` (clang inlined the body; the
  state-only predicate's closure) and U = `allocatedHas` (direct calls from the new-row answer's
  `id == row || used id`, non-equal branch). Each successful fresh id draw on these fixtures (oracle tape: valid,
  distinct ids) evaluates membership once; the model suspends before the candidate and resumes once each in F and R,
  pure runs once. The frozen floors encoded the stock list's eager placement; the runner checked one mapped symbol.
  Change:
  (a) acceptance profile `lazy-alloc` in `m4-probe.py` beside SHAPES (`--profile lazy-alloc`; default `stock`); a
  symbol map supplies names + registered traces alone (a `minima` key → rc 2); under `lazy-alloc` the five shapes'
  alloc role = exactly [U, B] (else rc 1).
  (b) per-entry floors, U | B | total: f1r (0,1,1) | (0,1,1) | (0,2,2); W3 (0,1,1) | (0,2,2) | (0,3,3); f3c (0,0,0)
  | (0,2,2) | (0,2,2); f1r-pure P 1 | 1 | 2; f3c-pure P 0 | 2 | 2. E ≥ 0 = a minimum (E = 0 recorded, not graded).
  The existing per-entry count programs stay; graded SUB tuples, order, registered traces + byte criteria unchanged.
  (c) pure runs once ⇒ the f3c-pure allocator floor = P ≥ 2 on stock + arm (stock executable floor 1 → 2; the §2
  "model per-phase sums" note errs for pure; its other pure discrepancies stay recorded, not waived).
  (d) census binding under `lazy-alloc`: U + B present at distinct addresses, no direct call/jmp between them (the
  one property the per-entry runtime floors cannot show: a nested entry counts twice); rebind after any codegen
  change.
  (e) hist:f1/f2: committed arm hist map `tests/store/tierb/m4-arm-hist.json` (the stock map, alloc [U, B]) whose
  traces are PREDICTED by the S2 spike grading record (f1 A [6,11,15,20], f2 A [5,11,14,20], B [11], C [20]),
  forwarded by `m4-run.sh --hist-symbols`; before its first byte grade, `m4-probe.py hist f1|f2` = hist-probe count rc
  0 + exact role counts (writer 4, reader 10, alloc 6 | stock 3) + trace = the predicted one; a mismatch = a matrix
  error → ruling, never a refit.
  (f) the closing record = one driver's count receipts (`m4-run.sh` cells `count:SHAPE` at each grid's first point
  + `histcount:f1|f2`, in its default set) + census + byte/repeat cells; hist sweeps run R = 1 per H, hist `repeat`
  ×2 (claimed as run).
  (g) qualification #8 (m4-qual.sh + ARM = the next frozen arm driver + ARMPLANT built once from its tree): clean
  witnesses on ARM (count f1r 100 `lazy-alloc` rc 0, hist f1 100 rc 0); binding plants (alloc [U] → 1,
  [U, latestRow] → 1, a `minima` key → 2); hist forwarding graded on the cell's log, not its exit (arm hist flatness is
  unmeasured): the map forwarded ⇒ no `bad window`; f1's trace altered ⇒ the `subn … want` line on f1, none on f2;
  native membership skip = ARMPLANT (both allocators gate `candidate == "f"×32 && used candidate`: valid hex outside
  the tape, the call reachable; its emitted C + objdump checked first: both routes' sites + the closure present):
  count f1r, W3, f3c, f3c-pure → rc 1 with U = B = 0 + the exact failed floors, tags + normalized digests = ARM's;
  hist f1 → rc 1 (alloc 0 ≠ 6). The v1 map plants are retired (non-discriminating).
  (h) credit: the five counts + hist f1/f2 counts rerun on a3b56f8f under `lazy-alloc` (no build) = the same binary
  red under the frozen check, green under this one; that + qualification = tool credit alone; arm credit = the
  closing frozen driver's matrix of record.
- Register (separate dispositions): f4 map's shared host (`latestAttempt` + `attemptEvolutionDecidable` → one host
  counted twice; historical tuple/trace kept); named hosts (callerBindingsDecidable, conflicts, descriptor membership,
  updateStructureDecidable, meaning): host reach ≠ each predicate's reach; hist `prefixGeneration` named in §2 f1/f2,
  absent from hist-probe's program; §7 "complete-trace grade ⊇ the minima" refuted by the four count reds (→ f).
