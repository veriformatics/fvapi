#!/usr/bin/env bash
# CI gate (.claude/rules/gate.md): the full gate on GitHub for the committed HEAD. Pushes it to
# ci/<unit>, waits for that commit's gate run, and is green only when every shard job of
# tools/gate.sh completed with conclusion success (a missing, skipped, cancelled or timed-out job
# is red). Prints the commit, its tree, each job's conclusion + wall-clock and the fan-out time;
# deletes the branch when green, and only while it still names the tested commit. Never pushes
# main. Usage: tools/ci-gate.sh <unit>. rc 0 = green, 1 = red (branch kept), 2 = no run to judge
# or an invalid call.
set -uo pipefail

# Shards (arguments) without exactly one job `gate (<shard>)` of conclusion success in a
# `gh run view --json jobs` document (stdin-free: the document is $1). Probed with fixtures.
ci_missing() {
    local doc="$1"
    shift
    jq -r --args '
        . as $run | $ARGS.positional[]
        | . as $s | [$run.jobs[] | select(.name == "gate (\($s))" and .conclusion == "success")]
        | if length == 1 then empty else $s end' "$@" <<<"$doc"
}

main() {
    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    cd -- "$root" || exit 2
    [[ $# -eq 1 && "$1" =~ ^[A-Za-z0-9._-]+$ ]] || {
        printf 'usage: tools/ci-gate.sh <unit>   (unit = [A-Za-z0-9._-]+)\n' >&2
        exit 2
    }
    branch="ci/$1"
    # CI checks out the commit alone: an uncommitted edit would go untested yet look tested.
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'ci-gate: uncommitted changes; commit (or amend) first\n' >&2
        exit 2
    fi
    sha="$(git rev-parse HEAD)" || exit 2
    tree="$(git rev-parse 'HEAD^{tree}')" || exit 2
    mapfile -t shards < <(bash -c 'source tools/gate.sh; shard_names')
    [[ ${#shards[@]} -gt 0 ]] || {
        printf 'ci-gate: tools/gate.sh names no shard\n' >&2
        exit 2
    }
    git push -f -q origin "HEAD:refs/heads/$branch" || exit 2

    id=""
    for _ in $(seq 60); do
        id="$(gh run list -b "$branch" -c "$sha" -w gate -L 1 --json databaseId --jq '.[0].databaseId // empty')"
        [[ -n "$id" ]] && break
        sleep 5
    done
    if [[ -z "$id" ]]; then
        printf 'ci-gate: no gate run for %s on %s within 5 min\n' "${sha:0:7}" "$branch" >&2
        exit 2
    fi
    printf 'ci-gate: run %s · commit %s · tree %s\n' "$id" "${sha:0:7}" "$tree"

    gh run watch "$id" --exit-status --interval 15 >/dev/null
    watch_rc=$?
    jobs="$(gh run view "$id" --json headSha,conclusion,jobs)" || {
        printf 'ci-gate: run %s unreadable\n' "$id" >&2
        exit 2
    }
    jq -r '
        def secs: if .completedAt and .startedAt then ((.completedAt | fromdate) - (.startedAt | fromdate) | tostring) + "s" else "?" end;
        (.jobs[] | "\(.name) \(.conclusion // .status) \(secs)"),
        ([.jobs[] | select(.name | startswith("gate")) | select(.completedAt and .startedAt)] |
            if length > 0 then "gate fan-out \((map(.completedAt | fromdate) | max) - (map(.startedAt | fromdate) | min))s" else empty end)' <<<"$jobs"
    missing="$(ci_missing "$jobs" "${shards[@]}")"
    head_sha="$(jq -r .headSha <<<"$jobs")"
    if [[ $watch_rc -ne 0 || -n "$missing" || "$head_sha" != "$sha" ]]; then
        printf 'ci-gate: run %s red (watch rc %d; shards without a successful job: %s; run commit %s); %s kept (gh run view %s --log-failed)\n' \
            "$id" "$watch_rc" "${missing//$'\n'/ }" "${head_sha:0:7}" "$branch" "$id" >&2
        exit 1
    fi
    if git push -q --force-with-lease="refs/heads/$branch:$sha" origin ":refs/heads/$branch"; then
        printf 'ci-gate: green; %s deleted\n' "$branch"
    else
        printf 'ci-gate: green, but %s was not deleted (it no longer names %s?)\n' "$branch" "${sha:0:7}" >&2
    fi
}

# Sourcing exposes ci_missing without pushing (tools/gate-probe.sh).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
