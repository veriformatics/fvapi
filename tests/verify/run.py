#!/usr/bin/env python3
"""Focused P2 host + CLI seams; fixture/setup errors stay distinct from assertion failures."""

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


class SubjectCrash(Exception):
    pass


def fixtures():
    spec = importlib.util.spec_from_file_location("verify_fixtures", Path(__file__).with_name("fixtures.py"))
    if spec is None or spec.loader is None:
        raise RuntimeError("fixture loader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(ok, message):
    if not ok:
        raise AssertionError(message)


def subject(argv, **kwargs):
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, **kwargs)
    if result.returncode < 0 or result.returncode >= 128:
        raise SubjectCrash(f"subject died rc={result.returncode}: {result.stderr}")
    return result


def profile_cases(fixture, directory):
    _, _, path, original, env = fixture.prepare(directory)
    count = 0

    def run(label, value, scope="caller", runtime=False, valid=True, field=None, exact_rc=None,
            human=False):
        nonlocal count
        fixture.relock(path, value)
        argv = [str(fixture.BINARY), "dev", "profile", "--profile", str(path), "--scope", scope]
        if runtime:
            argv.append("--runtime")
        if not human:
            argv.append("--json")
        result = subject(argv, env=env)
        require(result.returncode == 0 if valid else result.returncode != 0,
                f"{label}: rc={result.returncode}, expected {'success' if valid else 'failure'}")
        if exact_rc is not None:
            require(result.returncode == exact_rc, f"{label}: exact rc {exact_rc}")
        if human:
            require(re.search(r"\bversion\b", result.stdout + result.stderr) is not None,
                    f"{label}: diagnostic must name version")
        else:
            record = json.loads(result.stdout)
            require(isinstance(record, dict), f"{label}: profile report object")
            if "valid" in record:
                require(record["valid"] is valid, f"{label}: truthful present valid")
            if "scope" in record:
                require(record["scope"] == scope, f"{label}: truthful requested scope")
            if "runtime" in record:
                require(record["runtime"] == ("checked" if runtime else "not_checked"),
                        f"{label}: truthful performed runtime check")
            if field:
                diagnostics = record.get("diagnostics", [])
                require(any(isinstance(item, dict) and item.get("field") == field
                            for item in diagnostics), f"{label}: diagnostic field {field}")
        count += 1
        print(f"PASS profile-cli: {label}")

    run("Dreport requested service scope", copy.deepcopy(original), scope="service")
    run("runtime matched six", copy.deepcopy(original), runtime=True)
    two = copy.deepcopy(original)
    two["kernels"] = [k for k in two["kernels"] if k["name"] in {"leanchecker", "nanoda"}]
    run("runtime keeps caller scope with two kernels", two, runtime=True)
    wrong = copy.deepcopy(original)
    wrong["runtime"]["sha256"] = "0" * 64
    run("runtime opt-in: no flag skips runtime mismatch", wrong)
    run("explicit runtime mismatch", wrong, runtime=True, valid=False,
        field="runtime.sha256", exact_rc=1)
    wrong = copy.deepcopy(original)
    wrong["toolchain"] = "leanprover/lean4:v0.0.0"
    run("Ttoolchain", wrong, valid=False, field="toolchain", exact_rc=1)
    wrong = copy.deepcopy(original)
    wrong["version"] = 2
    run("Dreport invalid result", wrong, valid=False, field="version")
    run("human invalid field", wrong, valid=False, human=True)
    for name in ("export_ms", "comparator_ms", "memory_bytes"):
        wrong = copy.deepcopy(original)
        wrong["caps"][name] = 0
        run("positive " + name, wrong, valid=False, field="caps." + name)
    wrong = copy.deepcopy(original)
    wrong["kernels"][0]["timeout_ms"] = 0
    run("positive timeout_ms", wrong, valid=False, field="kernels[0].timeout_ms")
    for code in (128, 129, 255):
        value = copy.deepcopy(original)
        value["kernels"][0]["status_map"] = {str(code): "accept"}
        run("status_map " + str(code), value, valid=code == 128,
            field=None if code == 128 else "kernels[0].status_map")
    return count


def usage_cases(binary):
    cases = [["replay"], ["profile", "--profile", "/unused/profile"], ["not-a-command"], [],
             ["replay", "--package", "/unused/package", "--inventory", "/unused/inventory",
              "--profile", "/unused/profile", "--expected-source", "/unused/source",
              "--axioms", "", "--unexpected", "value"]]
    for args in cases:
        result = subject([str(binary), "dev", *args])
        require(result.returncode == 2 and result.stderr and not result.stdout,
                f"usage {args!r}: exact rc2, nonempty stderr, empty stdout (before replay IO)")
        print(f"PASS dev-usage: {args!r}")
    return len(cases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("group", choices=("host", "profile", "usage", "all"))
    parser.add_argument("--prebuilt", action="store_true")
    args = parser.parse_args()
    fixture = fixtures()
    if not args.prebuilt:
        targets = ["fvapi", "fvapi-tests-host"] if args.group in {"host", "all"} else ["fvapi"]
        build = subprocess.run(["lake", "build", *targets], cwd=ROOT, capture_output=True, text=True)
        if build.returncode:
            raise RuntimeError(build.stdout + build.stderr)
    count = 0
    with tempfile.TemporaryDirectory(prefix="verify-fixture-", dir=ROOT / ".lake") as temporary:
        directory = Path(temporary)
        if args.group in {"host", "all"}:
            host = directory / "host"
            prefix, tree, profile, _, _ = fixture.prepare(host)
            result = subject([str(ROOT / ".lake/build/bin/fvapi-tests-host"),
                              str(prefix), str(tree), str(profile)])
            print(result.stdout, end="")
            if result.returncode and "assertion: host:" not in result.stdout + result.stderr:
                raise RuntimeError(result.stdout + result.stderr)
            require(result.returncode == 0, result.stderr)
            count += 12
        if args.group in {"profile", "all"}:
            count += profile_cases(fixture, directory / "profile")
        if args.group in {"usage", "all"}:
            count += usage_cases(fixture.BINARY)
    print(f"verify-{args.group}: {count} cases, 0 failed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, json.JSONDecodeError) as error:
        print(f"assertion: verify: {error}", file=sys.stderr)
        sys.exit(1)
    except SubjectCrash as error:
        print(f"crash: verify: {error}", file=sys.stderr)
        sys.exit(3)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"setup: verify: {error}", file=sys.stderr)
        sys.exit(2)
