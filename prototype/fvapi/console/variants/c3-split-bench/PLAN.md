# Split bench

Premise = equal working surfaces: prepare a request at left, trace its proof at right; one recorder joins the two.

Palette: bench #eef0f7; paper #ffffff; ink #24334d; trace #51449a; accept #176445; reject #943e36. Borders derive from ink with opacity; states pair color with words.

Type: system sans = controls + prose (13/15/19/27 px); system monospace = editable JSON, Lean + hashes (12/14 px); verdict = 40 px sans, smaller than u02. Prose ≤76ch.

```
 fvapi / Split bench                           vflab / API v0
 [prepare a request                      ][trace the proof                ]
 [entry selector: all catalog entries     ][entry node                     ]
 [lookup spec................][Look up]   ][      subject / artifact       ]
 [verdict readout                        ][      closure directory groups ]
 [editable JSON tray                     ][      requirements + toolchain ]
 [Load example] [Run check]               ][checker verdict / demand stub  ]
 [chart recorder: Answers | Demand; click row restores both halves          ]
 [proof package: statements / hashes / replay / axioms / licence / source   ]
```

Principles: equal columns share the same baseline + height, neither a sidebar. A violet trace identifies the matched dependency path; green/red belong only to checker verdicts. The graph represents dependencies, never proof inference. Closure groups expand into exact files, with hashes in the package below. Directory aggregation keeps real 49–92-file bundles legible. Recorder rows restore the selected graph + recorded verdict without submitting another request; input absent from server history stays explicitly unavailable. No enamel, graph/list mode switch, animation, shadows, rounded cards or fake metrics. Mobile stacks preparation then trace then recorder. A collapsible text graph remains available at every width.

Finish = eleven API-backed states captured + inspected; recorder restoration driven; static local assets only. PROTOTYPE assurance.
