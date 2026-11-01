#!/usr/bin/env -S python3 -I
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

LINEAGES = {"leanchecker": "lean", "leanchecker-paranoid": "lean", "lean4lean": "lean", "nanoda": "nanoda", "con-leche": "con", "con-ron": "con"}
IDENTITY = re.compile(r"sha256:[0-9a-f]{64}\Z")
DIGEST = re.compile(r"(?:sha256:)?[0-9a-f]{64}\Z")


def parse_records(raw):
    try:
        one = json.loads(raw)
        if isinstance(one, dict):
            return [one]
    except json.JSONDecodeError:
        pass
    records = [json.loads(line) for line in raw.splitlines() if line.strip()]
    if not records or not all(isinstance(record, dict) for record in records):
        raise ValueError("stdout must contain JSON object records")
    return records


def trace_records(root):
    trace = Path(root) / "trace.jsonl"
    return [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []


def live_owned(root):
    observed = []
    for record in trace_records(root):
        for key in ("pid", "child_pid"):
            pid = record.get(key)
            if not isinstance(pid, int):
                continue
            proc = Path("/proc") / str(pid)
            try:
                cmdline = (proc / "cmdline").read_bytes().replace(b"\x00", b" ").decode(errors="replace")
                state = (proc / "stat").read_text().split(") ", 1)[1][0]
            except FileNotFoundError:
                continue
            owned = str(root) in cmdline or (key == "child_pid" and "u2-owned-child:" + str(record["pid"]) in cmdline)
            if owned or state == "Z":
                observed.append(pid)
    return sorted(set(observed))


def verify(args):
    cases = json.loads(Path(args.manifest).read_text())
    item = next(case for case in cases if case["id"] == args.case_id)
    expected = item["expected"]
    stdout = Path(args.stdout).read_text(errors="replace")
    stderr = Path(args.stderr).read_text(errors="replace")
    errors = []

    def need(ok, message):
        if not ok:
            errors.append(message)

    need(item["base_profile_available"], "validated base profile missing (fixture cannot earn green)")
    rc = int(args.rc)
    need(rc != 0 if expected["rc"] == "nonzero" else rc == expected["rc"], f"CLI rc={rc}, expected {expected['rc']}")
    try:
        records = parse_records(stdout)
    except (ValueError, json.JSONDecodeError) as error:
        records = []
        need(False, "stdout is not JSON records: " + str(error))
    trace = trace_records(item["root"])
    if item["action"] == "profile":
        if records:
            if expected["valid"]:
                need(all(not r.get("error") and r.get("verdict") != "fail" and r.get("valid") is not False for r in records), "positive profile reported failure")
            else:
                need(any(r.get("error") or r.get("verdict") == "fail" or r.get("valid") is False for r in records), "negative profile lacks structured failure")
            if expected.get("field"):
                field = expected["field"]
                diagnostics = [{key: r[key] for key in ("error", "detail", "message", "diagnostics", "fields", "field", "path") if key in r} for r in records]
                need(re.search(r"(?<![A-Za-z0-9])" + re.escape(field) + r"(?![A-Za-z0-9])", json.dumps(diagnostics)) is not None, "diagnostic does not name field " + field)
    elif expected.get("structured_failure"):
        need(bool(records) and any(r.get("error") or r.get("verdict") == "fail" for r in records), "inventory violation lacks structured JSON failure")
        need(all(r.get("verdict") != "pass" for r in records), "invalid inventory emitted PASS")
    else:
        inventory = json.loads(Path(item["inventory"]).read_text())["claims"]
        need(len(records) == expected.get("records", 1), "wrong number of per-claim records")
        observed_claims = [r.get("claim") for r in records]
        if expected.get("records", 1) > 1 and records:
            configs = [r.get("config") for r in records]
            need(len(set(configs)) == len(records), "different claims reused one theorem-config identity")
        for row in inventory:
            need(sum(claim in {row["id"], row["claim"]} for claim in observed_claims) == 1, "missing/duplicate record for " + row["id"])
        causes = set()
        for record in records:
            need(record.get("verdict") in {"pass", "fail"}, "record lacks pass/fail verdict")
            values = record.get("causes")
            need(isinstance(values, list) and all(isinstance(code, str) for code in values), "causes must be string array")
            if isinstance(values, list):
                causes.update(code for code in values if isinstance(code, str))
            if expected.get("exports"):
                need(record.get("snapshot") == item["snapshot_id"], "wrong frozen snapshot identity")
                profile = json.loads(Path(item["profile"]).read_text())
                need(record.get("profile") == profile["id"], "wrong profile identity")
                need(bool(IDENTITY.fullmatch(str(record.get("config", "")))), "missing config identity")
                exports = record.get("exports", {})
                for side in ("challenge_sha256", "solution_sha256"):
                    need(bool(DIGEST.fullmatch(str(exports.get(side, "")))), "missing complete export hash " + side)
                comparator = record.get("comparator", {})
                need(isinstance(comparator.get("status"), str) and type(comparator.get("rc")) is int, "missing comparator status/rc")
                if expected.get("comparator_nonzero"):
                    need(comparator.get("rc") != 0, "binding/axiom failure did not reach comparator")
                elif expected.get("comparator_rc") is not None:
                    need(comparator.get("rc") == expected["comparator_rc"], "wrong comparator failure rc")
                elif record.get("verdict") == "pass" or expected.get("kernel_controls"):
                    need(comparator.get("rc") == 0, "kernel controls must reach comparator rc 0")
                results = record.get("kernels", [])
                need(isinstance(results, list), "kernels must be array")
                if isinstance(results, list):
                    names = [result.get("name") for result in results]
                    need(len(names) == len(set(names)), "duplicate per-kernel results")
                    if record.get("verdict") == "pass" or expected.get("kernel_controls"):
                        need(set(names) == {k["name"] for k in profile["kernels"]}, "incomplete/extra kernel coverage")
                    for result in results:
                        name = result.get("name")
                        status = result.get("status")
                        need(name in LINEAGES, "unrecognized kernel id")
                        need(result.get("lineage") == LINEAGES.get(name), "wrong id-derived lineage")
                        need(status in {"accept", "reject", "decline", "crash", "timeout"}, "invalid kernel status")
                        need(isinstance(result.get("wall_ms"), (int, float)) and not isinstance(result.get("wall_ms"), bool) and result["wall_ms"] >= 0, "missing nonnegative kernel timing")
                        need("rc" in result and (result["rc"] is None or type(result["rc"]) is int), "missing kernel rc")
                        if status == "accept":
                            need(result.get("rc") == 0, "accept rc is not mapped exit 0")
                        if status == "reject":
                            need(result.get("rc") == 3, "reject rc is not mapped exit 3")
                        if status == "decline" and name in expected.get("statuses", {}):
                            need(result.get("feature") == "x" and result.get("rc") == 4, "decline did not retain mapped feature/rc")
                        target_status = expected.get("statuses", {}).get(name)
                        if target_status:
                            need(status == target_status, f"{name} status={status}, expected {target_status}")
                        solution = str(exports.get("solution_sha256", "")).removeprefix("sha256:")
                        matching_runs = [run for run in trace if run["name"] == name and any(i["sha256"] == solution for i in run["inputs"])]
                        need(len(matching_runs) == 1, f"{name} result needs exactly one executed fake on the immutable solution export")
                        mode_status = {"accept": "accept", "accept-with-decline": "accept", "reject": "reject", "reject-with-decline": "reject", "decline-x": "decline", "timeout": "timeout", "signal": "crash", "unmapped": "crash"}
                        for run in matching_runs:
                            if run["mode"] in mode_status:
                                need(status == mode_status[run["mode"]], f"{name} status disagrees with its executed exit/stderr mapping")
                            if run["mode"] == "decline-x":
                                need(result.get("feature") == "x" and result.get("rc") == 4, "mapped decline lost its feature/rc")
            if record.get("verdict") == "pass":
                need(record.get("causes") == [], "PASS has failure causes")
        for code in expected.get("causes", []):
            need(code in causes, "missing cause " + code)
        if expected.get("any_causes"):
            need(bool(causes.intersection(expected["any_causes"])), "missing snapshot-binding/build failure cause")
        if "comparator" in expected.get("ran", []):
            for run in trace:
                if run["name"] != "comparator":
                    continue
                arguments = run["argv"]
                need("--paranoid" not in arguments, "comparator aggregate paranoid mode was enabled")
                for flag, key in [("--challenge-from-export", "challenge_sha256"), ("--solution-from-export", "solution_sha256")]:
                    need(arguments.count(flag) == 1, "comparator needs exactly one " + flag)
                    if arguments.count(flag) == 1:
                        index = arguments.index(flag) + 1
                        need(index < len(arguments), "comparator export flag has no file")
                        if index < len(arguments):
                            actual = next((i["sha256"] for i in run["inputs"] if i["path"] == str(Path(arguments[index]).resolve())), None)
                            need(any(actual == str(r.get("exports", {}).get(key, "")).removeprefix("sha256:") for r in records), "comparator received wrong export bytes for " + flag)
        if expected.get("verdict") in {"pass", "fail"}:
            need(bool(records) and all(r.get("verdict") == expected["verdict"] for r in records), "wrong overall per-claim verdict")
        elif expected.get("verdict") == "mixed":
            need(Counter(r.get("verdict") for r in records) == Counter({"pass": 1, "fail": 1}), "expected one PASS and one FAIL")
        if expected.get("verdict") == "pass":
            need(not causes, "PASS has nonempty causes")
    seen = Counter(record["name"] for record in trace)
    if "ran" in expected:
        wanted = set(expected["ran"])
        need(wanted <= set(seen), "fake did not run: " + ",".join(sorted(wanted - set(seen))))
        if not wanted:
            need(not trace, "invalid inventory executed a kernel")
    if expected.get("reaped"):
        need(not live_owned(item["root"]), "owned timeout process tree still exists")
    if not expected.get("allow_snapshot_change"):
        frozen = Path(item["snapshot"])
        manifest = json.loads((frozen / "snapshot.json").read_text())
        for relative, digest in manifest["files"].items():
            path = frozen / relative
            need(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest, "trusted snapshot changed: " + relative)
    report = {"id": item["id"], "command": json.loads(Path(args.command).read_text()), "cli_rc": rc,
              "result": "FAIL" if errors else "PASS", "errors": errors, "stdout": stdout, "stderr": stderr,
              "fake_runs": dict(seen)}
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 1 if errors else 0


def golden(directory):
    root = Path(directory)
    raw = (root / "profile-golden.canonical").read_bytes()
    expected = (root / "profile-golden.sha256").read_text().strip()
    profile = json.loads((root / "profile-golden.json").read_text())
    result = subprocess.run(["jq", "-S", "-c", "del(.id)", str(root / "profile-golden.json")], capture_output=True, check=True)
    checks = {
        "P2-G01-canonical-bytes": result.stdout == raw + b"\n" and len(raw) == 1390,
        "P2-G02-digest": hashlib.sha256(raw).hexdigest() == expected == "649c990f7e4e9dd136f9f207878ecd81b19167654e0982303c6fbf986aabcd17",
        "P2-G03-id": profile["id"] == "sha256:" + expected,
    }
    for test_id, ok in checks.items():
        print(json.dumps({"id": test_id, "result": "PASS" if ok else "FAIL", "bytes": len(raw), "sha256": expected}, sort_keys=True))
    return 0 if all(checks.values()) else 1


def main():
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest="action", required=True)
    p = subs.add_parser("verify")
    for name in ("manifest", "case-id", "stdout", "stderr", "rc", "command"):
        p.add_argument("--" + name, required=True)
    p = subs.add_parser("golden"); p.add_argument("directory")
    p = subs.add_parser("live-pids"); p.add_argument("root")
    p = subs.add_parser("command"); p.add_argument("path"); p.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "verify":
        try:
            return verify(args)
        except (KeyError, TypeError, ValueError, OSError) as error:
            print(json.dumps({"id": args.case_id, "result": "FAIL", "errors": ["malformed record: " + str(error)], "cli_rc": int(args.rc), "stdout": Path(args.stdout).read_text(errors="replace"), "stderr": Path(args.stderr).read_text(errors="replace")}))
            return 1
    if args.action == "golden":
        return golden(args.directory)
    if args.action == "live-pids":
        print(" ".join(map(str, live_owned(args.root))))
        return 0
    Path(args.path).write_text(json.dumps(args.arguments))
    return 0


if __name__ == "__main__":
    sys.exit(main())
