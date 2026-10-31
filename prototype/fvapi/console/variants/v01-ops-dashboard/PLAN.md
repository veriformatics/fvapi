# Service operations console

Premise = service operator's dense workbench; persistent navigation + sortable inventory, with an evidence drawer beside its selected row.

Palette: navy #16354b (navigation), blue #145b91 (actions), paper #f3f6f8 (workspace), white #ffffff (tables), ink #203342 (text), amber #865000 (recorded warnings).
Type: system sans for interface; system monospace for identifiers, hashes + replay commands. Scale 12/14/16/24/30 px; prose <=76ch.

```
+-------------+------------------------------------------+
| fvapi       | vflab | Lean version | catalog count     |
| Catalog     +------------------------------------------+
| Look up     | Catalog                         Refresh  |
| Check       | Search | kind                            |
| Demand      +-------------------+----------------------+
| Answers     | sortable inventory| entry evidence drawer|
|             | id / kind / replay| claim, proof, replay  |
+-------------+-------------------+----------------------+
```

Distinction: horizontal rule-led tables rather than cards; nav remains visible across operation changes; health strip reads infrastructure facts, not invented uptime; recorded replay gets a persistent amber warning rather than a success badge. Drawer preserves catalog context. Forms + audit logs share the same compact controls. Mobile collapses navigation into a wrapping row, makes the drawer inline, and scrolls tables without clipping the page.

Finish: live relative API only; all required URL-hash states captured + inspected; commit only variant files.
