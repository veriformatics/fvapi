#!/usr/bin/env bash
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 2
mode=${1:-all}
if [[ $# -gt 1 || ! $mode =~ ^(f|w|all)$ ]]; then
  printf 'usage: TestsU3B/run.sh [f|w|all]\n' >&2
  exit 2
fi
mkdir -p .lake/tests-u3b
if [[ $mode == f || $mode == all ]]; then
  rm -f .lake/tests-u3b/fsync.jsonl .lake/tests-u3b/tasks-build.log
fi
if [[ $mode == w || $mode == all ]]; then
  rm -f .lake/tests-u3b/wire.jsonl
fi
start=$SECONDS
if ! lake build fvapi >.lake/tests-u3b/build.log 2>&1; then
  tail -40 .lake/tests-u3b/build.log >&2
  exit 2
fi
result=0
run() {
  "$@"
  local rc=$?
  if (( rc > 3 )); then rc=3; fi
  if (( rc > result )); then result=$rc; fi
}
if [[ $mode == f || $mode == all ]]; then
  if ! cc -std=gnu11 -Wall -Wextra -Werror -O2 -fPIC -shared TestsU3B/interpose.c \
    -ldl -pthread -o .lake/tests-u3b/interpose.so || \
    ! cc -std=gnu11 -Wall -Wextra -Werror -O2 TestsU3B/probe.c -o .lake/tests-u3b/probe || \
    ! cc -std=gnu11 -Wall -Wextra -Werror -O2 TestsU3B/race-probe.c -pthread -o .lake/tests-u3b/race-probe; then
    exit 2
  fi
  python3 -I TestsU3B/fsync.py --selftest
  rc=$?
  if (( rc )); then exit 2; fi
  run python3 -I TestsU3B/fsync.py
fi
if [[ $mode == w || $mode == all ]]; then
  python3 -I TestsU3B/wire.py --selftest
  rc=$?
  if (( rc )); then exit 2; fi
  run python3 -I TestsU3B/wire.py
fi
printf 'u3b: mode=%s rc=%s wall=%ss\n' "$mode" "$result" "$((SECONDS-start))"
exit "$result"
