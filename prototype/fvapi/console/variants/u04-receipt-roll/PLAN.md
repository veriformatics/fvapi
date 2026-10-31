# Till receipt roll

Premise = catalog price board above a till; every response prints its evidence onto a continuous narrow paper roll. Proofs are line items, never a decorative trust badge.

Palette: counter blue #254C5B; board blue #163744; thermal white #FAFAF6; ink #202926; faded ink #526059; warning burgundy #802B32. White and blue board contrast; burgundy = recorded/missing/rejected, paired with words.

Type: system sans for the catalog board + controls; vendored Liberation Mono (SIL OFL 1.1, FONT-LICENSE) for receipt evidence. 14px body, 12px hash labels, 32px till title, 26px receipt total. No artificial letter spacing.

```
+--------------------------------------+
| fvapi                 library counter|
| Price board: entries + replay status |
+--------------------------------------+
        [lookup / check / log controls]
         ╔════════ receipt slot ═══════╗
         | fvapi / answer identifier   |
         | entry + matched on          |
         | claim + statement           |
         | files / hashes              |
         | replay + axioms + licence   |
         |                 TOTAL       |
         +------ tear here ------------+
         | next request                |
```

The single physical roll owns the reading order. A request adds a receipt rather than replacing a card. Hashes wrap fully instead of being abbreviated. The catalog is a flat dark price board, not a card grid. Narrow paper is intentional: the mobile experience keeps the same metaphor. No entrance animation; print state is immediately available. Server responses = leads; receipt footers instruct local re-checking. Prototype fixtures are identified as illustrative. Recorded evidence is stamped “Not re-run by fvapi”.

Verification: catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand, answers, mobile → reached through live mock API requests, webcap full-page PNG captured + individually inspected. 390px mobile = no observed horizontal clipping. JS syntax = node --check passed. Console errors = not checked (webcap supplies rendered DOM, not console event history). Clipboard button = implemented; system clipboard result unconfirmed. Keyboard = native controls + visible focus styling; complete keyboard traversal unconfirmed. Contrast = palette chosen for AA; numerical audit not run. Catalog fixture = 3 entries, health fixture = 5; UI shows all catalog entries returned. Proof bundles + replay = not exercised against real vflab. Run URL = http://127.0.0.1:8464/console/u04-receipt-roll/; query state selects each capture state. Request history is a page-local continuous roll; reload starts a new roll. API answer/demand logs remain accessible independently.
