# Review ledger — IMPLEMENT whole product

Rows = each unit's fixed check set, opened before its diff is read; status `open` | `pass` | `fixed <sha>` | `deferred <deferred.md row>`. The phase closes with no `open` row (CLAUDE.md `Engineering`: review terminates on a fixed check set).

| Unit | Check | Status | Evidence |
|---|---|---|---|
| U1 | contract: every G/R/K/C/F/P predicate of `docs/contracts/U1-foundation.md` evidenced by a run or a planted probe | pass (C1/C2/C4 live run: row below) | gate-probe 24 fired (control 0 / planted ≠0 naming cause / restored 0); vflab-run-probe 18 held; manual mutation evidence: 7 hand-written sed mutants of `Fvapi/Cli.lean` killed (6 by `lake test` + smoke, `run` swap by smoke alone); timings recorded; renovate validator rc 0 + planted lookbehind rc 1 |
| U1 | C1/C4 on GitHub: gate workflow green on `ci/u1`, `tools/ci-gate.sh` green; clean public clone runs `tools/gate.sh` green on vflab | pass | `bash tools/ci-gate.sh u1` rc 0: run 41258818345, commit 41b46e9, tree 0c36fc92, gate (lean) success 40 s, gate (checks) success 16 s, fan-out 40 s, branch deleted; clean clone of 41b46e9 on vflab: gate rc 0, 21.1 s |
| U1 | C2: CodeQL `actions` analysis runs green on GitHub | open | codeql.yml triggers on `main` push, pull requests + schedule: first run follows the user's push of `main` |
| U1 | correctness lens: each hunk read with its enclosing function; rc paths; quoting across ssh + systemd-run | pass | remote argv via `printf %q` for the remote bash + `--expand-environment=no` (literal `$HOME $$` held); FIFO filters started before ssh, statuses waited by PID; stage subshells keep `failed` in the parent; fanout awk flushes per step + job + top key |
| U1 | cleanup lens: fvTrace helpers reused, no duplicate logic between gate, fast gate + probes | pass | fetch-tools, install-lean, lean-style, pin-tool, ci-gate adapted from fvTrace; fast gate + probes call gate.sh stage functions; one copy helper per purpose |
| U1 | altitude lens: no special case on shared infrastructure | pass | signal + SIGPIPE handling set on the unit type, not per command; tool identity in fetch-tools, not per stage |
| U1 | security lens (MAIN): remote command composition, sudo `systemd-run`, workflow token + secrets, pinned downloads | pass | workspace id restricted to `[A-Za-z0-9._-]` before reaching the sudo command line; the command runs as `eturkes` (`--uid`), only unit creation is privileged; CI token `contents: read`, `persist-credentials: false`, no secrets, actions digest-pinned; scanner + elan-init + Node downloads sha256-pinned; residual: the Lean toolchain itself is fetched by elan from GitHub releases without a hash pin (as in fvTrace) |
| U1 | stack mutation tool: `fvamut` (pinned capsule, U2) over `Fvapi/Cli.lean` + `Tests.lean`, survivors ruled | open | U2 brings the capsule; the manual mutants above are interim evidence |
| U2 | contract: every P1–P7 predicate + the acceptance matrix of `docs/contracts/U2-trust.md` evidenced by a run, proof or planted probe | open | A = P1–P4, B = P5–P7 |
| U2 | tester-2 blind suite (differential oracle for `verdict`, profile id golden, replay CLI) merged red → green | open | wt/tester-2 |
| U2 | mutation credit for the policy tests + U1's CLI tests via fvamut (P7) | open | |
| U2 | correctness / cleanup / altitude lenses on each U2 commit | open | |
| U2 | security lens (MAIN): subprocess + tool invocation, status parsing, capsule acquisition | open | |
