---
paths:
  - "**/*.lean"
---

# Lean 4.35 pitfalls (this toolchain, this repo)

- Structure literals: every field at or right of the first field's column, else `unexpected identifier; expected '}'` ⇒ write one field per line after `{ x with` / `{`.
- `section`, `scoped` = keywords: never variable/field names; a blanket rename must spare JSON string keys (`"section"`).
- Inside `Fvapi.Store`, bare `decide` resolves to the store decision function ⇒ `Decidable.decide (p)`.
- `if` on a mixed Bool/Prop condition can fail Decidable synthesis ⇒ write it with Bool operators (`&&`, `||`, `!`, `!=`); membership in a Bool context ⇒ `xs.contains x`.
- Production `if` guards do not reduce reliably under `rw [if_pos]`/`split` (`Decidable` is a structure) ⇒ `rcases` the head + `cases` the stream, then `simp_all [def, Bind.bind, Except.bind, throw, throwThe, MonadExceptOf.throw]`.
- Recursion inside a tactic proof: `match` on the decreasing argument (tactic `match`), not `rcases`/`cases`, or `termination_by` loses the equation.
- `return` inside `let x ← match …` arms exits the enclosing `do` (precedent: DevRuntime.initStore).
