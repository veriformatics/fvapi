# Panel scope

Premise = a software analyser: selection at left, input + compact verdict centrally, evidence scope embedded at right; one recorder strip below. Panel-led, graph = a live view of the selected package rather than navigation for the entire library.

Palette: workspace #edf1f7; paper #ffffff; ink #21334e; signal blue #265cc4; accept #186344; demand/reject #963d37. Muted text = ink; borders use ink with transparency. Status color always carries explicit text.

Type: system sans, 13/15/18/25 px for controls + prose; vendored Adwaita Mono, 12/14/40 px for input, hashes + readout. Prose ≤76ch. Local font = `AdwaitaMono-Regular.woff2`, SIL OFL 1.1 (`FONT-LICENSE.txt`); no external fetches.

```
 fvapi / Verification analyser                         vflab
 [entry selector] [compact verdict] [Evidence scope             ]
 [all entries   ] [input tray     ] [entry────checker            ]
 [lookup        ] [editable JSON  ] [subject──closure groups     ]
 [status        ] [Run check     ] [demand    libraries/toolchain]
 [chart recorder: answers | demand; real event rows across strip]
 [proof package: statements | replay + licence + source         ]
```

Principles: software workspace, not enamel or simulated hardware. Single blue readout anchors the panel; graph lives within its bounded scope. Group closure files by directory with counts; expand to inspect hashes rather than create 92 tiny nodes. Lookup highlights the complete evidence path; input checks highlight the checker alone. Demand is visibly unattached at the scope edge. Native details give a text graph alternative, never a graph/list mode. Recorder = ruled event rows, not raw JSON filling the page. Recorded status precedes both input and proof text. Narrow screens stack selector, readout/input, scope, recorder.

Finish = static API-backed page; eleven states captured + inspected; source restricted to this directory. Verification evidence + known limits reported to lead.
