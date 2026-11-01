#!/usr/bin/env bash
set -euo pipefail
U2_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export U2_ROOT
cd -- "$U2_ROOT"
source "$U2_ROOT/TestsU2/interface.sh"
group=${1:-all}
case "$group" in
  golden) exec python3 -I TestsU2/assertions.py golden TestsU2/fixtures ;;
  all|profile|replay|inventory) ;;
  *) printf 'usage: run-blackbox.sh [golden|profile|replay|inventory|all]\n' >&2; exit 2 ;;
esac
workers=${U2_JOBS:-4}
case "$workers" in
  [1-6]) ;;
  *) printf 'SETUP: U2_JOBS must be an integer from 1 to 6\n' >&2; exit 2 ;;
esac
started=$SECONDS
mkdir -p .lake
scratch=$(mktemp -d "$U2_ROOT/.lake/u2-contract.XXXXXXXX")
cleanup() {
  local case_root observed pids
  for case_root in "$scratch"/*/; do
    [[ -f $case_root/trace.jsonl ]] || continue
    observed=$(python3 -I "$U2_ROOT/TestsU2/assertions.py" live-pids "$case_root")
    if [[ -n $observed ]]; then
      printf 'cleanup observed test-owned pids: %s\n' "$observed" >&2
      # Only PIDs observed from this case's fake-executable trace are eligible.
      read -ra pids <<<"$observed"
      kill -KILL "${pids[@]}" 2>/dev/null || true
    fi
  done
  if [[ ${U2_KEEP_FIXTURES:-0} == 1 ]]; then
    printf 'fixtures retained: %s\n' "$scratch" >&2
  else
    rm -rf -- "$scratch"
  fi
}
trap cleanup EXIT
if [[ -z ${U2_FVAPI_BIN:-} ]]; then
  if ! lake build fvapi > "$scratch/build.log" 2>&1; then
    printf 'SETUP: lake build fvapi failed\n' >&2
    cat "$scratch/build.log" >&2
    exit 2
  fi
fi
python3 -I TestsU2/fixtures.py prepare --root "$scratch" --repo "$U2_ROOT" \
  --base "${U2_BASE_PROFILE:-$U2_ROOT/verify/profile.json}" > "$scratch/prepare.json"
run_case() {
  local test_id=$1 action=$2 case_root=$3 scope=$4 rc
  export U2_TEST_TRACE="$case_root/trace.jsonl" U2_COMMAND_FILE="$case_root/command.json"
  if [[ $action == profile ]]; then
    if u2_profile "$case_root/profile.json" "$scope" > "$case_root/stdout" 2> "$case_root/stderr"; then
      rc=0
    else
      rc=$?
    fi
  else
    if u2_replay "$case_root/package" "$case_root/package/verify/claims.json" \
        "$case_root/profile.json" "$case_root/expected-source" > "$case_root/stdout" 2> "$case_root/stderr"; then
      rc=0
    else
      rc=$?
    fi
  fi
  python3 -I TestsU2/assertions.py verify --manifest "$scratch/cases.json" \
    --case-id "$test_id" --stdout "$case_root/stdout" --stderr "$case_root/stderr" \
    --rc "$rc" --command "$U2_COMMAND_FILE"
}
python3 -I TestsU2/fixtures.py list "$scratch/cases.json" "$group" > "$scratch/selected.tsv"
mapfile -t rows < "$scratch/selected.tsv"
cases=${#rows[@]}
if [[ $cases == 0 ]]; then
  printf 'SETUP: no selected cases\n' >&2
  exit 2
fi
# Every worker owns its fixture tree + files. Emit reports only after all workers, in input order.
for row in "${rows[@]}"; do
  IFS=$'\t' read -r test_id action case_root scope <<< "$row"
  while [[ $(jobs -rp | wc -l) -ge $workers ]]; do wait -n || true; done
  (
    set +e
    run_case "$test_id" "$action" "$case_root" "$scope" > "$case_root/report" 2>&1
    status=$?
    printf '%s\n' "$status" > "$case_root/status"
    exit "$status"
  ) &
done
wait || true
failures=0
for row in "${rows[@]}"; do
  IFS=$'\t' read -r test_id action case_root scope <<< "$row"
  if [[ ! -s $case_root/status || ! -s $case_root/report ]]; then
    printf 'blackbox: missing worker result for %s\n' "$test_id" >&2
    printf '{"id":"%s","result":"FAIL","errors":["missing worker result"]}\n' "$test_id"
    failures=$((failures + 1))
  else
    cat "$case_root/report"
    [[ $(<"$case_root/status") == 0 ]] || failures=$((failures + 1))
  fi
done
printf '{"suite":"%s","cases":%s,"failures":%s}\n' "$group" "$cases" "$failures"
printf 'blackbox suite %s: workers=%s wall=%ss\n' "$group" "$workers" "$((SECONDS-started))" >&2
(( failures == 0 ))
