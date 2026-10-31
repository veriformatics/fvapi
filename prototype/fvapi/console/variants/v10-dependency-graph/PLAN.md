# Dependency atlas

Premise: inspect the library as a proof dependency graph; follow a claim through its subject, delivered closure and trusted runtime.

Palette: paper #f5f8fb; ink #16324b; border #a7b9cb; link #335f8a; verified #126247; demand #953e26. White #ffffff is the node surface.

Type: system sans for controls and prose; system monospace for source, hashes and Lean. Scale 13/15/19/28 px. Long prose width ≤76ch.

```
 fvapi / Dependency atlas                         library | activity
 [lookup specification________________] [Look up]
 [Graph] [Accessible list]       Legend: entry / subject / closure / runtime
 ┌─────────────────────────────────┬───────────────────────┐
 │ entries → subjects              │ selected node         │
 │         → delivered files       │ statement / source    │
 │         → required libraries    │ replay / check input  │
 │         → Lean toolchain        │ closure hashes        │
 │ demand ○ - - - unattached       │                       │
 └─────────────────────────────────┴───────────────────────┘
```

Distinctive principles: the graph is the primary navigation, not decoration. Edge labels carry the relationship. A selected entry expands its exact dependency neighborhood; unrelated entries stay visible. A missed lookup creates a visually dangling demand node, not a failed search page. Recorded proofs have a persistent warning. Check verdicts color the checker node and remain separate from proof replay. Narrow screens stack graph and inspector; the accessible list preserves identical navigation. No animation needed.
