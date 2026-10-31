# Request playground

Premise = HTTP workbench: compose left, inspect right, remember every exchange in a narrow session rail; server logs below.

Palette: paper #F5F7FA; ink #233247; request blue #1954A6; response green #176347; warning brown #80500B; border #CBD3DE. White editor surfaces. No decorative gradients/shadows.
Type = system sans for navigation/headings (13/15/22/28px); system monospace only for actual JSON, routes, hashes, commands. Editor line-height 1.6; body 1.5.

```
[ fvapi / Request playground                     v0 | vflab ]
[ Session    ][ Request                           | Response ]
[ exchanges  ][ presets                           | HTTP code]
[            ][ method | route                    | structured / raw]
[            ][ editable body                     | proof / verdict ]
[            ][ Send request                      | replay materials]
[            ][ Server activity: demand | answers               ]
```

Principles: request/response pairing is the dominant gesture; method pills identify traffic, not decoration. Catalog is an API response with selectable entries, not a parallel app. Proof obligations live beside successful responses. Server logs distinguish shared history from local session history. Desktop uses workbench panes; mobile stacks composer then response. All API-derived text uses textContent or escaped HTML. Every response remains inspectable as raw JSON.

Finish = live relative API; all specified states captured and inspected; static assets only; keyboard focus + narrow viewport; own-dir commit.
