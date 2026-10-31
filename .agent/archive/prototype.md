# PROTOTYPE — whole product (closed into ITERATE)

- Built: v0 API on vflab (FastAPI/uv, store `/srv/data/fvapi`, 5 seed entries: `vf.contrast-2x2` real replay + checker, 4 fva entries recorded), `fvapi` CLI (fetch/replay/check --recheck), console.
- Console path: 16 variants (10 conventional, 6 unconventional; commit 8e99fce) → 6 finalists → user pick u02-instrument-panel × v10-dependency-graph → 5 combinations → user pick `c1-panel-scope`. Retired code = `git show 9d0aeb6^:prototype/fvapi/console/variants/<name>/` (retired in 9d0aeb6).
- History: the first three local commits carried private fixture text + a study id → folded into 40c5bb6 before first push (one-off `git commit-tree` replay, trees byte-identical; script not kept).
- Teammates: builder-1..3, 16 variant builders, 5 combination builders, operator-1, navigator-1, reviewer-1 (2 rounds), janitor-1 (3 sweeps). Findings fixed in-phase: live-order entry selection (v05), seed short-name resolution publishing a wrong statement name (fva.cert-sort), recorded CLI command PATH, code rsync never deleting, client KeyError on missing licence.
