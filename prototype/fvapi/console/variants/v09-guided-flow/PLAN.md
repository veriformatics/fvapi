# Guided flow

Premise = newcomer workbook; one meaningful question at a time, a visible three-step sequence, evidence before confidence.

Palette = ink #19334A; paper #FFFFFF; field #F0F5F8; blue #225DA9; green #236445; amber #795214. Status colors pair with explicit text.
Type = system sans (body 16, labels 14, headline 40, section 27); system monospace only for proof/code. Reading width ≤72ch.

```
 fvapi                            Operator view
 ------------------------------------------------
 [1 Choose] ------ [2 Find] ------ [3 Check]
 | What do you want verified?                    |
 | short explanation                             |
 | [Choose from library] [Paste a request]        |
 | stacked library choices, full-width rules     |
 |                                  [Look up]   |
 ------------------------------------------------
 You receive evidence. You do not have to trust us.
```

Sequence numbers are actual steps. Main bold element = question; quiet horizontal progress track; no dashboard metrics, decorative icons, shadows or gradients. Step 2 teaches hit vs miss. Step 3 distinguishes checking proof from checking input, foregrounds replay provenance. Operator logs secondary. Mobile collapses sequence labels, not their order.

Finish = catalog, entry, recorded, lookup-hit, lookup-miss, check-accept, check-reject, check-409, demand+answers, mobile rendered/captured/inspected. API data only; query `state` supports repeatable captures.
