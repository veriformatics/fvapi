namespace Fvapi.Verify.Regex

/-! P2's line-oriented regex subset: Thompson graph, bounded epsilon closure, one capture.
Matching is leftmost-longest; captures preserve the matched feature's exact scalar sequence. -/

inductive Mark where
  | plain | open | close | start | finish
  deriving BEq, Repr

inductive Test where
  | any
  | chars (negated : Bool) (ranges : List (Char × Char))
  deriving Repr

def Test.holds (c : Char) : Test → Bool
  | .any => true
  | .chars neg ranges => (ranges.any fun (lo, hi) => lo ≤ c && c ≤ hi) != neg

inductive Edge where
  | epsilon (target : Nat) (mark : Mark)
  | consume (target : Nat) (test : Test)
  deriving Repr

structure Pattern where
  graph : Array (List Edge)
  captures : Nat
  deriving Repr

private def edge (g : Array (List Edge)) (source : Nat) (e : Edge) : Array (List Edge) :=
  g.modify source (· ++ [e])

private def escaped : Char → Char
  | 'n' => '\n'
  | 'r' => '\r'
  | 't' => '\t'
  | c => c

private def classChars : Nat → List Char → List (Char × Bool) →
    Except String (List (Char × Bool) × List Char)
  | 0, _, _ => .error "unterminated bracket class"
  | _ + 1, ']' :: cs, acc =>
    if acc.isEmpty then .error "empty bracket class" else .ok (acc.reverse, cs)
  | n + 1, '\\' :: c :: cs, acc => classChars n cs ((escaped c, true) :: acc)
  | n + 1, c :: cs, acc => classChars n cs ((c, false) :: acc)
  | _, [], _ => .error "unterminated bracket class"

private def ranges : List (Char × Bool) → Except String (List (Char × Char))
  | (a, _) :: ('-', false) :: (b, _) :: cs => do
    if a > b then throw "descending bracket range"
    return (a, b) :: (← ranges cs)
  | (a, _) :: cs => return (a, a) :: (← ranges cs)
  | [] => pure []

private def quantifier (g : Array (List Edge)) (source to : Nat) (cs : List Char) :
    Array (List Edge) × List Char :=
  match cs with
  | '*' :: rest => (edge (edge g source (.epsilon to .plain)) to (.epsilon source .plain), rest)
  | '+' :: rest => (edge g to (.epsilon source .plain), rest)
  | '?' :: rest => (edge g source (.epsilon to .plain), rest)
  | _ => (g, cs)

private def compileLoop : Nat → List Char → Array (List Edge) → Nat →
    Option Nat → Nat → Except String Pattern
  | 0, _, _, _, _, _ => .error "regex parser exhausted"
  | _ + 1, [], g, _, group, count =>
    if group.isSome then .error "unclosed capture group" else .ok ⟨g, count⟩
  | n + 1, '(' :: cs, g, cursor, group, count => do
    unless group.isNone && count == 0 do throw "only one capture group is supported"
    let next := g.size
    compileLoop n cs (edge (g.push []) cursor (.epsilon next .open)) next (some cursor) 1
  | n + 1, ')' :: cs, g, cursor, group, count => do
    let some source := group | throw "unmatched closing parenthesis"
    let next := g.size
    let g := edge (g.push []) cursor (.epsilon next .close)
    let (g, rest) := quantifier g source next cs
    compileLoop n rest g next none count
  | n + 1, c :: cs, g, cursor, group, count => do
    let next := g.size
    if c == '^' || c == '$' then
      let mark := if c == '^' then Mark.start else .finish
      compileLoop n cs (edge (g.push []) cursor (.epsilon next mark)) next group count
    else
      let (test, rest) ← match c, cs with
        | '.', _ => pure (Test.any, cs)
        | '[', '^' :: tail => do
          let (chars, rest) ← classChars (tail.length + 1) tail []
          pure (Test.chars true (← ranges chars), rest)
        | '[', _ => do
          let (chars, rest) ← classChars (cs.length + 1) cs []
          pure (Test.chars false (← ranges chars), rest)
        | '\\', d :: tail => pure (Test.chars false [(escaped d, escaped d)], tail)
        | '\\', [] => throw "trailing backslash"
        | '*', _ | '+', _ | '?', _ => throw "quantifier has no atom"
        | '|', _ => throw "alternation is outside the regex subset"
        | _, _ => pure (Test.chars false [(c, c)], cs)
      let g := edge (g.push []) cursor (.consume next test)
      let (g, rest) := quantifier g cursor next rest
      compileLoop n rest g next group count

def compile (s : String) : Except String Pattern :=
  compileLoop (s.length + 1) s.toList #[[]] 0 none 0

private structure State where
  node : Nat
  first : Option Nat := none
  last : Option Nat := none

private def closure (p : Pattern) (pos size : Nat) (seeds : List State) : List State := Id.run do
  let mut seen : Array Bool := Array.replicate p.graph.size false
  let mut queue : Array State := #[]
  for s in seeds do
    unless seen[s.node]?.getD true do
      seen := seen.set! s.node true
      queue := queue.push s
  let mut head := 0
  for _ in [:p.graph.size] do
    if let some s := queue[head]? then
      head := head + 1
      for e in p.graph[s.node]?.getD [] do
        if let .epsilon target mark := e then
          if (mark != .start || pos == 0) && (mark != .finish || pos == size) then
            unless seen[target]?.getD true do
              let s := { s with
                node := target
                first := if mark == .open then some pos else s.first
                last := if mark == .close then some pos else s.last }
              seen := seen.set! target true
              queue := queue.push s
  return queue.toList

private def cursor (p : Pattern) (cs : Array Char) (start : Nat) : Option String := Id.run do
  let mut states := closure p start cs.size [⟨0, none, none⟩]
  let mut found : Option String := none
  for pos in [start:cs.size + 1] do
    if let some s := states.find? (·.node + 1 == p.graph.size) then
      let captured := match s.first, s.last with
        | some first, some last => String.ofList (cs.extract first last).toList
        | _, _ => ""
      found := some captured
    if let some c := cs[pos]? then
      let next := states.flatMap fun s => (p.graph[s.node]?.getD []).filterMap fun e =>
        match e with
        | .consume target test => if test.holds c then some { s with node := target } else none
        | _ => none
      states := closure p (pos + 1) cs.size next
    if states.isEmpty then break
  return found

/-- One stderr line; a match without a capture has feature `""` (crash patterns). -/
def matchLine (p : Pattern) (line : String) : Option String := Id.run do
  let chars := line.toList.toArray
  for start in [:chars.size + 1] do
    if let some feature := cursor p chars start then return some feature
  return none

/-- Match each line independently, retaining the first matching line's feature. -/
def search (pattern text : String) : Option String := do
  let p ← (compile pattern).toOption
  (text.splitOn "\n").findSome? (matchLine p)

end Fvapi.Verify.Regex
