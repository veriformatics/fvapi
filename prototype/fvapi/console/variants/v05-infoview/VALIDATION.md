# v05-infoview validation

| Target | Result |
|---|---|
| Catalog | pass: all 3 entries returned by mock, capture inspected |
| Entry | pass: claim, API statement at file:line, closure SHA-256, replay command + copy control, axioms, licence + notices, source; capture inspected |
| Recorded | pass: full GLM fixture, explicit “Recorded; not re-run by fvapi”; capture inspected |
| Lookup hit | pass: spec_id vf.contrast-2x2, HTTP 200; capture inspected |
| Lookup miss | pass: HTTP 404, “logged as demand”; unrelated evidence cleared; capture inspected |
| Check accept | pass: API example_input, HTTP 200 accept; capture inspected |
| Check reject | pass: first row's first weight changed to 1, HTTP 200 reject; capture inspected |
| Check 409 | pass: fva.edger-cpm, HTTP 409; selected entry's recorded state shown; capture inspected |
| Demand | pass: misses + by_key counts from API; capture inspected |
| Answers | pass: answer log from API; capture inspected |
| Mobile | pass: 390 px, stacked statement + infoview, local horizontal code scrolling; capture inspected |
| Browser errors | pass: Neo window error + unhandledrejection arrays empty across 10 desktop states; console stream not collected |
| JavaScript syntax | pass: node --check app.js rc=0 |
| Relative API + offline assets | pass: positive relative-fetch control expected 1 = 1; external runtime URL search expected 0 = 0 (rg rc=1); bundled OFL IBM Plex Mono |
| Manual interaction | pass: Run check → accept; editable input {} → reject; Restore example → accept |

Run = `python3 prototype/fvapi/mock.py 8455`; URL = `http://127.0.0.1:8455/console/v05-infoview/`. State selector = `?state=<state>`; mobile uses entry.

Captures = primary repo `.scratch/shots/v05-infoview/`: `catalog.png`, `entry.png`, `recorded.png`, `lookup-hit.png`, `lookup-miss.png`, `check-accept.png`, `check-reject.png`, `check-409.png`, `demand.png`, `answers.png`, `mobile.png`. Each captured via webcap, opened + inspected at final state; matching DOM snapshots alongside.

Limits: mock = immutable fixtures; request actions do not mutate its logs. Mock catalog has 3 entries, not the live store's eventual set. Mock lacks bundle downloads; link targets the API contract but download is unconfirmed here. fva.edger-cpm has summary only in mock; GLM has full recorded fixture. Vflab integration, clipboard permission behavior, full console stream + automated accessibility audit not checked. No motion; native form controls + explicit focus outline. Long source paths wrap in explorer; literal theorem text scrolls inside its buffer on narrow screens.

Distinctness: proof-assistant file explorer + source buffer + infoview, rather than metrics or cards. The statement's original line numbers and the adjacent replay/axiom boundary are the organizing structure.

Notify-set edits = none.
