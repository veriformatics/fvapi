# Obligation matrix (agent-read; contract `docs/contracts/U2-trust.md` P4; gate stage `inventory` checks it against `verify/claims.json`)

Columns: promise → inventory claim → implementation + shipped call paths → proof | test → coverage → residual trust.

| Promise | Claim id | Implementation (call paths) | Proof / test | Coverage | Residual trust |
|---|---|---|---|---|---|
| A verification passes only under the `Answer guarantee` kernel policy | `policy-exact` | `Fvapi.Verify.verdict` | `FvapiProof.Policy.policy_exact`; Tests.lean policy controls | the decision over result facts | result collection + status parsing (P3, pending), Lean compiler + runtime |
| An answer names exactly its accepting kernels, in profile order | `accepting-exact` | `Fvapi.Verify.accepting` | `FvapiProof.Policy.accepting_exact`; Tests.lean order control | membership; order + once-each by construction (`List.filter` over the profile order) | profile order validity (P2), Lean compiler + runtime |
| A profile names a run set the `Answer guarantee` can pass: fvapi's own = the six kernels once each; a caller's = no repeats, leanchecker + a kernel of another lineage | `run-set-exact` | `Fvapi.Verify.runSetOk` (via `checkProfile`, `fvapi dev profile`) | `FvapiProof.Profile.run_set_exact`; TestsU2 black-box P2 (152 cases incl. all 64 subsets × 2 scopes) | the decision over parsed kernel ids | profile parsing + field checks + host identity (tested: TestsU2 P2), Lean compiler + runtime |
| Decoding returns exactly the outcome the reviewed byte grammar assigns, errors + their precedence included | `decode-exact` | `Fvapi.Json.decode` | `FvapiProof.Json.decode_exact`; TestsU3 T1–T5 (blind differential) | every byte string | the grammar's fidelity to RFC 8259 + docs/api.md (review ruling + differential), core `@[extern]` byte access + UTF-8, Lean compiler + runtime |
| A decoded value is profile-valid (int range, string caps, depth ≤ 32, keys strictly ascending) | `decode-valid` | `Fvapi.Json.decode` | `FvapiProof.Json.decode_valid`; TestsU3 T4 | every successful decode | Lean compiler + runtime |
| A JSON text denotes one value (the raw grammar is deterministic) | `text-unique` | `Fvapi.Json.decode` | `FvapiProof.Json.text_unique` | the grammar itself | none beyond the spec's review |
| The printer emits exactly the reviewed canonical text (= jq -S -c on valid values) | `print-exact` | `Fvapi.Json.print` | `FvapiProof.Json.print_exact`; TestsU3 T6 (jq differential) | every value | jq agreement = review + differential; Lean compiler + runtime |
| A valid value's canonical text decodes, by the grammar, to that value | `round-trip` | `Fvapi.Json.print` | `FvapiProof.Json.round_trip` | every valid value | none beyond the spec's review |
| print then decode returns a valid value unchanged | `print-decode` | `Fvapi.Json.print`, `Fvapi.Json.decode` | `FvapiProof.Json.print_decode`; TestsU3 T7 | every valid value | Lean compiler + runtime |
| Canonical text tells valid values apart (profile ids, content names) | `canonical-injective` | `Fvapi.Json.print` | `FvapiProof.Json.canonical_injective` | every pair of valid values | none beyond the spec's review |
| `Value.object` = a stable key sort of its members | `object-law` | `Fvapi.Json.Value.object` | `FvapiProof.Json.object_law`; TestsU3 T7 | every member list | core `String` order extern; Lean compiler + runtime |
| `get?` = the first member with an equal key; `none` for absent keys + non-objects | `get-law` | `Fvapi.Json.Value.get?` | `FvapiProof.Json.get_law`; TestsU3 T7 | every value + key | Lean compiler + runtime |
| Each projection returns exactly its constructor's payload | `as-laws` | `Fvapi.Json.Value.asBool?` … `asObj?` | `FvapiProof.Json.as_laws`; TestsU3 T7 | every value | Lean compiler + runtime |
| `hex` renders each byte as two lowercase hex digits | `hex-exact` | `Fvapi.Hash.hex` | `FvapiProof.Hash.hex_exact`; TestsU3 T10 | every byte array | Lean compiler + runtime; the digest itself = HACL*'s upstream proof + NIST/differential/ASan tests (no Lean claim) |

Pending (later units): result collection + status parsing, export + challenge binding (P3); credit aggregation (P7); every product promise of U3–U19.
