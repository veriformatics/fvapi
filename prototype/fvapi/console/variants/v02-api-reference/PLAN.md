# v02-api-reference

Premise = API reference as working console: route navigator | readable contract + live semantic response | editable request + raw response.

Palette: paper #ffffff; ink #243247; muted #526279; lavender surface #f2f0fa; violet action #5540a0; green outcome #246345. Warning = ink text on lavender + explicit wording, not status color alone.
Type: system sans for documentation, 32/23/17/14px scale; system monospace for route identifiers, commands + JSON. Prose max 66ch.

```
fvapi / API reference                 v0    relative API origin
route navigator    | Route + explanation     | Try this request
  Catalog          | live human-readable    | JSON editor
  Entry            | answer                 | [Send request]
  Lookup           | trust/replay guidance   | curl / CLI
  Check            |                         | HTTP status + JSON
  Demand / answers |                         |
```

Distinct principles: navigation names HTTP routes, not dashboard areas; every page exposes the call that produces it; prose never replaces actual response; trust payload stays readable alongside exact JSON. Violet request rail = one bold visual area, left reference + middle answer remain quiet. Square sections, no decorative cards, no animation. Mobile stacks route selector, documentation, request rail; code scrolls internally. Responses escaped before insertion.

Finish = eleven state screenshots (catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers, mobile), each inspected; editable live requests; no writes outside variant except assigned screenshots; worktree commit.
