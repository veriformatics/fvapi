"""Independent Tiny-package inputs + observing wrappers for the ruled P3 controls."""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".lake/build/bin/fvapi"
HARNESS = ROOT / ".lake/build/bin/fvapi-tests-replay"
NAMES = ["leanchecker", "leanchecker-paranoid", "lean4lean", "nanoda", "con-leche", "con-ron"]
AXIOMS = ["propext", "Classical.choice", "Quot.sound"]


class SetupError(RuntimeError):
    pass


class SubjectCrash(Exception):
    pass


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SetupError("fixture loader: " + str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def need(ok, message):
    if not ok:
        raise AssertionError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relock(path, value):
    path.write_text(json.dumps(value) + "\n")
    raw = subprocess.run(["jq", "-S", "-c", "del(.id)", str(path)],
                         capture_output=True, check=True).stdout
    if not raw.endswith(b"\n"):
        raise SetupError("canonical profile encoder")
    value["id"] = "sha256:" + hashlib.sha256(raw[:-1]).hexdigest()
    path.write_text(json.dumps(value) + "\n")


def fixture(directory, **settings) -> dict[str, Any]:
    u2 = load(ROOT / "TestsU2/fixtures.py", "ruled_u2_fixtures")
    directory.mkdir(parents=True)
    package, source = directory / "package", directory / "expected-source"
    for name, content in u2.SOURCES.items():
        u2.write(package / name, content)
    u2.write(package / "lean-toolchain", (ROOT / "lean-toolchain").read_text())
    identity = u2.snapshot(package, source)
    u2.inventory(package, identity)
    base = json.loads((ROOT / "verify/profile.json").read_text())
    prefix = Path(subprocess.run(["lean", "--print-prefix"], capture_output=True,
                                 text=True, check=True).stdout.strip())
    config = {"package": str(package), "real_exporter": base["exporter"]["executable"].replace(
        "{lean_prefix}", str(prefix)), "real_lake": str(prefix / "bin/lake"), **settings}
    (directory / "case.json").write_text(json.dumps(config))
    bin_dir = directory / "bin"
    bin_dir.mkdir()
    for name in ["exporter", "comparator", *NAMES]:
        shutil.copyfile(Path(__file__).with_name("actor.py"), bin_dir / name)
        (bin_dir / name).chmod(0o755)
    profile = copy.deepcopy(base)
    profile["canaries"]["files"] = {}
    profile["caps"].update(export_ms=30000, comparator_ms=10000, memory_bytes=8589934592)
    profile["kernels"] = []
    for name in settings.get("names", NAMES):
        configured = name in settings.get("configured", [])
        kernel = {"name": name, "executable": str(bin_dir / name), "sha256": digest(bin_dir / name),
                  "args": ["{config}" if configured else "{export}"], "timeout_ms": 3000,
                  "status_map": {"0": "accept", "4": "decline"},
                  "decline_pattern": "^UNSUPPORTED:(.*)$"}
        if configured:
            kernel["config_template"] = {"export": "{export}", "marker": name,
                                          "self": "{config}", "axioms": "{axioms}"}
        profile["kernels"].append(kernel)
    for role in ("exporter", "comparator"):
        profile[role].update(executable=str(bin_dir / role), sha256=digest(bin_dir / role))
    if settings.get("comparator") == "timeout":
        profile["caps"]["comparator_ms"] = 200
    profile_path = directory / "profile.json"
    relock(profile_path, profile)
    # Record actual private-tree allocation + supervisor launches; delegate their OS calls.
    for name, text in {
        "mktemp": '''#!/usr/bin/env python3
import os,subprocess,sys
from pathlib import Path
r=subprocess.run(["/usr/bin/mktemp",*sys.argv[1:]],capture_output=True)
if r.returncode==0 and any("fvapi-replay." in x for x in sys.argv[1:]):
 Path(os.environ["FVAPI_REPLAY_CASE"],"run-dir").write_bytes(r.stdout)
sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr)
raise SystemExit(r.returncode)
''',
        "setsid": '''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
with Path(os.environ["FVAPI_REPLAY_CASE"],"launches.jsonl").open("a") as f:
 f.write(json.dumps({"argv":sys.argv[1:],"time_ns":time.time_ns()})+"\\n")
os.execv("/usr/bin/setsid",["setsid",*sys.argv[1:]])
''',
    }.items():
        (bin_dir / name).write_text(text)
        (bin_dir / name).chmod(0o755)
    env = dict(os.environ, FVAPI_REPLAY_CASE=str(directory),
               PATH=str(bin_dir) + ":" + os.environ["PATH"])
    return {"root": directory, "package": package, "source": source, "profile": profile,
            "profile_path": profile_path, "snapshot": identity, "config": config,
            "env": env, "prefix": prefix, "u2": u2}


def configure(case, **values):
    case["config"].update(values)
    (case["root"] / "case.json").write_text(json.dumps(case["config"]))


def build_fault(case, kind):
    configure(case, build_fault=kind,
              original_source_hex=(case["source"] / "FvapiSelf/Tiny.lean").read_bytes().hex())
    script = case["root"] / "build-fault.py"
    script.write_text('''import hashlib,json,sys,time
from pathlib import Path
case=Path(sys.argv[1]); cfg=json.loads((case/"case.json").read_text()); kind=cfg["build_fault"]
scratch=Path((case/"run-dir").read_text().strip())
paths=[]
if kind.startswith("source-add") or kind=="source-set-bytes":
 paths.append(case/"expected-source/added-input.txt")
if kind.startswith("source-byte") or kind=="source-set-bytes":
 paths.append(case/"expected-source/FvapiSelf/Tiny.lean")
if kind.startswith("challenge-add"):
 paths.append(scratch/"challenge/added-input.txt")
if kind=="challenge-output":
 paths.append(scratch/"challenge/.lake/build/fixture-output.bin")
for path in paths:
 path.parent.mkdir(parents=True,exist_ok=True)
 before=hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
 path.write_bytes((path.read_bytes() if path.exists() else b"")+b"\\n-- build fault\\n")
 with (case/"events.jsonl").open("a") as f:
  f.write(json.dumps({"role":"build-fault","kind":kind,"path":str(path),"before":before,
   "after":hashlib.sha256(path.read_bytes()).hexdigest(),"time_ns":time.time_ns()})+"\\n")
''')
    proof = case["package"] / "FvapiProof/Tiny.lean"
    original = proof.read_text()
    hook = ("import Lean\nimport FvapiSelf.Tiny\nopen Lean\nrun_cmd do\n"
            "  let out ← IO.Process.output { cmd := \"python3\", args := #[\"-I\", " +
            json.dumps(str(script)) + ", " + json.dumps(str(case["root"])) + "] }\n"
            "  unless out.exitCode == 0 do throwError \"{out.stderr}\"\n")
    proof.write_text(hook + original.split("\n", 1)[1])


def records(path):
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def replay(case, strace=False):
    argv = [str(BINARY), "dev", "replay", "--package", str(case["package"]), "--inventory",
            str(case["package"] / "verify/claims.json"), "--profile", str(case["profile_path"]),
            "--expected-source", str(case["source"]), "--axioms", ",".join(AXIOMS), "--json"]
    if strace:
        argv = ["strace", "-f", "-ttt", "-s", "4096", "-e", "trace=openat,execve", "-o",
                str(case["root"] / "strace.log"), *argv]
    started = time.monotonic()
    result = subprocess.run(argv, cwd=ROOT, env=case["env"], capture_output=True, text=True)
    if result.returncode < 0 or result.returncode >= 128:
        raise SubjectCrash(f"replay died {result.returncode}: {result.stderr}")
    try:
        found = [json.loads(line) for line in result.stdout.splitlines() if line]
    except ValueError as error:
        raise AssertionError("malformed replay JSON: " + result.stdout + result.stderr) from error
    need(len(found) == 1 and isinstance(found[0], dict), "one structured claim record")
    return result.returncode, found[0], records(case["root"] / "events.jsonl"), time.monotonic() - started


def check_result(case, rc, record, passed=False, causes=()):
    need((rc == 0) == passed and record.get("verdict") == ("pass" if passed else "fail"),
         f"verdict/rc: expected {'PASS' if passed else 'FAIL'}, got {rc}/{record.get('verdict')}")
    got = record.get("causes", [])
    need(isinstance(got, list) and all(isinstance(code, str) for code in got), "string cause array")
    need(len(got) == len(set(got)), "distinct cause array")
    need(set(causes) <= set(got), "missing causes " + repr(set(causes) - set(got)))
    if passed:
        need(got == [], "PASS has no failure causes")
        need(record.get("profile") == case["profile"]["id"] and
             record.get("snapshot") == case["snapshot"], "input identities")


def cleanup(case):
    marker = case["root"] / "run-dir"
    if marker.exists():
        scratch = Path(marker.read_text().strip())
        if scratch.parent != Path("/tmp") or not scratch.name.startswith("fvapi-replay."):
            raise SetupError("private-tree cleanup provenance")
        if scratch.exists():
            for directory, _, _ in os.walk(scratch):
                Path(directory).chmod(0o755)
            shutil.rmtree(scratch)
