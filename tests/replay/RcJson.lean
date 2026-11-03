import Lean
import Fvapi.Verify.Replay

open Lean Meta Elab Command

-- Check the shipped private serializer definition, including an arbitrary Nat argument.
run_cmd liftTermElabM do
  let env ← getEnv
  let names := env.constants.map₁.toList.filterMap fun (name, _) =>
    if name.toString.endsWith "Fvapi.Verify.Replay.rcJson" then some name else none
  unless names.length == 1 do
    throwError "setup: replay-rc-json-exact: serializer declaration is not unique"
  let function := mkConst names.head!
  let natural := mkConst ``Nat
  let absent := mkApp (mkConst ``Option.none [Level.zero]) natural
  withTransparency .all do
    unless ← isDefEq (mkApp function absent) (mkConst ``Fvapi.Json.Value.null) do
      throwError "assertion: replay-rc-json-exact: absent exit must encode null"
    withLocalDeclD `n natural fun n => do
      let present := mkApp2 (mkConst ``Option.some [Level.zero]) natural n
      let expected := mkApp (mkConst ``Fvapi.Json.Value.int) (mkApp (mkConst ``Int.ofNat) n)
      unless ← isDefEq (mkApp function present) expected do
        throwError "assertion: replay-rc-json-exact: present exit must encode its exact integer"
  logInfo "replay-rc-json-exact: none → null, ∀ n : Nat, some n → int n"
