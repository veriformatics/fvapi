#!/usr/bin/env python3
"""P3 survivor regressions: actual export/comparison, controlled faults, exact collected facts."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def helpers():
    spec = importlib.util.spec_from_file_location("replay_cases", Path(__file__).with_name("cases.py"))
    if spec is None or spec.loader is None:
        raise RuntimeError("case loader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SPECS = {
    "valid": {}, "comparator-error": {"comparator": "error"},
    "comparator-timeout": {"comparator": "timeout"},
    "empty-challenge": {"export": {"challenge": "empty"}},
    "empty-solution": {"export": {"solution": "empty"}},
    "nonzero-challenge": {"export": {"challenge": "nonzero"}},
    "nonzero-solution": {"export": {"solution": "nonzero"}},
    "export-io": {"export": {"challenge": "unlink"}},
    "post-comparator": {"comparator": "change-solution"},
    "post-kernel": {"action": "solution-change"},
    "missing-export": {"action": "solution-unlink"},
    "late-pin": {"action": "late-pin", "fault_kernel": "con-leche"},
    "earlier-unnamed": {"modes": {"con-leche": "missing-feature"}},
    "cause-pin": {"action": "cause-pin", "fault_kernel": "con-leche",
                  "modes": {"con-leche": "missing-feature"}},
    "late-io": {"action": "late-io", "fault_kernel": "con-leche", "configured": ["con-ron"],
                "modes": {"con-leche": "missing-feature"}},
    "two-configs": {"names": ["leanchecker", "nanoda"], "configured": ["leanchecker", "nanoda"]},
    "source-byte": {"action": "source-byte"}, "challenge-byte": {"action": "challenge-byte"},
    "challenge-missing": {"action": "challenge-missing"},
    "challenge-unreadable": {"action": "challenge-unreadable"}, "source-add": {"action": "source-add"},
    "challenge-add": {"action": "challenge-add"}, "build-output": {"action": "challenge-output"},
    "dependency-input": {"action": "challenge-package"},
    "build-source-add": {"build_fault": "source-add-restore"},
    "build-source-byte": {"build_fault": "source-byte-restore"},
    "build-challenge-add": {"build_fault": "challenge-add-restore"},
    "build-set-bytes": {"build_fault": "source-set-bytes"},
    "build-output-early": {"build_fault": "challenge-output"},
    "name-underscore": {}, "name-prime": {}, "proof-input": {}, "runtime-once": {},
    **{"zero-" + name: {"cap": name, "cap_value": 0}
       for name in ("export_ms", "comparator_ms", "memory_bytes")},
    **{"one-" + name: {"cap": name, "cap_value": 1}
       for name in ("export_ms", "comparator_ms", "memory_bytes")},
}
GROUPS = {
    "baseline": ["cause-pin", "late-io", "challenge-add", "dependency-input", "build-challenge-add"],
    "exports": ["valid", "comparator-error", "comparator-timeout", "empty-challenge", "empty-solution",
                "nonzero-challenge", "nonzero-solution", "export-io", "post-comparator",
                "post-kernel", "missing-export"],
    "late": ["late-pin", "earlier-unnamed", "cause-pin", "late-io"],
    "freeze": ["source-byte", "challenge-byte", "challenge-missing", "challenge-unreadable",
               "source-add", "challenge-add",
               "dependency-input", "build-source-add", "build-source-byte", "build-challenge-add",
               "build-set-bytes", "build-output", "build-output-early", "proof-input"],
    "names": ["name-underscore", "name-prime"], "configs": ["two-configs"],
    "caps": [name for name in SPECS if name.startswith(("zero-", "one-"))],
    "runtime": ["runtime-once"], "io": ["outer", "freeze-set"],
}


def private_runtime(h, case):
    source = case["prefix"]
    target = case["root"] / "toolchain"
    if source.stat().st_dev != case["root"].stat().st_dev:
        raise h.SetupError("runtime fixture needs same-filesystem immutable hardlinks")
    shutil.copytree(source, target, copy_function=os.link, symlinks=True)
    for directory, _, _ in os.walk(target):
        Path(directory).chmod(0o755)
    sentinel = target / "fvapi-runtime-sentinel"
    sentinel.write_bytes(b"independent manifest scan sentinel\n")
    fixture = h.load(ROOT / "tests/verify/fixtures.py", "replay_manifest_reference")
    case["profile"]["runtime"]["sha256"] = fixture.manifest(target)
    h.relock(case["profile_path"], case["profile"])
    shim = case["root"] / "bin/lean"
    lean = shutil.which("lean")
    if lean is None:
        raise h.SetupError("lean")
    shim.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                    f"if sys.argv[1:] == ['--print-prefix']: print({str(target)!r})\n"
                    f"else: os.execv({lean!r}, [{lean!r}, *sys.argv[1:]])\n")
    shim.chmod(0o755)
    return sentinel


def setup(h, directory, label):
    settings = SPECS[label]
    case = h.fixture(directory, **settings)
    if "cap" in settings:
        case["profile"]["caps"][settings["cap"]] = settings["cap_value"]
        h.relock(case["profile_path"], case["profile"])
    if "build_fault" in settings:
        h.build_fault(case, settings["build_fault"])
    if label in {"name-underscore", "name-prime"}:
        ending = "correct_name" if label == "name-underscore" else "correct'"
        proof = case["package"] / "FvapiProof/Tiny.lean"
        proof.write_text(proof.read_text().replace("theorem correct :", "theorem " + ending + " :"))
        row = dict(case["u2"].CLAIM, proof="FvapiProof.Tiny." + ending)
        case["u2"].inventory(case["package"], case["snapshot"], [row])
    if label == "proof-input":
        path = case["source"] / "FvapiProof/Unused.lean"
        path.parent.mkdir()
        path.write_text("theorem independentUnused : True := True.intro\n")
        manifest_path = case["source"] / "snapshot.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"]["FvapiProof/Unused.lean"] = h.digest(path)
        manifest_path.write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")))
        case["snapshot"] = "sha256:" + h.digest(manifest_path)
        case["u2"].inventory(case["package"], case["snapshot"])
    if label == "runtime-once":
        case["sentinel"] = private_runtime(h, case)
    return case


def validate(h, case, label, rc, record, events):
    kernels = [e for e in events if e["role"] == "kernel"]
    exporters = [e for e in events if e["role"] == "exporter"]
    comparators = [e for e in events if e["role"] == "comparator"]
    faults = [e for e in events if e["role"] in {"fault", "build-fault"}]
    rows = record.get("kernels", [])
    h.need(isinstance(rows, list) and all(isinstance(r, dict) for r in rows), "kernel records")
    names = [r.get("name") for r in rows]
    h.need(len(names) == len(set(names)), "unique kernel ids")
    if kernels:
        solution = record.get("exports", {}).get("solution_sha256")
        h.need(all(e["sha256"] == solution for e in kernels),
               "every executed kernel read the recorded immutable solution bytes")
    passed = label in {"valid", "two-configs", "name-underscore", "name-prime", "build-output",
                       "build-output-early", "runtime-once"}
    wanted = []
    if label in {"cause-pin", "late-io", "earlier-unnamed"}:
        wanted += ["unnamed_unsupported", "kernel_crashed"]
    if label in {"cause-pin", "late-pin"}:
        wanted += ["kernel_identity_mismatch", "kernel_missing"]
    if label.startswith(("empty-", "nonzero-")) or label in {
        "export-io", "post-comparator", "post-kernel", "missing-export"
    }:
        wanted += ["export_failed"]
    if label in GROUPS["freeze"] and label not in {"build-output", "build-output-early"}:
        wanted += ["challenge_mismatch"]
    if label.startswith("zero-"):
        wanted += ["profile_mismatch"]
    if label in {"comparator-error", "comparator-timeout"}:
        wanted += ["comparator_error"]
    if not label.startswith("one-"):
        h.check_result(case, rc, record, passed, wanted)
    else:
        h.need("profile_mismatch" not in record.get("causes", []), "positive one is schema-valid")
    if label.startswith(("zero-", "one-")):
        launches = h.records(case["root"] / "launches.jsonl")
        builds = [r for r in launches if str(case["prefix"] / "bin/lake") in r["argv"] and
                  "build" in r["argv"]]
        if label.startswith("zero-"):
            field = "caps." + label.removeprefix("zero-")
            h.need(field in json.dumps(record.get("diagnostics", [])), "named field " + field)
            h.need(not launches and not events, "zero cap rejects before all supervised tools")
        else:
            h.need(bool(builds), "positive one reaches the real supervised build launch")
        return
    if label in {"proof-input"}:
        h.need(not events and not h.records(case["root"] / "launches.jsonl"),
               "proof inputs reject before any build/export/kernel")
        return
    if "build_fault" in SPECS[label]:
        h.need(any(e["role"] == "build-fault" for e in events), "solution build injected the fault")
        if label == "build-set-bytes":
            h.need(len(faults) == 2 and any(e["before"] is None for e in faults) and
                   any(e["before"] is not None for e in faults), "both path-set + byte edits occurred")
        if not passed:
            h.need(not exporters and not kernels, "post-build mismatch permanently stops replay")
        return
    if label in {"cause-pin", "late-pin", "late-io"}:
        h.need(bool(faults), "late fault actually occurred")
        h.need("con-ron" not in [e["name"] for e in kernels], "affected later kernel never runs")
    if label == "late-io":
        h.need(os.geteuid() != 0 and any(e["operation"] == "readonly-directory" for e in faults),
               "ordinary owner produced a real config permission fault")
        h.need(any(r.get("name") == "con-leche" and r.get("status") == "crash" for r in rows),
               "late IO retains earlier completed kernel status")
    if label in {"empty-challenge", "empty-solution", "nonzero-challenge", "nonzero-solution",
                 "export-io"}:
        h.need({e["side"] for e in exporters} == {"challenge", "solution"}, "both exporters ran")
        h.need(not comparators and not kernels, "failed/incomplete exports stop comparison + kernels")
        results = [e for e in events if e["role"] == "exporter-result"]
        if label.startswith("empty-"):
            side = label.removeprefix("empty-")
            h.need(any(e["side"] == side and e["rc"] == 0 and e["size"] == 0 for e in results),
                   "one successful exporter actually emitted zero bytes")
        if label.startswith("nonzero-"):
            side = label.removeprefix("nonzero-")
            h.need(any(e["side"] == side and e.get("real_rc") == 0 and e["rc"] == 11 and
                       e["size"] > 0 for e in results),
                   "controlled nonzero exit followed a complete real export")
        if label == "export-io":
            h.need(any(e["operation"] == "unlink" for e in faults), "export stdout actually unlinked")
        return
    if label == "post-comparator":
        h.need(bool(faults) and any(e["role"] == "comparator-result" and e["rc"] == 0 for e in events),
               "real comparison accepted before the export changed")
        h.need(not kernels, "no kernel receives post-comparator changed bytes")
        return
    if label in {"post-kernel", "missing-export", "source-byte", "challenge-byte", "challenge-missing",
                 "challenge-unreadable", "source-add", "challenge-add", "dependency-input", "build-output"}:
        h.need(bool(faults), "last kernel actually changed its owned file")
        h.need(set(names) == set(h.NAMES) and all(r.get("status") == "accept" for r in rows),
               "every kernel accepted the original immutable export before the late fault")
    if label in {"valid", "comparator-error", "comparator-timeout"}:
        expected = {"valid": ("accept", 0), "comparator-error": ("error", 2),
                    "comparator-timeout": ("timeout", 124)}[label]
        actual = record.get("comparator", {})
        h.need(actual.get("status") == expected[0] and actual.get("rc") == expected[1],
               "truthful comparator status + raw rc")
    if label == "valid":
        proof = "FvapiProof.Tiny.correct"
        suffix = list(dict.fromkeys([proof, *h.AXIOMS, *case["profile"]["comparator"]["targets"]]))
        h.need(len(exporters) == 2 and all(e["argv"][e["argv"].index("--") + 1:] == suffix
                                        for e in exporters), "export argv: proof, axioms, targets")
    if label == "two-configs":
        h.need(len(kernels) == 2 and {e["name"] for e in kernels} == {"leanchecker", "nanoda"},
               "both configured kernels actually ran")
        h.need(len({e["config_path"] for e in kernels}) == 2, "distinct actual config paths")
        for e in kernels:
            h.need(e["config"] == {"export": e["export"], "marker": e["name"],
                                   "self": e["config_path"], "axioms": h.AXIOMS}, "actual config values")
            row = next(r for r in rows if r.get("name") == e["name"])
            h.need(row.get("config") == "sha256:" + e["config_sha256"], "actual config-byte identity")
    if label == "runtime-once":
        text = (case["root"] / "strace.log").read_text()
        lines = text.splitlines()
        hits = [i for i, line in enumerate(lines) if '"' + str(case["sentinel"]) + '"' in line]
        h.need(len(hits) == 1, f"one runtime manifest scan, observed sentinel opens={len(hits)}")
        executions = [i for i, line in enumerate(lines) if any(
            'execve("' + str(case["root"] / "bin" / name) + '"' in line for name in h.NAMES)]
        h.need(bool(executions) and hits[0] < min(executions),
               "complete manifest scan precedes the first real kernel execve")


def run_one(h, directory, label):
    if label in {"outer", "freeze-set"}:
        directory.mkdir(parents=True)
        result = subprocess.run([str(h.HARNESS), label, str(directory)], cwd=ROOT,
                                capture_output=True, text=True)
        if result.returncode < 0 or result.returncode >= 128:
            raise h.SubjectCrash(f"replay IO harness died rc={result.returncode}")
        if result.returncode and "assertion: replay-io:" not in result.stdout + result.stderr:
            raise h.SetupError(result.stdout + result.stderr)
        h.need(result.returncode == 0, result.stdout + result.stderr)
        print(result.stdout, end="")
        return
    case = setup(h, directory, label)
    try:
        rc, record, events, seconds = h.replay(case, label == "runtime-once")
        try:
            validate(h, case, label, rc, record, events)
        except AssertionError:
            print("observed:", json.dumps({"case": label, "rc": rc, "record": record,
                                           "faults": [e for e in events if e["role"] in {
                                               "fault", "build-fault", "restore"}]}))
            raise
        print(f"PASS replay: {label} ({seconds:.3f}s)", flush=True)
    finally:
        h.cleanup(case)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=["all", *GROUPS], default="all")
    parser.add_argument("--case", action="append", choices=[*SPECS, "outer", "freeze-set"])
    parser.add_argument("--prebuilt", action="store_true")
    args = parser.parse_args()
    h = helpers()
    if not args.prebuilt:
        result = subprocess.run(["lake", "build", "fvapi", "fvapi-tests-replay"], cwd=ROOT,
                                capture_output=True, text=True)
        if result.returncode:
            raise h.SetupError(result.stdout + result.stderr)
    selected = args.case or ([*SPECS, "outer", "freeze-set"] if args.group == "all" else GROUPS[args.group])
    failures = 0
    timings = []
    with tempfile.TemporaryDirectory(prefix="replay-ruled-", dir=ROOT / ".lake") as temporary:
        for label in selected:
            started = time.monotonic()
            try:
                run_one(h, Path(temporary) / label, label)
            except AssertionError as error:
                print(f"assertion: replay: {label}: {error}", file=sys.stderr)
                failures += 1
            except h.SubjectCrash as error:
                print(f"crash: replay-ruled: {error}", file=sys.stderr)
                return 3
            except h.SetupError as error:
                print(f"setup: replay-ruled: {error}", file=sys.stderr)
                return 2
            finally:
                timings.append((time.monotonic() - started, label))
    for seconds, label in sorted(timings, reverse=True)[:3]:
        print(f"slow replay: {label} {seconds:.3f}s")
    print(f"replay-ruled: {len(selected)} cases, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"setup: replay-ruled: {error}", file=sys.stderr)
        sys.exit(2)
