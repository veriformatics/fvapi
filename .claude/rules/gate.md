# Gate

- Gate = `tools/vflab-run bash tools/gate.sh` (user ruling: all fvapi work — builds, gates, spikes, tests — runs on vflab; this overrides the global `offload run` default for this repo; the desktop runs no fvapi build or check). Iteration = `tools/vflab-run bash tools/fast-gate.sh` (never the claim). Any other command that builds or runs fvapi code → `tools/vflab-run <cmd>`. Contract + predicates: `docs/contracts/U1-foundation.md`.
- `tools/vflab-run` needs `fvapi_gate.slice` on vflab (`bash tools/bootstrap-vflab.sh`, idempotent, asserts the live cgroup limits). Exit = the command's status; 125 = sync or output mapping failed; a signal, OOM kill or timeout (`FVAPI_VFLAB_TIMEOUT`, default 7200 s) never exits 0.
- CI gate, once `main`'s CI is green: `bash tools/ci-gate.sh <unit>` (push `ci/<unit>`, green only when every shard job succeeded, branch deleted when green). Until then the full gate runs on vflab alone.
- Gate timings on vflab (U2 P3 merge, in-gate): full 523.6 s — `blackbox` 331.9 s (204 black-box cases, parallel workers; speedup = `.agent/deferred.md` row), `probes` 147.1 s (69), `profile` 17.9 s; fast gate 4.3 s. U1 baseline: full 16.5 s, fast 1.2 s.
