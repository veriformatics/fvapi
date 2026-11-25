---
paths:
  - "Fvapi/Store/Fixture.lean"
  - "tests/store/model/PathBridge.lean"
---

# Fixture path splitter bridge (SW-N22 import uniqueness)

- `Fixture.pathParts` (core `String.split '/'`) replaced Legacy `String.splitOn "/"` because only the core splitter has lemmas (`String.toList_split_char` + `List.intercalate_splitOn` ⇒ `intercalate "/" (pathParts s) = s`, which `FvapiProof/Store/N22Fixture.lean` `fixture_unique` rests on). Legacy `splitOn` stays the reference: `fvapi-store-path-bridge` (exe, `tests/store/model/PathBridge.lean`) compares both on every string of length ≤ 6 over `a b / é` + 20,000 seeded strings of length ≤ 64 (12 characters, 1–4-byte UTF-8, `/`, `.`, NUL).
- Firing record (lane 955775b, driver be64ac28): plain → `PASS 25461 strings`, rc 0; `--plant` (a splitter dropping empty components) → `15433 of 25461 strings differ`, rc 1. Any edit to `pathParts`, `fixturePath`, `pathParent`, `pathName` reruns both; the store-control gate stage carries it from U4A close.
