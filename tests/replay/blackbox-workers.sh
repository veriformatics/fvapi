#!/usr/bin/env bash
# The case scheduler overlaps work, preserves order, and fails on bad/missing worker results.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd -- "$root"
mkdir -p .lake
scratch=$(mktemp -d "$root/.lake/blackbox-workers.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
lake build fvapi > "$scratch/build.log" 2>&1 || { cat "$scratch/build.log" >&2; exit 2; }
python3 -I TestsU2/fixtures.py prepare --root "$scratch/expected" --repo "$root" \
    --base verify/profile.json > "$scratch/prepare.json"
python3 -I TestsU2/fixtures.py list "$scratch/expected/cases.json" profile \
    > "$scratch/expected.tsv"
cat > "$scratch/wrapper" <<'PY'
#!/usr/bin/env -S python3 -I
import fcntl,json,os,signal,subprocess,sys
from pathlib import Path
state = Path(os.environ["U2_WORKER_STATE"])
def change(delta, complete=False):
    with (state.parent / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        value = json.loads(state.read_text()) if state.exists() else {"active":0,"peak":0,"done":0}
        value["active"] += delta
        value["peak"] = max(value["peak"], value["active"])
        value["done"] += int(complete)
        state.write_text(json.dumps(value))
change(1)
try:
    target = "P2-P01-caller-nanoda" in os.environ["U2_COMMAND_FILE"]
    mode = os.environ["U2_WORKER_MODE"]
    if target and mode == "fail":
        raise SystemExit(96)
    if target and mode == "missing":
        os.kill(os.getppid(), signal.SIGKILL)
        raise SystemExit(97)
    result = subprocess.run([os.environ["U2_REAL_BIN"], *sys.argv[1:]], check=False)
    raise SystemExit(result.returncode)
finally:
    change(-1, True)
PY
chmod +x "$scratch/wrapper"
export U2_REAL_BIN="$root/.lake/build/bin/fvapi"
export U2_FVAPI_BIN="$scratch/wrapper" U2_JOBS=2
for mode in normal fail missing; do
    export U2_WORKER_MODE="$mode" U2_WORKER_STATE="$scratch/$mode/state.json"
    mkdir -p "$scratch/$mode"
    if bash TestsU2/run-blackbox.sh profile > "$scratch/$mode/output" 2>&1; then rc=0; else rc=$?; fi
    python3 -I - "$scratch" "$mode" "$rc" <<'PY'
import json,sys
from pathlib import Path
root, mode, rc = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
text = (root / mode / "output").read_text()
records = [json.loads(line) for line in text.splitlines() if line.startswith("{")]
suite = [r for r in records if r.get("suite") == "profile"]
assert len(suite) == 1 and suite[0]["cases"] == 152, text
expected = [line.split("\t")[0] for line in (root / "expected.tsv").read_text().splitlines()]
assert [r["id"] for r in records if "id" in r] == expected, "case report order/set changed"
state = json.loads((root / mode / "state.json").read_text())
if mode == "normal":
    assert rc == 0 and suite[0]["failures"] == 0
    assert 2 <= state["peak"] <= 2 and state["done"] == 152, state
else:
    assert rc != 0 and suite[0]["failures"] >= 1, text
    if mode == "missing":
        assert "missing worker result" in text, text
print(f"blackbox-worker {mode}: rc={rc}, peak={state['peak']}, cases=152, order retained")
PY
done
if U2_JOBS=7 bash TestsU2/run-blackbox.sh profile > "$scratch/cap" 2>&1; then rc=0; else rc=$?; fi
[[ $rc == 2 ]] || { cat "$scratch/cap" >&2; exit 1; }
printf '{"suite":"blackbox-workers","cases":4,"failures":0}\n'
