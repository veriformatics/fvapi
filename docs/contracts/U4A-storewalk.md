# U4A store walks — per-batch cost ∝ change: unit contract (rows FROZEN one at a time; consultant-67 reviewed all)

Tier: kernel (store production + proofs; no downstream re-check). Law: `.claude/rules/store.md` (frozen functions get
twins beside them + a refinement theorem; a reviewed-spec change = a `U4-tables.md` erratum + steward row + red-first
pair), `.claude/rules/suites.md`, `.claude/rules/tierb-m4.md`, `.claude/rules/c8b.md`. Rulings: `.agent/spec.md`
`Decisions` → Store ("Design first"; index checkpoints = reusable chunks). Design record: proposal v3.1 (consultants
64–66, two rounds; advisor) — scratch `.scratch/u4/w3/storewalk/proposal-v3.md`, cost packets = two reverse-dependency
runs over all 254 proof modules (`ReverseDeps.lean`). Decision rule R1: any whole-closure walk handles every edge
occurrence per batch (memo hits skip hash + decode, never the visit) ⇒ Θ(live) per batch ⇒ the seal walk becomes
incremental; each row's own bound is its obligation, not a consequence of R1.

Row status: FROZEN = acceptance fixed, code may start; DRAFT = revise per consultant-67 (`### S3`–`### S8`, scratch
`.scratch/u4/w3/consultant-67.md`) + a re-review before its code.

## Carried credit (no new store-walk code; closing frozen-driver grades still required)
K3 tail accounting = lane 2c72e6d (M4 T1 family retained); N2 overflow = lane 91fa41a (M4 T2 retained).

## Rows

| id | status | change | acceptance (before credit) | open contract rows |
|---|---|---|---|---|
| SW-V | FROZEN | `Valid` decisions of `BlobRef`/`AnyRecordRef`/`ObjectRef` via fast Bool twins + `@[csimp]` (no `String.toList`) | csimp equations (unconditional); emitted C of every caller on the closing driver reaches the fast decisions (no `lean_string_data` under them); RP Valid region 0 B; plant (csimp dropped) allocates | — (maxNumber parse retired: one init-time parse on c3eda97) |
| SW-K8 | FROZEN | seal suffixes by counter difference: chronological `dropLoop` with count = `counters.x − before.counters.x` (authority, audits, answers, revisions); pins' six lengths from counters + an explicit origins total | both production seals consume a PROVED before/after length-counter invariant, otherwise take the frozen path (never establish the fast premise by recounting OLD history on the hot path); the explicit origins total = `origins.length` at genesis/open and after every serial install, unchanged on rollback; at fixed NEW counts and value widths each reached suffix/charge-length path does work bounded by its NEW count (zero OLD length scans): graded at varied H with ≥ 2 unequal appended values (order) + a realized OLD-length control, the M4 §4 seal boundary included | — |
| SW-K1 | DRAFT | `LiveSet` (persistent `TreeMap ObjectKey LiveEntry`: count of edge occurrences + root mark, space, kind, length, the shared byte object) as a `SealedRoot` field; seal twin = pruned DFS over NEW keys with `traverse`'s semantics, edges into L checked by the validated-key lemma, counts + cascade; both startup routes (`afterCurrent`, the model's `afterVisit`) build L from the visit | `LiveExact` (key set = closure; counts; shapes; bytes = `data.observe`) at genesis, every seal, both startup routes; refinement: ok/err ⇔ frozen `finish` with equal error + equal state/data/layout/reference/current; publication: `needed` Nodup + byte equality ⇒ `cacheFor` yields the same sorted list (27 ModelForecast + 5 ModelDriver theorems transfer); pins: a read-side live view, lookup equivalence with `restrict`, charge value = today's `viewCharge`, retained bytes ≤ charge (native); controls: distinct-key, high-degree, OLD reactivation, alias (exact `.length`/`.expectedKind` error), cascade (a checkpoint rebuild drops a chunk tree) | holder-cost bound (per-holder L version vs charge); writer-only fields projected out of pins |
| SW-K5 | DRAFT | admission residency from L: membership twins of F `chargedBytes` and A `admissionBytes`; E-A55's queued/head branch kept | `…By (· ∈ L) = … (HashSet.ofList selected)`; the 10 + 7 admission theorems transfer | — |
| SW-N6 | DRAFT | (a) committed GenIndex (first introducing generation per logical ref, insert-if-absent in authority order) + a staged scan of the batch's own new events (counter-indexed); (b) structural certificates = the frozen `historyHead?` verdict, keyed by (stream, stored head value, validating backing); (c) semantic prefix certificates = stored items 1..n equal the exact expected projection (`.row`: `attemptValue` of attempts 1..n; `.evidence`: the receipt binding), established by a successful frozen meaning check; staged certificates created by each serial success, installed at commit, dropped on failure; revision index (caller, id, revision) for meaning `.row`; `attemptHead` count from the certificate | refinement of each twin to the frozen function under GenIndex/certificate exactness + the stability lemma (frozen verdicts stable when histories extend + records are added, none changed); M4 N6-A + T-rowcheck + T-headcheck graded: OLD allocation 0, per update O(new + depth); time O(new + depth + log H) | whole-update bounds restated after (b)–(c); same-batch lifecycle (a row updated twice in one batch) |
| SW-N4 | DRAFT | directory writer: path-local marked recursion — descend unmarked nodes; skip a marked (reused) subtree only when its candidate bytes are exactly present for the same founder, hash, fuel (`DirectoryStored`, established on both startup routes, preserved per write); otherwise the frozen path for that subtree | equal CandidateData + equal ref-check outcome; work O(new nodes × fan-out + lookups·log n) | — |
| SW-K2 | DRAFT | (user ruling) chunk format v2 in place: chunk = `{caller_id, index, items}`; the checkpoint record keeps `source`; chunks 512–1,024 items (one may hold fewer; split/borrow/merge); resident per-kind ordered projections (insert/replace/delete per committed event; a close deletes its open-miss item); a checkpoint writes changed chunks + the directory ONCE (one `appendDirectory` over the final chunk list + one `prepareDirectory`) | P21/P23 erratum (steward row; red-first production + spec pair); `CheckpointExact` unchanged; `ChunkSources` + `Startup.chunkSources` + `blockStored`'s chunk branch restated; per-kind delta lemmas (8); occupancy lemma; projection exactness; blind-suite corrections via the steward path (cases with small tail limits, codec samples, `image.validate()` chunk-source assertion, `include_unselected` export contents); cost per checkpoint per index = changed chunks × ≤ 1,024 items + the final directory (≈ 0.34 B per index item, static estimate) | staged vs final directory bytes priced on the built writer |
| SW-K7 | DRAFT | indexed delivery checker (deliveries keyed by operation) | refinement to `deliveryEventsExact`; time O(E + D) | — |
| SW-N25 | DRAFT | model ack history: O(1) push (Hist); retention = E-A25b's (kept by contract) | model cell flat per completion | — |
| SW-N26 | DRAFT | observation capture: running printed size, abort at min(byteLimit, 16 MiB) before materializing the rest; an aborted inline capture still selects the paged fallback; the paged path's preparation scratch gets its own bound | capture cells: scratch ≤ cap at every image size, both paths | paged-path bound |
| SW-N22–N24 | DRAFT | model image/path tables → keyed maps; barrier rescans → dirty set; whole-image accounting → running totals | refinement per lookup; model cells flat in image size | consumer list (ModelIO internals) |
| SW-N8 | DRAFT | admission closure walks: measured first (enqueue observer at two closure sizes, H varied apart) → designed or KEEP+TERM with its axis | before the proof barrier | its class |
| SW-K9 | DRAFT | startup: (a) U4A — both routes build L, GenIndex, certificates, projections; (b) U4B — linear-time startup twins (temporary indexes) | (a) before E-A40; (b) U4B acceptance | — |

## Order + barrier

Freeze prerequisites (before the proof barrier): each applicable row has its closing refinement to the frozen function
(SW-K2: to the steward-ruled v2 spec), real call-path grades + controls, staged/installed/retired owner bindings and
resource terms; N8 classified (and any resulting change done); the `csimp` gate stage audits every `@[csimp]` lemma's
axioms with a firing plant; C2 of record (lane b6b9009) stays graded against its original spec + roots; the combined
tree gets an independent statement-faithfulness review + the permitted-axiom closure; SW-K2's spec + production
red-first pair stays distinct from the steward-led blind correction. Closing evidence = the full existing Tier B C8
acceptance (frozen G2/M4 reach/count/bytes + plants, G3, C2/all roots + audit, §6 differential, blind suite + model1025,
every invalidated native/frame record), not a replacement; C8b regenerated on the combined frozen driver's actual
identities under `.claude/rules/c8b.md` once E-A40's composition targets are fixed, rebound on any later driver change.


SW-V (+ the `csimp` gate stage) → SW-K8 → SW-K1 + SW-K5 (+ pins, both startup routes) → SW-N6 → SW-N4 → SW-K2 → SW-K7,
SW-N25/N26, SW-N22–N24, SW-N8 → one combined implementation + evidence checkpoint on a new frozen driver → C8b
regeneration on that driver → the E-A40 memory proofs, once. C2's S2 checkpoint (lane b6b9009) stays identifiable:
each row lands as its own lane commit with its refinement theorem.
