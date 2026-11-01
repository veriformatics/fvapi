---
paths:
  - "tools/**"
  - "tests/cli/**"
  - "tests/renovate/**"
  - ".github/**"
  - "renovate.json"
  - "lakefile.lean"
---

# Purpose-built checks + their probes

- An edit to a check (gate registry + aggregation, `imports`, `lean-style`, `fanout`, `deps`, `renovate`, `meta`, `spec`, `cli`, `tools/fetch-tools.sh`, `tools/ci-gate.sh` `ci_missing`, the compiler options in `lakefile.lean`) reruns `tools/vflab-run bash tools/gate-probe.sh` (also the gate's `probes` stage): each check passes on a clean copy, fails on its planted input naming its cause, passes once restored. Firing record (U1): 24 probes fired, 0 failed. A new check lands with its probe.
- An edit to `tools/vflab-run` or `tools/bootstrap-vflab.sh` reruns `bash tools/vflab-run-probe.sh` from the desktop (real host; U1: 18 held, 0 failed). Exit codes seen at U1: signal N → 128 + N, OOM + timeout → 1, refused workspace → 125.
- An edit to `renovate.json` records `tools/vflab-run bash -c 'npx --yes --package renovate@<release ≥ 7 days old> renovate-config-validator --strict renovate.json'` → rc 0 in the commit body (RE2 active: a planted lookbehind → rc 1).
