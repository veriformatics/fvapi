# Obligation matrix (agent-read; contract `docs/contracts/U2-trust.md` P4; gate stage `inventory` checks it against `verify/claims.json`)

Columns: promise → inventory claim → implementation + shipped call paths → proof | test → coverage → residual trust.

| Promise | Claim id | Implementation (call paths) | Proof / test | Coverage | Residual trust |
|---|---|---|---|---|---|
| A verification passes only under the `Answer guarantee` kernel policy | `policy-exact` | `Fvapi.Verify.verdict` | `FvapiProof.Policy.policy_exact`; Tests.lean policy controls | the decision over result facts | result collection + status parsing (P3, pending), Lean compiler + runtime |
| An answer names exactly its accepting kernels, in profile order | `accepting-exact` | `Fvapi.Verify.accepting` | `FvapiProof.Policy.accepting_exact`; Tests.lean order control | membership; order + once-each by construction (`List.filter` over the profile order) | profile order validity (P2), Lean compiler + runtime |

Pending (later units): result collection + status parsing, export + challenge binding (P3); profile identity (P2 Lean reader); credit aggregation (P7); every product promise of U3–U19.
