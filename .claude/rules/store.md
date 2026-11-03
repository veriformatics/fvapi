---
paths:
  - "Fvapi/Store/**"
  - "FvapiSpec/Store/**"
  - "FvapiSpec/StoreModel.lean"
  - "FvapiProof/Store/**"
  - "tests/store/**"
---

# Store (U4) — change law

- The reviewed spec (`FvapiSpec/Store/**`) changes only under a MAIN ruling published as a `docs/contracts/U4-tables.md` erratum (steward row in `.scratch/u4/steward.md`), paired with the production change in one red-first commit, its firing commit kept. A spec + production pair that agree with each other but not with the tables is still a defect.
- Production functions whose exactness proof has closed (e.g. `typedProposal`, `checkedWith`, `decide`, `decideBatch`, `appendNode`, `appendBlock`) are frozen: new behavior lives beside them with a refinement theorem back to them; a ruled change to one reopens its proofs, so the diff goes to MAIN first and the proof owners adapt at a relayed sha.
- Shared proof bridges (`StructureBridge`, `BindingBridge`) have one owner per change; other proof owners merge the owner's adapted sha and never patch the bridge themselves.
- Native controls (`tests/store/**`) call production through thin wrappers and never import `FvapiProof` closures: proof-only constants (e.g. `TraversalBudget.keyUniverse`) initialize at executable startup and exhaust 8 GiB before `main`.
- `TestsU4/**` is the blind suite: builders run it read-only; corrections follow `.claude/rules/suites.md`.
