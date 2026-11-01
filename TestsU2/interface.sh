#!/usr/bin/env bash
# All uncontracted CLI spelling is isolated here; MAIN has ruled these flags.
u2_cli() {
  local executable=${U2_FVAPI_BIN:-$U2_ROOT/.lake/build/bin/fvapi}
  python3 -I "$U2_ROOT/TestsU2/assertions.py" command "$U2_COMMAND_FILE" "$executable" "$@"
  "$executable" "$@"
}
u2_profile() {
  u2_cli dev profile --profile "$1" --scope "$2" --json
}
u2_replay() {
  u2_cli dev replay --package "$1" --inventory "$2" --profile "$3" \
    --expected-source "$4" --axioms "${U2_AXIOMS:-propext,Classical.choice,Quot.sound}" --json
}
