---
paths:
  - "tools/**"
  - "tests/**"
  - "c/**"
  - "TestsU3B/**"
  - ".github/**"
  - "renovate.json"
  - "lakefile.lean"
  - "vendor/**"
---

# Purpose-built checks + their probes

- An edit to a check (gate registry + aggregation, `imports`, `lean-style`, `fanout`, `deps`, `renovate`, `meta`, `spec`, `cli`, `profile`, `inventory`, `vendor`, `native`, `fsync`, `wire`, `tools/fetch-tools.sh`, `tools/ci-gate.sh` `ci_missing`, the compiler options in `lakefile.lean`) reruns `tools/vflab-run bash tools/gate-probe.sh` (also the gate's `probes` stage): each check passes on a clean copy, fails on its planted input naming its cause, passes once restored. Firing record (U3 part B merge): 90 probes fired (75 base + 15 audit), 0 failed. A new check lands with its probe. `tools/gate-probe.sh --base | --audit` runs one set (no argument = both; the `audit` CI shard runs `--audit`); probe copies exclude `.tools/capsules`. The capsule root control (`tools/capsule-root-control.sh`, in stage `capsule`) holds a relative `FVAPI_CAPSULE_ROOT` to the same capsule as its absolute form.
- Stage `fsync` = `tests/fsync/native.sh` (the real external-object bridge under ASan + UBSan + leak detection: lifetime, guard, reused-descriptor controls) + `tests/fsync/driver.sh` (exact-byte IO through `fvapi dev fsync run` in the gate workspace); probes `fsync-lifecycle` (closed flag not persisted → names it) + `fsync-asan` (one-past write → `AddressSanitizer`). Stage `wire` = `tests/wire/Api.lean` (typed-record smoke) + `tests/wire/smoke.py` (driver controls, the 786,692-byte maximal request, 65,536-byte raw check); probe `wire-body-cap` (65,536 → 65,537 → `wire: check_over_cap`). Stage `tests-u3b` = the blind part B suite (`TestsU3B/run.sh all`); its ZFS case runs only with `FVAPI_U3B_ZFS_ROOT` (outside the portable gate, recorded per merge).
- Vendored C (`vendor/<name>/`) changes only through its vendoring script (`tools/vendor-hacl.sh [COMMIT]`: raw git blobs at the commit, per-file sha256 in `lock.json`); the no-argument rerun regenerating identical bytes + lock is the acceptance check for any pin bump. A Renovate pin PR edits `commit` alone and stays red on `vendor` until that script relocks it.
- An edit to `tools/vflab-run` or `tools/bootstrap-vflab.sh` reruns `bash tools/vflab-run-probe.sh` from the desktop (real host; U1: 18 held, 0 failed). Exit codes seen at U1: signal N → 128 + N, OOM + timeout → 1, refused workspace → 125.
- An edit to `renovate.json` records `tools/vflab-run bash -c 'npx --yes --package renovate@<release ≥ 7 days old> renovate-config-validator --strict renovate.json'` → rc 0 in the commit body (RE2 active: a planted lookbehind → rc 1).
