---
paths:
  - "**/*.lean"
---

# Lean 4.35 pitfalls (this toolchain, this repo)

- Structure literals: every field at or right of the first field's column, else `unexpected identifier; expected '}'` ⇒ write one field per line after `{ x with` / `{`.
- `section`, `scoped`, `local`, `at` = keywords: never variable/field/hypothesis names; a blanket rename must spare JSON string keys (`"section"`).
- Inside `Fvapi.Store`, bare `decide` resolves to the store decision function ⇒ `Decidable.decide (p)`.
- `if` on a mixed Bool/Prop condition can fail Decidable synthesis ⇒ write it with Bool operators (`&&`, `||`, `!`, `!=`); membership in a Bool context ⇒ `xs.contains x`.
- Production `if` guards do not reduce reliably under `rw [if_pos]`/`split` (`Decidable` is a structure) ⇒ `rcases` the head + `cases` the stream, then `simp_all [def, Bind.bind, Except.bind, throw, throwThe, MonadExceptOf.throw]`.
- Recursion inside a tactic proof: `match` on the decreasing argument (tactic `match`), not `rcases`/`cases`, or `termination_by` loses the equation.
- `return` inside `let x ← match …` arms exits the enclosing `do` (precedent: DevRuntime.initStore).
- No Mathlib/Batteries: `swap` is an unknown tactic ⇒ `case neg =>` after `by_cases`; a contradiction argument = `Classical.byContradiction fun bad => …`.
- `open private … from M` = the project command in `FvapiProof.Store.SurfacePrivate` (import it); the alias is the FULL name (`Fvapi.Store.Startup.record`), and production modules cannot use it.
- Name constructor implicits with `| @row id rest h₁ h₂ allocated =>`; `rename_i` renames the most recent inaccessibles, which are often anonymous proofs.
- Key lookups on code-built JSON objects: rewrite with a stable-sort lookup lemma (`StartupProject.member_object`) instead of unfolding `Value.object`/`sortMembers` (an 11-member `mergeSort` does not simp).
- `let some x := e | alt` is do-notation only; a helper extracted from a `do` block needs its own `do`. TreeMap `get?` vs `[k]?`: bridge with `Std.TreeMap.get?_eq_getElem?`.
- `rcases h : f _ … with …` leaves `_` as an unresolved metavariable that never matches the goal ⇒ spell the argument or `split at` the unfolded bind chain.
- `decide` needs a closed goal with a `Decidable` instance: free variables → `show` the closed literal form first; spec predicates without an instance (spec `present`) → `show` the native Bool form, then `rw [decide_eq_false_iff_not]`. `native_decide` adds an axiom outside {propext, Classical.choice, Quot.sound} ⇒ never.
- `@[simp] presentExact` rewrites native `present` into spec `present` inside any `simp` ⇒ a later `decide` meets the instance-less spec form.
- A production lambda that a proof cannot restate → state the lemma over an arbitrary predicate and `rw [lemma]`: `rw` unifies the goal's own lambda (precedent `SnapshotCollections.find_index`).
- Inside `case X =>`, a nested `cases … with` puts each `| ctor =>` arm on its own line, indented past `case`.
- Private structure fields opened with `open private` → apply the full name (`Fvapi.Store.CandidateData.objects data`); dot notation `data.objects` fails.
- Formal premises that stay visible by ruling (E-A28 `Sha256Output32`, the validated node caller) are theorem arguments, never axioms or `sorry`.
- A do-block `let x := e` becomes `have x := e`: the term `e` is hidden from `cases e`/`rw` until `simp only [f]` (zeta) exposes it; do join points (`have __do_jp`) block `split` the same way ⇒ `simp only [f] at h`, then `split at h`.
- `if_pos`/`if_neg` are deprecated (errors under warningAsError) ⇒ state the reduced form by defeq (`have h' : … := h`) or use `ite_eq_left`/`ite_eq_right`.
- `cases h` on `some a = some b` (both locals) may eliminate the variable you need ⇒ `have e := Option.some.inj h; subst e` (eliminates the right-hand variable).
- `cases` takes comma-separated targets: inside `⟨fun x => by cases x, …⟩` the comma is parsed as a second target ⇒ parenthesize every `fun … => by …` field.
- `cases h` on an equation between non-variable constructor arguments fails ("Dependent elimination failed") ⇒ `simp only [….injEq] at h` to extract the field equation.
- Compiled allocation hides in runtime primitives (E-A40 cost models + perf): a `Nat` literal of 2^32 or more — also a folded def such as `2 ^ 53 - 1` — compiles to `lean_cstr_to_nat("…")` at every evaluation (GMP parse, libc `malloc`); `Int.ofNat n` past 2^31 − 1 builds a GMP big integer (libc limbs + a 24 B object); `String.data`/`toList` = C++ `lean_string_data` (a `std::vector` of code points grown through `operator new` → libc). Allocation observers therefore probe libc as well as mimalloc + the small-object path (`tests/store/model/alloc-observe.sh`), and a cost model reads the compiled C (`.lake/build/ir/**.c`), never the Lean source alone.
