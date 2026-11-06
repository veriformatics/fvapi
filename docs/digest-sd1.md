# Statement digest `sd1` (interface reference; binds through `.agent/spec.md` `Decisions` → `Statement digest`)

Scope = routing key alone. Equal digests never imply equivalent, compatible or acceptable theorems: acceptance = the caller's challenge + axiom allowlist + comparator + kernels (`Answer guarantee`); a lookup hit is a routing outcome; verified status is a separate result, set only by the caller's re-check. The byte function below is frozen: a change to the identity rule = a new tag; a changed elaboration input (imports, toolchain, options) may change a digest under the same tag.

## Encoding (spike `ARMS.md` § A1, verbatim; tag `spike-sd1` = f441eba)

Selected declaration's closed elaborated TYPE + ordered universe-context arity. Excluded = selected name/module/source/proof + global environment/toolchain salt. Referenced constants retain full Lean names. No transitive declaration/proof closure.

`H = SHA-256`; `U(n)` = minimal unsigned LEB128, arbitrary nonnegative integer, zero `00`; `B(s) = U(UTF8(s).size) || UTF8(s)`. Child hashes = raw 32 bytes. Domains = ASCII + final NUL: `fvapi:sd1:name\0`, `fvapi:sd1:level\0`, `fvapi:sd1:expr\0`, `fvapi:sd1:statement\0`. Every nonroot node = `H(domain || one-byte tag || payload)`.

| family | tag | payload |
|---|---:|---|
| Name anonymous | 0 | empty |
| Name str | 1 | prefix-name hash + B(component) |
| Name num | 2 | prefix-name hash + U(component) |
| Level zero | 0 | empty |
| Level succ | 1 | child hash |
| Level max | 2 | left hash + right hash, ordered |
| Level imax | 3 | left hash + right hash, ordered |
| Level param | 4 | U(index in ordered ConstantInfo.levelParams) |
| Expr bvar | 0 | U(index) |
| Expr sort | 1 | level hash |
| Expr const | 2 | name hash + U(universe-argument count) + ordered level hashes |
| Expr app | 3 | function hash + argument hash |
| Expr lam | 4 | domain hash + body hash |
| Expr forall | 5 | domain hash + body hash |
| Expr let | 6 | type hash + value hash + body hash |
| Expr Nat literal | 7 | U(value) |
| Expr String literal | 8 | B(value) |
| Expr projection | 9 | type-name hash + U(field index) + subject hash |

`mdata _ e` → hash(e), recursively. Erase binder/let labels, BinderInfo, let nondep. Retain every binder/domain/argument, arity including unused universe parameters, raw ordered max/imax syntax + universe application order. No δ/β/ζ/η, proof-argument erasure, overloaded-literal normalization or structure η.

Root = `H("fvapi:sd1:statement\0" || U(levelParams.length) || type_expr_hash)` (no extra root tag). Output = `sd1:` + 64 lowercase hexadecimal digits.

Reject FVar, Expr/Level MVar, loose bvar at actual binder depth, duplicate ordered universe labels, parameter outside that list, missing/ambiguous declaration, frontend failure. Resource exhaustion → typed failure/no digest; outer OOM/signal/timeout → nonzero/no usable digest. Memoization keys bind the universe mapping + binder-depth validity; sharing, allocation and traversal order contribute no bytes.

Reading notes (bind with the encoding): the universe context = `ConstantInfo.levelParams` in order, each label ↦ its position, unused parameters kept; "proof" = the selected declaration's own value, while proof-valued arguments inside TYPE stay hashed; Name hashing covers all three Name constructors, so public source-name resolution (which declaration a caller names) is a separate layer.

## Failures

- Typed (cooperative; no digest): FVar; Expr or Level MVar; loose bvar at its actual binder depth; duplicate ordered universe label; universe parameter outside the list; missing or ambiguous declaration; frontend failure; cooperative resource exhaustion.
- Forced (OOM, signal, outer timeout): nonzero exit, no usable digest, no typed payload promised.
- A caller-binding gap (an internal-name target the binding decoder cannot name, a candidate-axiom root) limits re-check, not hashing: such declarations still digest.

## Conformance vectors

`docs/digest-sd1/vectors.json` (sha256 `021c2f1f80ba0fc718c0771ed1ece2eb0ae213110c2b058f3765f92b5198ac23`) + `docs/digest-sd1/vectors.expected.json` (sha256 `f7f74dc589542252498b33eca91cbd475ed1a93199e5fa8bfd5798d3c6be6b6f`) = byte copies of `spike-sd1:spike/sd1/`. 77 cases: 18 raw-byte encodings (10 `U`, 8 `B`) + 34 node hashes (10 Name, 8 Level, 16 Expr) + 19 statement digests + 6 typed failures (`expr_fvar`, `expr_mvar`, `loose_bvar`, `level_mvar`, `unbound_universe_parameter`, `duplicate_universe_parameter`). `A2_deltas` = spike-only A2 normalization examples, outside `sd1`. The vectors are finite conformance examples; the encoding above is the authority; production correctness = U5's encoder refinement proofs (erasure, memoization, root) + property tests; the spike encoder = a differential aid.

## Open (U5 operation contract, before code)

`fvapi digest FILE [THEOREM]`: declaration selection when THEOREM is omitted, accepted declaration kinds, import/module/options boundary, success output, failure mapping onto the outcome taxonomy (`docs/api.md`).
