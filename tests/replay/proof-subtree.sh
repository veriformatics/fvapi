#!/usr/bin/env bash
# P4 proof modules may split within their domain while theorem ownership stays exact.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd -- "$root"
export U2_ROOT="$root"
# shellcheck source=TestsU2/interface.sh
source "$root/TestsU2/interface.sh"
mkdir -p .lake
scratch=$(mktemp -d "$root/.lake/proof-subtree.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
lake build fvapi > "$scratch/build.log" 2>&1 || { cat "$scratch/build.log" >&2; exit 2; }
python3 -I TestsU2/fixtures.py prepare --root "$scratch" --repo "$root" \
    --base verify/profile.json > "$scratch/prepare.json"
case_root="$scratch/P3-R01-valid"
python3 -I - "$case_root/package" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = root / "FvapiProof/Tiny.lean"
child = root / "FvapiProof/Tiny/Proof.lean"
child.parent.mkdir()
source.rename(child)
(root / "FvapiProofs.lean").write_text("import FvapiProof.Tiny.Proof\n")
inventory = root / "verify/claims.json"
value = json.loads(inventory.read_text())
value["claims"][0]["proof_module"] = "FvapiProof.Tiny.Proof"
inventory.write_text(json.dumps(value, indent=2) + "\n")
PY
export U2_TEST_TRACE="$case_root/trace.jsonl" U2_COMMAND_FILE="$case_root/command.json"
if u2_replay "$case_root/package" "$case_root/package/verify/claims.json" \
    "$case_root/profile.json" "$case_root/expected-source" \
    > "$case_root/stdout" 2> "$case_root/stderr"; then rc=0; else rc=$?; fi
failed=0
python3 -I TestsU2/assertions.py verify --manifest "$scratch/cases.json" \
    --case-id P3-R01-valid --stdout "$case_root/stdout" --stderr "$case_root/stderr" \
    --rc "$rc" --command "$U2_COMMAND_FILE" || failed=1
printf '{"suite":"proof-subtree","cases":1,"failures":%s}\n' "$failed"
exit "$failed"
