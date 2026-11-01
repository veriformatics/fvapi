import TestsU2.Oracle

namespace TestsU2.PolicyCases
open Oracle

abbrev Subject := List Fact → Bool
abbrev Reporting := List Kernel → List Fact → List Kernel

def fact (kernel : Kernel) (status : Status) : Fact := ⟨kernel, status⟩

private def die {α : Type} (id : String) (detail : String) : IO α :=
  throw <| IO.userError s!"FAIL {id}: {detail}"

/-- Inlined so `detail` (a `repr`) builds on failure alone: built eagerly, it cost 250 s of the
differential's 12M comparisons. -/
@[macro_inline] private def check (id : String) (ok : Bool) (detail : String := "assertion") :
    IO Unit :=
  unless ok do die id detail

/-- Eight choices per id: omitted, or one of seven status/feature values. -/
private def visitAssignments (remaining : List Kernel) (rs : List Fact)
    (visit : List Fact → IO Unit) : IO Unit := do
  match remaining with
  | [] => visit rs.reverse
  | kernel :: tail =>
    visitAssignments tail rs visit
    for status in statuses do
      visitAssignments tail (fact kernel status :: rs) visit

/-- `visitAssignments kernels []` as one task per choice for the first id (the suite sits on the
gate's critical path); `visit` returns the comparisons it ran → (bases, comparisons), or the
first failure in choice order. -/
private def visitAll (visit : List Fact → IO Nat) : IO (Nat × Nat) := do
  let seeds := match kernels with
    | [] => [([], [])]
    | first :: rest => ([], rest) :: statuses.map fun status => ([fact first status], rest)
  let tasks ← seeds.mapM fun (seed, rest) => IO.asTask do
    let bases ← IO.mkRef 0
    let comparisons ← IO.mkRef 0
    visitAssignments rest seed fun rs => do
      let ran ← visit rs
      bases.modify (· + 1)
      comparisons.modify (· + ran)
    return (← bases.get, ← comparisons.get)
  tasks.foldlM (init := (0, 0)) fun (n, c) task => do
    let (n', c') ← IO.ofExcept (← IO.wait task)
    return (n + n', c + c')

def differential (subject : Subject) : IO Unit := do
  let (n, c) ← visitAll fun rs => do
    let mut ran := 0
    let samples := [rs, rs.reverse, rs ++ rs, (rs ++ rs).reverse]
    for sample in samples do
      check "P1-DIFF" (subject sample == pass sample) s!"rs={repr sample}"
      ran := ran + 1
    -- All 42 single-fact extensions include same-status and contradictory duplicates.
    for kernel in kernels do
      for status in statuses do
        let sample := rs ++ [fact kernel status]
        check "P1-DIFF-EXT" (subject sample == pass sample) s!"rs={repr sample}"
        ran := ran + 1
    return ran
  check "P1-DOMAIN" (n == 262144 && c == 12058624) s!"bases={n} comparisons={c}"
  IO.println s!"PASS P1-DIFF bases={n} comparisons={c}"

private def lc : Fact := fact .leanchecker .accept
private def nd : Fact := fact .nanoda .accept

private def controls : List (String × List Fact × Bool) :=
  [("P1-C01-empty", [], false),
   ("P1-C02-default-alone", [lc], false),
   ("P1-C03-only-default-accepts", lc :: (kernels.tail.map (fact · (.decline "x"))), false),
   ("P1-C04-lean-lineage-only", [lc, fact .leancheckerParanoid .accept,
     fact .lean4lean .accept, fact .nanoda (.decline "x"),
     fact .conLeche (.decline "x"), fact .conRon (.decline "x")], false),
   ("P1-C05-lean-nanoda", [lc, nd], true),
   ("P1-C06-default-missing", [nd, fact .conLeche .accept], false),
   ("P1-C07-lean-con-leche", [lc, fact .conLeche .accept], true),
   ("P1-C08-lean-con-ron", [lc, fact .conRon .accept], true),
   ("P1-C09-paranoid-not-default", [fact .leancheckerParanoid .accept, nd], false),
   ("P1-C10-port-not-default", [fact .lean4lean .accept, nd], false),
   ("P1-C11-empty-feature", [lc, nd, fact .conRon (.decline "")], false),
   ("P1-C12-space-feature", [lc, nd, fact .conRon (.decline " ")], false),
   ("P1-C13-whitespace-feature", [lc, nd, fact .conRon (.decline " \t\n\r")], false),
   ("P1-C14-trimmed-feature", [lc, nd, fact .conRon (.decline " x ")], true),
   ("P1-C15-duplicate-facts", [nd, lc, nd, lc], true),
   ("P1-C16-independent-decline-only", [lc, fact .nanoda (.decline "x")], false),
   ("P1-C17-all-accept", kernels.map (fact · .accept), true),
   ("P1-C18-all-decline", kernels.map (fact · (.decline "x")), false)]

def namedControls (subject : Subject) : IO Unit := do
  let mut count := 0
  for (id, rs, expected) in controls do
    check s!"{id}-oracle" (pass rs == expected) s!"rs={repr rs} expected={expected}"
    check id (subject rs == expected) s!"rs={repr rs} expected={expected}"
    count := count + 1
  -- Every id must poison the verdict, including contradictory duplicate facts.
  for kernel in kernels do
    for (tag, status) in [("reject", Status.reject), ("crash", .crash), ("timeout", .timeout)] do
      let rs := [lc, nd, fact kernel status]
      check s!"P1-C19-{repr kernel}-{tag}" (!subject rs) s!"rs={repr rs}"
      count := count + 1
  check "P1-CONTROL-COUNT" (count == 36)
  IO.println s!"PASS P1-CONTROLS cases={count}"

/-- Every unique ordered subset (including the empty profile): Σ P(6,k)=1957. -/
private def profileOrders : Nat → List Kernel → List (List Kernel)
  | 0, _ => [[]]
  | fuel + 1, available =>
    [] :: (available.flatMap fun first =>
      (profileOrders fuel (available.filter (· != first))).map (first :: ·))

private def subsets : List Kernel → List (List Kernel)
  | [] => [[]]
  | k :: ks => let tail := subsets ks; tail ++ tail.map (k :: ·)

def reporting (subject : Reporting) : IO Unit := do
  let (_, diffs) ← visitAll fun rs => do
    let mut ran := 0
    for order in [kernels, kernels.reverse] do
      let sample := (rs ++ rs).reverse
      let got := subject order sample
      check "P1-ACCEPTING-DIFF" (got == accepting order sample)
        s!"order={repr order} rs={repr sample} got={repr got}"
      ran := ran + 1
    return ran
  let comparisons ← IO.mkRef diffs
  let allOrders := profileOrders 6 kernels
  check "P1-PROFILE-ORDERS" (allOrders.length == 1957)
  let allSubsets := subsets kernels
  check "P1-ACCEPTING-SUBSETS" (allSubsets.length == 64)
  let tasks ← allSubsets.mapM fun accepted => IO.asTask do
    let rs := (accepted.map (fact · .accept)) ++ (kernels.map (fact · (.decline "x")))
    let mut ran := 0
    for order in allOrders do
      for profile in [order, order ++ order] do
        for sample in [rs ++ rs, (rs ++ rs).reverse] do
          let got := subject profile sample
          check "P1-ACCEPTING-ORDER" (got == accepting profile sample)
            s!"profile={repr profile} rs={repr sample} got={repr got}"
          ran := ran + 1
    return ran
  for task in tasks do
    let ran ← IO.ofExcept (← IO.wait task)
    comparisons.modify (· + ran)
  for kernel in kernels do
    for status in statuses.tail do
      let rs := [fact kernel .accept, fact kernel status]
      for profile in [kernels, kernels.reverse, kernels ++ kernels.reverse, [], [kernel]] do
        for sample in [rs, rs.reverse] do
          let got := subject profile sample
          check "P1-ACCEPTING-CONFLICT" (got == accepting profile sample)
            s!"profile={repr profile} rs={repr sample} got={repr got}"
          comparisons.modify (· + 1)
  let n ← comparisons.get
  check "P1-ACCEPTING-COUNT" (n == 1025640) s!"comparisons={n}"
  IO.println s!"PASS P1-ACCEPTING comparisons={n}"

private def trimPaddings : Nat → List String
  | 0 => [""]
  | fuel + 1 => "" :: ([" ", "\t", "\n", "\r"].flatMap fun c =>
      (trimPaddings fuel).map (c ++ ·))

/-- Four-char trim boundary: VT/FF/NBSP are content, including when surrounded by trim chars. -/
def featureBoundaries (subject : Subject) : IO Unit := do
  let paddings := trimPaddings 2
  check "P1-FEATURE-PADDINGS" (paddings.length == 21)
  let comparisons ← IO.mkRef 0
  let testFeature (feature : String) (expected : Bool) : IO Unit := do
    for kernel in kernels do
      let rs := [lc, nd, fact kernel (.decline feature)]
      for sample in [rs, rs.reverse, rs ++ rs] do
        check "P1-FEATURE-ORACLE" (pass sample == expected) s!"feature={repr feature}"
        check "P1-FEATURE-BOUNDARY" (subject sample == expected) s!"rs={repr sample}"
        comparisons.modify (· + 1)
  for blank in paddings do
    testFeature blank false
  let content := [String.ofList [Char.ofNat 11], String.ofList [Char.ofNat 12],
    String.ofList [Char.ofNat 160], "x"]
  for middle in content do
    for left in paddings do
      for right in paddings do
        testFeature (left ++ middle ++ right) true
  let n ← comparisons.get
  check "P1-FEATURE-COUNT" (n == 32130) s!"comparisons={n}"
  IO.println s!"PASS P1-FEATURES features=1785 comparisons={n}"

end TestsU2.PolicyCases
