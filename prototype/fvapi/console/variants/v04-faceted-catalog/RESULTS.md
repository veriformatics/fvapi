# v04-faceted-catalog — harvest input

Run = `python3 prototype/fvapi/mock.py 8454`; URL = `http://127.0.0.1:8454/console/v04-faceted-catalog/`.

| State | Route hash | PNG inspected | Evidence |
|---|---|---|---|
| catalog | catalog | pass | 3 fixture entries, four facet groups, empty inspector |
| entry | entry | pass | claim + theorem + SHA256 closure + replay + axioms + licence + source |
| recorded | recorded | pass | full GLM fixture; explicit not re-run warning |
| lookup-hit | lookup-hit | pass | exact-match notice + selected result + full delivery |
| lookup-miss | lookup-miss | pass | logged-as-demand notice + no-matching-result inspector |
| check-accept | check-accept | pass | editable example + accept output + local recheck command |
| check-reject | check-reject | pass | changed first weight visible; reject output + recheck instructions |
| check-409 | check-409 | pass | non-checker selected; explicit no-checker error + corrective action |
| demand | demand | pass | request-by-key counts + recent miss query |
| answers | answers | pass | checker + lookup rows with answer id, time + verdict |
| mobile | catalog | pass | 390px stacked facets/results/inspector; no clipping or horizontal overflow |

Capture root = `.scratch/shots/v04-faceted-catalog/`; filenames = state + `.png`. Mobile = 390px; desktop = 1440px; full page.

Checks: JS syntax `node --check app.js` rc=0. Neo page runtime errors = [] through catalog, entry, recorded, hit, miss, accept, reject, 409 + logs. Filter checker → 1 entry; clear → 3. Lookup submitted via actual form → exact match. All response data fetched from relative `/v0/` routes.

Distinct = package-registry retrieval. One broad query area; trust-relevant facets; persistent result list + delivery inspector. Checker + activity secondary. Blue registry chrome, white work surface, amber recorded provenance; no dashboard metrics.

Limits: local mock verification only; demand/answer logs = fixed mock fixtures, not cumulative requests; bundle download route absent in mock (link follows API contract); source proofs not executed by this variant. Production deployment + bundle delivery unconfirmed here. Native clipboard click + exhaustive keyboard traversal unconfirmed. Keyboard Tab reaches brand with solid focus outline. Neo 390px emulation: no horizontal overflow. Text contrast ratios: ink/white 12.61; secondary/white 6.15; blue/white 7.27; amber/pale amber 6.05; warning/pale amber 7.86; pale text/blue 6.02 (WCAG luminance formula; all ≥4.5). Browser console log stream not checked; window error + rejection capture checked. No instruction/spec edits.
