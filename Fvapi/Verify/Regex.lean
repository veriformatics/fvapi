import Std.Data.HashSet.Basic

namespace Fvapi.Verify.Regex

/-! P2's subset: boolean Thompson reachability fixes the leftmost-longest whole span.
An ordered path search chooses its greedy capture; the group's last iteration supplies the
feature. -/

inductive Mark where
  | plain | open | close | start | finish | repeatGroup
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

private def quantifier (g : Array (List Edge)) (source to : Nat) (cs : List Char)
    (group : Bool := false) : Array (List Edge) × List Char :=
  let back := if group then Mark.repeatGroup else .plain
  -- The body precedes its exit; the back edge precedes the following concatenated piece.
  match cs with
  | '*' :: rest => (edge (edge g source (.epsilon to .plain)) to (.epsilon source back), rest)
  | '+' :: rest => (edge g to (.epsilon source back), rest)
  | '?' :: rest => (edge g source (.epsilon to .plain), rest)
  | _ => (g, cs)

private def compileLoop : Nat → List Char → Array (List Edge) → Nat →
    Option Nat → Nat → Except String Pattern
  | 0, _, _, _, _, _ => .error "regex parser exhausted"
  | _ + 1, [], g, _, group, count =>
    if group.isSome then .error "unclosed capture group" else .ok ⟨g, count⟩
  | n + 1, '(' :: cs, g, cursor, group, count => do
    unless group.isNone && count == 0 do throw "only one capture group is supported"
    let source := g.size
    let next := source + 1
    let g := edge ((g.push []).push []) cursor (.epsilon source .plain)
    let g := edge g source (.epsilon next .open)
    compileLoop n cs g next (some source) 1
  | n + 1, ')' :: cs, g, cursor, group, count => do
    let some source := group | throw "unmatched closing parenthesis"
    let next := g.size
    let g := edge (g.push []) cursor (.epsilon next .close)
    let (g, rest) := quantifier g source next cs true
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
      -- A repetition returns to this atom alone, not a preceding atom's shared junction.
      let source := next
      let to := source + 1
      let g := edge ((g.push []).push []) cursor (.epsilon source .plain)
      let g := edge g source (.consume to test)
      let (g, rest) := quantifier g source to rest
      compileLoop n rest g to group count

def compile (s : String) : Except String Pattern :=
  compileLoop (s.length + 1) s.toList #[[]] 0 none 0

private def closure (p : Pattern) (pos size : Nat) (seeds : List Nat) : List Nat := Id.run do
  let mut seen : Array Bool := Array.replicate p.graph.size false
  let mut queue : Array Nat := #[]
  for node in seeds do
    unless seen[node]?.getD true do
      seen := seen.set! node true
      queue := queue.push node
  let mut head := 0
  for _ in [:p.graph.size] do
    if let some node := queue[head]? then
      head := head + 1
      for e in p.graph[node]?.getD [] do
        if let .epsilon target mark := e then
          if (mark != .start || pos == 0) && (mark != .finish || pos == size) then
            unless seen[target]?.getD true do
              seen := seen.set! target true
              queue := queue.push target
  return queue.toList

private structure Thread where
  node : Nat
  pos : Nat
  first : Option Nat := none
  last : Option Nat := none

private inductive Step where
  | visit (thread : Thread)
  | accept (thread : Thread)

/-- Future reachability depends on node, position + the group's current iteration start, never
its previous capture end. DFS's first visit dominates every later history with that key. -/
private def capture (p : Pattern) (cs : Array Char) (start stop : Nat) : Option String := Id.run do
  let mut pending := [Step.visit ⟨0, start, none, none⟩]
  let mut seen : Std.HashSet (Nat × Nat × Option Nat) := {}
  -- Each key expands once; each expansion pushes its edges + at most one acceptance task.
  let edges := p.graph.foldl (fun n es => n + es.length) 0
  let bound := 1 + (edges + p.graph.size) * (stop + 1) * (stop + 2)
  for _ in [:bound] do
    match pending with
    | [] => return none
    | .accept s :: rest =>
      pending := rest
      if s.pos == stop then
        return some (match s.first, s.last with
          | some first, some last => String.ofList (cs.extract first last).toList
          | _, _ => "")
    | .visit s :: rest =>
      pending := rest
      let key := (s.node, s.pos, s.first)
      unless seen.contains key do
        seen := seen.insert key
        let next := (p.graph[s.node]?.getD []).filterMap fun e =>
          match e with
          | .consume target test =>
            match cs[s.pos]? with
            | some c => if s.pos < stop && test.holds c then
                some (Step.visit { s with node := target, pos := s.pos + 1 }) else none
            | none => none
          | .epsilon target mark =>
            if (mark != .start || s.pos == 0) && (mark != .finish || s.pos == cs.size) &&
                (mark != .repeatGroup || s.first != some s.pos) then
              some (Step.visit { s with
                node := target
                first := if mark == .open then some s.pos else s.first
                last := if mark == .close then some s.pos else s.last })
            else none
        -- At an accepting node, another body iteration still precedes the regex's exit.
        let exit := if s.node + 1 == p.graph.size then [Step.accept s] else []
        pending := next ++ exit ++ pending
  return none

private def cursor (p : Pattern) (cs : Array Char) (start : Nat) : Option String := do
  let stop ← Id.run do
    let mut states := closure p start cs.size [0]
    let mut found : Option Nat := none
    for pos in [start:cs.size + 1] do
      if states.any (· + 1 == p.graph.size) then found := some pos
      if let some c := cs[pos]? then
        let next := states.flatMap fun node => (p.graph[node]?.getD []).filterMap fun e =>
          match e with
          | .consume target test => if test.holds c then some target else none
          | _ => none
        states := closure p (pos + 1) cs.size next
      if states.isEmpty then break
    return found
  capture p cs start stop

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
