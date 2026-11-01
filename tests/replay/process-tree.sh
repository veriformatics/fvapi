#!/usr/bin/env bash
# P3 owns every tool's process group after both ordinary exits and deadline expiry.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd -- "$root"
export U2_ROOT="$root"
# shellcheck source=TestsU2/interface.sh
source "$root/TestsU2/interface.sh"
mkdir -p .lake
scratch=$(mktemp -d "$root/.lake/process-tree.XXXXXXXX")
cleanup() {
    local trace observed
    local pids=()
    for trace in "$scratch"/*/trace.jsonl; do
        [[ -f $trace ]] || continue
        observed=$(python3 -I TestsU2/assertions.py live-pids "${trace%/trace.jsonl}")
        if [[ -n $observed ]]; then
            printf 'cleanup observed owned pids: %s\n' "$observed" >&2
            read -r -a pids <<< "$observed"
            kill -KILL "${pids[@]}" 2>/dev/null || true
        fi
    done
    rm -rf -- "$scratch"
}
trap cleanup EXIT
lake build fvapi > "$scratch/build.log" 2>&1 || { cat "$scratch/build.log" >&2; exit 2; }
python3 -I TestsU2/fixtures.py prepare --root "$scratch" --repo "$root" \
    --base verify/profile.json > "$scratch/prepare.json"
failed=0
for case_id in P3-R07-reject P3-R08-timeout-tree; do
    case_root="$scratch/$case_id"
    python3 -I - "$case_root" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
root = Path(sys.argv[1])
executable = root / "bin/con-ron"
source = executable.read_text().replace('if mode == "timeout":',
    'if mode in {"timeout", "reject"}:', 1)
source = source.replace("import time; time.sleep(120)",
    "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(120)")
executable.write_text(source)
profile_path = root / "profile.json"
profile = json.loads(profile_path.read_text())
for kernel in profile["kernels"]:
    if kernel["name"] == "con-ron":
        kernel["sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
profile_path.write_text(json.dumps(profile, indent=2) + "\n")
canonical = subprocess.run(["jq", "-S", "-c", "del(.id)", str(profile_path)],
    capture_output=True, check=True).stdout[:-1]
profile["id"] = "sha256:" + hashlib.sha256(canonical).hexdigest()
profile_path.write_text(json.dumps(profile, indent=2) + "\n")
PY
    export U2_TEST_TRACE="$case_root/trace.jsonl" U2_COMMAND_FILE="$case_root/command.json"
    if u2_replay "$case_root/package" "$case_root/package/verify/claims.json" \
        "$case_root/profile.json" "$case_root/expected-source" \
        > "$case_root/stdout" 2> "$case_root/stderr"; then rc=0; else rc=$?; fi
    case_failed=0
    python3 -I TestsU2/assertions.py verify --manifest "$scratch/cases.json" \
        --case-id "$case_id" --stdout "$case_root/stdout" --stderr "$case_root/stderr" \
        --rc "$rc" --command "$U2_COMMAND_FILE" || case_failed=1
    observed=$(python3 -I TestsU2/assertions.py live-pids "$case_root")
    if [[ -n $observed ]]; then
        printf '%s: owned process tree survived replay: %s\n' "$case_id" "$observed"
        case_failed=1
    else
        printf '%s: owned process tree gone\n' "$case_id"
    fi
    failed=$((failed + case_failed))
done
printf '{"suite":"process-tree","cases":2,"failures":%s}\n' "$failed"
(( failed == 0 ))
