# Computational notebook

Premise = an executable investigation, request cells + rendered evidence; the order tells the verification story.

Palette: paper #ffffff; desk #edf0f5; ink #24334b; notebook blue #244cb0; success #176443; caution #855400. Error text uses ink + explicit Reject label rather than a seventh color.
Typography: system sans for prose (14/20, headings 28/34); system monospace for editable requests + literal proof text (13/20). Prose measure ≤72ch.

```text
fvapi / Notebook                       API v0
[Outline]      Verification walkthrough
 Catalog       Run the requests. Inspect the evidence.
 Entry         [Run all cells] [Add cell]
 Lookup        In [1] [catalog   ] [Run] [Up] [Down]
 Check         | request editor                    |
 Demand        Out[1] catalog table
 Answers       In [2] show …
               Out[2] claim / statement / closure
```

Notebook-specific: execution prompts in left gutter, mutable request cells, outputs never replace inputs, evidence stays beside the request that produced it. Ordered execution markers describe an actual sequence. Blue rule = active investigation, not a generic card grid. Flat square editors, no shadows, no animation. Outline links scroll through the same document, not separate dashboards. Pre-filled walkthrough includes deliberate failed input + demand review.

Finish: catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers, mobile PNGs inspected. API fixtures remain the only response source. All controls keyboard-operable; narrow layout removes outline + moves gutter above cells.

Validation: node --check + git diff --check pass. Neo: 10 initial cells render; accept + reject both present; edit accepted input → reject; move first cell down → entry first; Add cell → 11 cells; desktop horizontal overflow = false. Captured error + unhandled-rejection events during these interactions = 0; initial-load console errors = not checked. Mock catalog = 3 entries; UI renders all returned entries. Bundle downloads + live log mutation = unconfirmed (mock omits bundle route + returns static log fixtures). Screenshot inspection = 11/11 PNGs opened: catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers, mobile. Captured DOM assertions = 10/10 expected outputs, no request-execution failure copy. Mobile at 390px = no horizontal overflow; outline hidden; cell controls + re-check output fit. No blank captures. Critique: quiet executable-paper presentation makes the investigation legible; evidence-heavy cells remain long, and editing weights requires scrolling inside the JSON editor. Initial-load console collection + download execution remain unconfirmed.
