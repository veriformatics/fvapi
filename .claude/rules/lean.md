---
paths:
  - "**/*.lean"
---

# Lean 4.35 pitfalls (this toolchain, this repo)

- Structure literals: every field at or right of the first field's column, else `unexpected identifier; expected '}'` ⇒ write one field per line after `{ x with` / `{`.
- `section`, `scoped`, `local` = keywords: never variable/field/hypothesis names; a blanket rename must spare JSON string keys (`"section"`).
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
