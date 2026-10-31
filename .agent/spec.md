## Intent

fvapi is an API for formal verification. Someone who wants something formally verified can call it. When our private library can speed up the work, fvapi uses the library, and it still gives the caller everything that they need to prove the result true themselves. fvTrace and fva use fvapi, also for their own normal work. Future applications can use it too, including applications that other people write.

fvapi runs on `vflab`, a machine dedicated to it. vflab does the actual work, stores the artifacts and holds the library. While few requests arrive, vflab keeps working on its library and improves it. The Claude sessions that control fvapi run on the founder's desktop, and the fvapi repository lives there. The sessions use vflab for the work, for the storage of artifacts and for the upkeep of the machine.

## Artifacts

- `ops/vflab/` = vflab installer + checks: `VFLAB_CONSOLE_PASSWORD_FILE=<file> bash ops/vflab/build.sh` (Ubuntu ISO in `ops/vflab/dl/` → `ops/vflab/out/vflab-autoinstall.iso`; autoinstall config `src/autoinstall.yaml.in`, scripts `src/vflab/early.sh` + `late.sh`, checked against Subiquity's `autoinstall-schema.json`); QEMU test `bash ops/vflab/test/vm.sh <bios|uefi> <fresh|boot>` (`NOUSB=1` = no stick; SSH 2222 | 2223); `bash ops/vflab/write-stick.sh <serial>`; `bash ops/vflab/check-installed.sh offload@<host>` (14 checks, rc = failures). `ops/vflab/stick-22245a1e/` = the image installed on vflab (gitignored).
- `prototype/fvapi/` = PROTOTYPE (disposable): v0 API + `fvapi` CLI + console variants; contract `prototype/fvapi/API.md`, fixtures `fixtures/v0/`. Run: `bash prototype/fvapi/deploy.sh` (desktop → vflab: code sync, uv env, Lean toolchain, seed store `/srv/data/fvapi`, `fvapi-proto.service`) → console index `http://192.168.40.241:8441/`; client on vflab `bash prototype/fvapi/fvapi-on-vflab.sh catalog` (any `fvapi` subcommand; `fetch`/`replay` dirs live on vflab). Build seam (not an inspection surface): `python3 prototype/fvapi/mock.py` serves `fixtures/v0/` for variant builders.
- Console = `c1-panel-scope` (user pick from 5 u02 × v10 combinations): `http://192.168.40.241:8441/console/c1-panel-scope/` (`?state=<state>` drives each state); code `prototype/fvapi/console/variants/c1-panel-scope/` (`PLAN.md` = premise, palette, wireframe). Retired variants live in git history (`8e122af`, combinations before this pick).

## Decisions

- Name + scope (user rulings): `fvapi` = the hosted multi-user service that fvTrace's `Decisions` reserve ("separate paid product, other repo"): library endpoints first; compute endpoints (fvTrace's exact plan search past its local limit, verifier replays, large what-if sweeps) later, on rented hardware. fvTrace + fva gain the capability to call it, also for their own normal work.
- Openness (user ruling): everything that does not conflict with the moat is public (free GitHub CI); the library content stays private.
- Host (user rulings): vflab serves fvapi alone, never as an offload host (not even for formal-verification work). Ubuntu 26.04 LTS; plain root (LVM, ext4) on the SATA SSD (no TPM on the board; encryption low priority); the two NVMe drives = ZFS mirror `data` at `/srv/data` with native encryption (key on root, backup on the controller). Static 192.168.40.241 + DHCP; access `offload@` by key alone.
- Sessions (user ruling): Claude sessions + this repository live on the desktop; vflab does the work, stores artifacts and is maintained from there.
- Request-time answers use no LLM (subscription terms: Claude Code "Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf"; OpenAI's sign-in terms prohibit "Using one user's subscription to fulfill another user's requests") ⇒ lookups, proved checkers, CPU automation; LLM work = the library's own development, or paid API keys later.
- Prototype set (user rulings): v0 HTTP+JSON API on vflab + a browser console (catalog, request playground, bundle view, demand log) + `fvapi` CLI client that fetches a bundle and replays it; Python FastAPI via uv; runs + is inspected on vflab alone; real replay for one entry (`vf.contrast-2x2`, a factorial contrast checker importing `Std` alone), the fva seeds = recorded stubs labelled as such; console = full variant fan-out (≥10 conventional + ≥5 unconventional).
- Library content stays out of git (repo `veriformatics/fvapi` = public): code + formats are committed; entries, proofs, seed metadata + study details reach vflab's store through `seed.py` from local sources alone (seed manifest `prototype/fvapi/seed.local.json`, gitignored); fixtures + examples in git = synthetic, or drawn from public fva (Apache-2.0).
- Console direction (user ruling, from 16 variants): combine `u02-instrument-panel` × `v10-dependency-graph`. Keep from u02: verdict readout (a tad smaller than u02's), entry selector + editable input tray, chart-recorder log of answers + demand. Keep from v10: proof graph (entry → artifact → closure files → requirements + toolchain), lookup lighting the matched path + check lighting the checker node, demand misses as dangling nodes. Not kept: u02's enamel instrument material, v10's graph↔list toggle (an accessible text alternative stays, per the UI quality floor). Explored as 5 combinations; user picked `c1-panel-scope` (panel-led: selector, input tray + compact verdict readout, proof graph in an inset scope, recorder strip below). Open product questions (lookup multi-key semantics, caller rights on delivered bundles, axiom trust policy, repo LICENSE) wait until the UI is decided.
- Lookup (user ruling): every supplied key (`spec_id`, `artifact_sha256`, `statement`) must point to the same entry; any disagreement = a miss logged as demand, naming the mismatch (a proof about another build never answers).
- Delivered-bundle terms (user ruling): decided later; until then every private-library bundle states "provisional: internal evaluation only", and final terms are set before any outside caller receives a bundle.
- Re-check trust (user ruling): the API stays one request → answer + bundle; the optional re-check runs caller-side in the open-source client against a client-held axiom allowlist (default `propext`, `Classical.choice`, `Quot.sound`, caller-editable); the bundle's own axiom list is displayed, never trusted; plus an optional published container for a re-check independent of the caller's Lean install.
- Idle library work (user ruling): shown in the next ITERATE round as a visible stub (a demand item moving queued → being proved → added to the library); the real loop = IMPLEMENT.
- Code licence (user ruling): Apache-2.0 (`LICENSE`, canonical text); library content stays private and unlicensed.

## Tasks

- [x] c9f5d59 Server + store + seed + deploy to vflab (`prototype/fvapi/src/fvapi_proto/{server,seed}.py`, `deploy.sh`)
- [x] 376bc8e `fvapi` CLI client + real replay of `vf.contrast-2x2` (`src/fvapi_proto/client.py`)
- [x] 8e122af Console fan-out: 16 variants under `prototype/fvapi/console/variants/`
- [x] 9e7e1d0 Live contact sheet (operator-1) + screening → finalists (6, in Artifacts)
- [x] ae476e5 Combination round: 5 u02 × v10 combos, live QA + fixes, user pick = c1-panel-scope
- [ ] Integrate + run every artifact on vflab + webcap every console state
- [ ] Navigator pass + closing review → fixes, `.agent/deferred.md` rows, `Phase: ITERATE`
- [ ] Rulings into the prototype: lookup all-keys-agree, provisional bundle terms, client-side axiom allowlist (builder-3)
- [ ] ITERATE: re-check container (optional, published image) + idle-work stub in the console
- Deferred queue → `.agent/deferred.md`

## Phase

PROTOTYPE — whole product
