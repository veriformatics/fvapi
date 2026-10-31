# v05-infoview

Premise = proof-assistant workspace: explorer → statement buffer → evidence infoview. Read a theorem and its trust boundary together.

Palette: editor white #ffffff; pane gray #f3f5f8; ink #263344; Lean violet #6337a6; selection blue #e5efff; success green #216544. Errors = ink + explicit text, recorded = violet + explicit warning.
Type: system sans 13/15/20/26 for controls + prose; bundled IBM Plex Mono 13/14 for Lean, paths, JSON + hashes (domain syntax, not decorative labels). Font = unmodified `fonts/IBMPlexMono-Regular.ttf`, SIL OFL 1.1 (`fonts/OFL.txt`); source = google/fonts `ofl/ibmplexmono`.

```
┌ fvapi / proof workspace                        API fixture ┐
├ Library explorer ┬ Catalog | Statement | Request ┬ Infoview ┤
│ filter           │ file tab / file:line          │ Replay   │
│ entry            │                              │ Axioms   │
│  closure file    │ line gutter / Lean theorem    │ Closure  │
│ entry            │                              │ Licence  │
│                  ├ Messages / API response       │ Source   │
├ Demand / Answers ┴───────────────────────────────┴──────────┤
│ Ready / API path / caller must replay                       │
└─────────────────────────────────────────────────────────────┘
```

Identity: file tabs are actual closure paths; line gutter starts at the statement's API line; evidence stays adjacent, never collapsed into a green trust badge. An explicit recorded warning replaces the replay state, not a faint tag. Request output occupies the editor's messages area. No motion, shadows, gradients or decorative metrics. Mobile = explorer becomes a compact selector; buffer and infoview stack.

Finish = live relative API reads; all required routes/states; 11 inspected captures; syntax check + browser error evidence; worktree commit. Evidence = VALIDATION.md (validator input to lead's harvest).
