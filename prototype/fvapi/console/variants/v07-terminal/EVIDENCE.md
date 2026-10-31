# v07-terminal validator input

Run = `python3 prototype/fvapi/mock.py 8457`; URL = `http://127.0.0.1:8457/console/v07-terminal/`.
Screenshot root = `.scratch/shots/v07-terminal/`.

| State | Capture + inspection |
|---|---|
| catalog | catalog.png; inspected; complete 3-entry fixture |
| entry | entry.png + entry-full.png; inspected; claim/statements/closure hashes/replay/axioms/source/licence/notices visible |
| recorded | recorded.png; inspected; prominent recorded stub / not re-run warning |
| lookup-hit | lookup-hit.png; inspected; match id + full entry |
| lookup-miss | lookup-miss.png; inspected; HTTP 404 + logged-as-demand |
| check-accept | check-accept.png; inspected; editable JSON + accepted result |
| check-reject | check-reject.png; inspected; one edited weight → rejected / incorrect_weights |
| check-409 | check-409.png; inspected; HTTP 409 + choose a checker fix |
| demand | demand.png; inspected; misses + by_key count |
| answers | answers.png; inspected; answer table + clickable ids |
| mobile | mobile.png; inspected; 390px; fixed prompt + scrollable table; no page overflow |

BrowserOS Neo = Tab id completion `show vf.` → `show vf.contrast-2x2`; Enter → statements/closure; Up → command history; desktop overflow=false. Edited first weight to 9 → Rejected; Restore example + Run check → Accepted. Mobile CDP 390×844 → document width=390; focus-visible rule present. JS parse = `node --check terminal.js`, rc 0. Console errors = not checked (webcap lacks console output). Captures = 11 required states + entry-full.png; webcap batch rc 0. Text contrast = 6.51:1 minimum across all four text colors against both surfaces; computed sRGB relative luminance. Evidence validator = seeded 10 open rows (rg rc 0), final 0 (rg rc 1); 12 PNG positive control. No motion used.

Font = vendored Liberation Mono Regular, SIL OFL 1.1; FONT-LICENSE. Terminal background = blue slate rather than near-black; mint + copper reflect answer/replay states. Data = relative live `/v0/` routes only.

Known limits = mock catalog has 3 entries, not 5; recorded full fixture available only for GLM; mock bundle endpoint absent; local download/replay intentionally delegated to API + CLI. Query `?state=<state>` drives screenshot paths. No shared instruction/spec files edited.
