# Faceted catalog

Premise = a verification package registry: find an exact result, narrow by provenance, inspect the delivery.

Palette: paper #ffffff; mist #f0f4f8; ink #24344a; secondary #526378; registry blue #174fbd; caution #87500a. Blue search bar = sole bold element; amber only marks recorded provenance.

Type: system sans for navigation, claims + headings (14/16/22/36 px); system monospace for proof text, commands + hashes (12/14 px). Claims bounded to 70ch.

```
fvapi / Library                           Check input  Activity
[ What do you want verified?________________ ] [Look up]
[ Entry id | SHA256 | Statement ]
Filters          Results                      Entry inspector
Kind             package title + provenance   claim
Replay           package title + provenance   theorem
Licence          package title + provenance   delivery / replay
Toolchain                                    licence / source
```

Principles: retrieval before administration; facets expose trust-relevant properties rather than popularity; list remains visible beside selected package; inspector explains independent rechecking; recorded evidence is not a success badge; secondary tabs keep request machinery out of the discovery flow. Mobile stacks filters, list + inspector. Square controls + inset list selection echo package registries, without decorative dashboard metrics.

Finish = static live-API client; 11 named capture states; keyboard + narrow-screen usability; owned paths only.
