# Assurance tiers (CLAUDE.md `Engineering`, as applied in this repo)

- kernel = source contracts, acceptance decisions, irreversible effects → `consultant` on the contract before code, `tester` suite from it, full adversarial battery.
- A proof-only kernel part (closed theorems, no behavior change) = its own property tests (`.claude/rules/tests.md`) ⇒ the blind check a `tester` adds = an independent statement-faithfulness review (astra lane) of every definition + theorem against the contract, before credit, incl. a vacuity probe: a premise that makes the statement trivially true or turns its conclusion into an assumption, an unexercised predicate, a trivial definition; each end-to-end claim names a consuming theorem or a nontrivial witness.
- data = producers a downstream check re-verifies (bundles the caller re-checks, archives verified by sha256, presentation) → one structural validator + live spot-check; defects fix forward.
- docs = consistency pass.
- Each unit's contract (`docs/contracts/U<n>-*.md`) declares the tier of every part; a judgment-bearing part inside glue (an exit-code mapping, a gate verdict) is kernel.
