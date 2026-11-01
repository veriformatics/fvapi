#!/usr/bin/env bash
# P3: package builds can regenerate metadata; P4 must validate the runner's original input.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd -- "$root"
export U2_ROOT="$root"
# shellcheck source=TestsU2/interface.sh
source "$root/TestsU2/interface.sh"
mkdir -p .lake
scratch=$(mktemp -d "$root/.lake/inventory-input.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
if ! lake build fvapi > "$scratch/build.log" 2>&1; then
    printf 'SETUP: replay binary does not build\n' >&2
    cat "$scratch/build.log" >&2
    exit 2
fi
python3 -I TestsU2/fixtures.py prepare --root "$scratch" --repo "$root" \
    --base verify/profile.json > "$scratch/prepare.json"
case_root="$scratch/P3-R01-valid"
cp "$case_root/package/verify/claims.json" "$case_root/original-inventory.json"
python3 -I - "$case_root" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
inventory = root / "package/verify/claims.json"
original = json.loads(inventory.read_text())
assert len(original["claims"]) == 1
rewritten = dict(original, claims=[])
proof = root / "package/FvapiProof/Tiny.lean"
source = proof.read_text()
mutation = ("run_cmd do\n  let _ ← IO.FS.writeFile " + json.dumps(str(inventory)) + " "
            + json.dumps(json.dumps(rewritten)) + "\n  pure ()\n")
proof.write_text("import Lean\n" + source.replace("namespace FvapiProof.Tiny", mutation
                 + "namespace FvapiProof.Tiny", 1))
PY
export U2_TEST_TRACE="$case_root/trace.jsonl"
export U2_COMMAND_FILE="$case_root/command.json"
if u2_replay "$case_root/package" "$case_root/package/verify/claims.json" \
    "$case_root/profile.json" "$case_root/expected-source" \
    > "$case_root/stdout" 2> "$case_root/stderr"; then
    rc=0
else
    rc=$?
fi
failed=0
python3 -I TestsU2/assertions.py verify --manifest "$scratch/cases.json" \
    --case-id P3-R01-valid --stdout "$case_root/stdout" --stderr "$case_root/stderr" \
    --rc "$rc" --command "$U2_COMMAND_FILE" || failed=1
python3 -I - "$case_root" <<'PY' || failed=1
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
original = json.loads((root / "original-inventory.json").read_text())["claims"]
rewritten = json.loads((root / "package/verify/claims.json").read_text())["claims"]
records = [json.loads(line) for line in (root / "stdout").read_text().splitlines() if line]
assert len(original) == 1 and rewritten == [], "the build must actually rewrite the input"
assert len(records) == len(original), "only the original claims get replay records"
assert [r.get("claim") for r in records] == [c["id"] for c in original]
assert all(r.get("verdict") == "pass" and r.get("causes") == [] for r in records)
print("inventory-input: original rows=1, rewritten rows=0, original claim PASS records=1")
PY
printf '{"suite":"inventory-input","cases":1,"failures":%s}\n' "$failed"
exit "$failed"
