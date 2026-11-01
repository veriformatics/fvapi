#!/usr/bin/env bash
# Invoke through tools/vflab-run. Protocol: 0 pass, 1 assertion, 2 setup, 3 crash.
set -uo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$root" || exit 2
prepared=0
if [[ "${1:-}" == --prepared ]]; then prepared=1; shift; fi
suite="${1:-all}"
if [[ $# -gt 1 || ! "$suite" =~ ^(T([1-9]|10)|all|self)$ ]]; then
    printf 'setup: usage: TestsU3/run.sh [--prepared] [T1..T10|all|self]\n' >&2
    exit 2
fi
for tool in lake python3 jq sha256sum timeout; do
    if ! command -v "$tool" >/dev/null; then
        printf 'setup: missing %s\n' "$tool" >&2
        exit 2
    fi
done
mkdir -p .lake/tests-u3 || exit 2
if [[ $prepared -eq 0 ]]; then
    python3 -I TestsU3/corpus.py .lake/tests-u3 || exit 2
fi
if [[ ! -s .lake/tests-u3/json.tsv || ! -s .lake/tests-u3/nist.tsv ||
    ! -s .lake/tests-u3/hash.tsv ]]; then
    printf 'setup: prepared corpus incomplete\n' >&2
    exit 2
fi
if [[ "$suite" == self ]]; then target=fvapi-tests-u3-oracle; else target=fvapi-tests-u3; fi
lake build "$target" > .lake/tests-u3/build.log 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then
    head -35 .lake/tests-u3/build.log >&2
    printf '%s setup: adapter/target unavailable (lake rc=%s)\n' "$suite" "$rc" >&2
    [[ $rc -lt 128 ]] && exit 2
    exit 3
fi
run_native() {
    timeout --signal=TERM 300 "$@"
    local rc=$?
    case "$rc" in
        0|1|2|3) return "$rc" ;;
        *) printf 'crash: native process rc=%s\n' "$rc" >&2; return 3 ;;
    esac
}
if [[ "$suite" == self ]]; then
    run_native .lake/build/bin/fvapi-tests-u3-oracle .lake/tests-u3
    exit $?
fi
if [[ "$suite" == T8 ]]; then
    python3 -I TestsU3/resources.py .lake/build/bin/fvapi-tests-u3 .lake/tests-u3
    exit $?
fi
run_native .lake/build/bin/fvapi-tests-u3 "$suite" .lake/tests-u3
rc=$?
if [[ $rc -eq 0 && "$suite" == all ]]; then
    python3 -I TestsU3/resources.py .lake/build/bin/fvapi-tests-u3 .lake/tests-u3
    rc=$?
fi
exit "$rc"
