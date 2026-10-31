# Trust chain

Premise = inspect every answer as a chain of caller obligations; fvapi's search stays outside the trusted base.

Palette: paper #f5f6fb; ink #202b49; blue #304f93; boundary #637392; amber #8a4b08; white #ffffff. Blue = caller-checkable link, amber + dashed edge = recorded/unavailable link; labels carry meaning independently.
Type: system sans for reading (16px base, 24px section, 40px headline); system monospace for statement text, commands + hashes (13px). Content prose ≤76ch.

```text
fvapi / Trust chain                     Prototype / live API
Catalog | Look up | Run check | Demand | Answers
What can you check?                 [fvapi: untrusted search]
[claim                              ]    outside the chain
  │
[statement — you read                ]
  │
[closure — you hash                  ]
  │ solid / dashed recorded
[replay — you run                    ]
  │
[axioms — you accept                 ]
  │
[kernel + toolchain — you trust      ]
```

Catalog = compact parallel chains, not cards; each shows claim → replay status → toolchain. Entry expands one chain. Lookups supply or break the claim link. Checks keep a server verdict outside the chain and provide caller recheck instructions. Logs = request → result chains, never trust badges. Bold element = persistent indigo trust-base block at chain foot. Flat borders + visible connectors; no shadows, animation or decoration. Mobile folds off-chain note above the chain, preserves labels + wraps hashes. Keyboard focus = thick blue outline. Every API-derived string escaped; no data embedded.

Finish = live API data; catalog/entry/recorded/lookup-hit/lookup-miss/check-accept/check-reject/check-409/demand/answers/mobile screenshots inspected; browser errors checked where tooling exposes them. Screenshot status = 11/11 captured + inspected (catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers, mobile). Neo = required route states, clipboard copy, invalid JSON + injected network failure exercised; captured error/unhandledrejection arrays empty during normal state transitions. 390px layout = scrollWidth 390px; controls focusable + labelled. Actual text pair contrast ≥6.54:1; boundary 4.42:1. Syntax + diff whitespace checks = rc0. Initial rejection capture caught loading → explicit readiness awaited + recapture passed. Coverage = fixture mock only (catalog fixture contains 3 entries; all displayed); vflab + bundle download/replay not checked by this variant build.
