# Library transit

Premise = proof kinds become transit lines; entries become stations; requirements become interchanges; lookup plans a journey; check issues a ticket; unmet demand becomes a planned extension.

Palette: paper #f4f7fa; ink #17334a; checker blue #004f98; version purple #915cac; refutation red #b52e39; relation green #093220. Colour + line letters + explicit kind labels identify routes; status always has text.

Type: system sans for signs, labels + body; system monospace for code + hashes only. Scale 14/16/20/32/52 px. Text max 76ch. Heavy destination heading; map = sole large graphic.

```
[roundel fv] LIBRARY TRANSIT                  vflab / prototype
[Network] [Plan a journey] [Run check] [Planned extensions] [Tickets]
+-------------------------------------+----------------------+
| Find a route to a verified answer    | Journey planner      |
|                                     | From [key] [query]    |
|  C ==== o === Std                   | To verified answer   |
|  V ===== mathlib ===== o            | [Look up]            |
|  R ========= o                     | result / ticket      |
|  L ===== (no stations)             |                      |
+-------------------------------------+----------------------+
[Station index: kind / entry / replay state]
[Selected station: claim / statements / closure / replay]
```

Principles: schematic angled lines + interchange rings, generous map field, unboxed station labels, vertical wayfinding rail. SVG derives stations + requirements from API data. Empty lines labelled honestly. Map is a navigation diagram, not a dependency proof: shared requirements label interchange locations; station index provides an accessible alternative. Dashed planned extension represents unmet demand, never an existing proof. No invented completion promises. Server verdict = ticket, not final authority; replay kit remains visible.

Finish: live relative API; catalog/entry/recorded/lookup-hit/lookup-miss/check-accept/check-reject/check-409/demand/answers/mobile captures inspected. URL `?state=<name>` drives deterministic demonstration states by calling API, never supplying response fixtures.
