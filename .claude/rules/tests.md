---
paths:
  - "tests/**"
  - "Tests*/**"
  - "Tests.lean"
  - "FvapiProof/**"
  - "FvapiProofs.lean"
  - "FvapiSpec/**"
  - "c/**"
  - "docs/contracts/**"
---

# Test form (adapts CLAUDE.md `Engineering` → `Tests/verification`: "each contract predicate over the input domain → a property-based test")

- A contract predicate proved as a closed Lean theorem about the shipped function already covers every input ⇒ that proof = its property test: a generated test of it cannot fail (the compiler is trusted, `Decisions` → `Self-verification`) and greens like a clean tree. A predicate without a closed proof → a property-based test, seed fixed in the gate.
- Proofs leave out what they do not model ⇒ tests still cover code behind `@[extern]` / `@[implemented_by]` (native C + FFI glue) and compiled-code resources (stack depth, heap, time). Byte-level readers (U3 JSON + wire decoders, U4 store-object decoding, U7 HTTP receive, U8 archive extraction) + native C (fsync bridge, SHA-256 glue) each get a coverage-guided fuzz target, sanitizers on for native code; campaigns run in the campaign tier (`.claude/rules/gate.md`), the gate replays the committed seed corpus + every crash input.
