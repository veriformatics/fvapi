# v07-terminal

Premise = browser terminal shares fvapi CLI verbs; proof inspection = a readable command transcript, not a dashboard.

Palette (a blue terminal modeled on a workbench console, not black phosphor):
- Workbench #22354D = canvas.
- Well #192A40 = command/editor surface.
- Chalk #E5EEF6 = primary text.
- Mist #A8BED3 = secondary text + rules.
- Copper #FFC79B = recorded/reject warnings.
- Seafoam #A4E5CE = live/accept/result emphasis.

Type = vendored Liberation Mono Regular (SIL OFL 1.1, FONT-LICENSE) throughout (terminal semantics, deliberate exception to avoiding monospace labels); 14px body / 20px title / 12px status; prose width 76ch. Font file keeps captures + LAN browsers independent of host font availability.

```text
┌ fvapi / terminal                      vflab [API status] ┐
│ catalog  show  lookup  check  demand  answers   help     │
├ session ────────────────────────────────────────────────┤
│ founder@vflab $ catalog                                │
│ library entries                                       │
│ id                   kind           replay            │
│ ...                  ...            ...               │
│                                                        │
│ [show: text proof panels / check: editable JSON]        │
├────────────────────────────────────────────────────────┤
│ fvapi $ [command                                      ]│
│ Tab complete    ↑↓ history    Enter run                │
└ api v0 / proof packages             search, never trust ┘
```

Distinctive rules = command line remains fixed; results form one scrollable terminal buffer; textual boxes replace cards; ids execute `show`; every action echoes its CLI command; status reports request path + HTTP code; command history + completion work without pointer. Copy/re-run controls remain native accessible buttons. Rich entry content wraps hashes/commands rather than cropping; long tables scroll within their region on mobile. Copper always includes explicit warning text. No motion.

Finish = live API only; all brief states captured + inspected; editable checks; history + id completion; worktree-only commit. Screenshots = external validator inputs at `.scratch/shots/v07-terminal/`.
