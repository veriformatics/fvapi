#!/usr/bin/env python3
"""P7 zero-site controls: exact exit serialization + kernel argv/config placeholder binding."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".lake/build/bin/fvapi"


class SetupError(Exception):
    pass


class SubjectCrash(Exception):
    pass


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def command(argv, **kwargs):
    kwargs.setdefault("cwd", ROOT)
    return subprocess.run(argv, capture_output=True, text=True, **kwargs)


def relock(path, profile):
    path.write_text(json.dumps(profile, ensure_ascii=False) + "\n")
    canonical = command(["jq", "-S", "-c", "del(.id)", str(path)])
    if canonical.returncode:
        raise SetupError("profile canonicalizer unavailable")
    profile["id"] = "sha256:" + hashlib.sha256(canonical.stdout.encode()[:-1]).hexdigest()
    path.write_text(json.dumps(profile, ensure_ascii=False) + "\n")


def replay(case, axioms, extra_env=None, relative=False):
    env = dict(os.environ, U2_TEST_TRACE=str(case / "trace.jsonl"))
    env.update(extra_env or {})
    path = lambda name: name if relative else str(case / name)
    result = command([str(BINARY), "dev", "replay", "--package", path("package"),
                      "--inventory", path("package/verify/claims.json"), "--profile",
                      path("profile.json"), "--expected-source", path("expected-source"),
                      "--axioms", ",".join(axioms), "--json"], env=env,
                     cwd=case if relative else ROOT)
    if result.returncode < 0 or result.returncode >= 128:
        raise SubjectCrash(f"replay binary died: rc={result.returncode}")
    try:
        records = [json.loads(line) for line in result.stdout.splitlines() if line]
    except ValueError as error:
        raise AssertionError(f"malformed replay record: {result.stdout} {result.stderr}") from error
    require(len(records) == 1 and isinstance(records[0], dict), "one replay record required")
    return result.returncode, records[0]


def kernels(record):
    rows = record.get("kernels", [])
    expected = {"leanchecker", "leanchecker-paranoid", "lean4lean", "nanoda", "con-leche", "con-ron"}
    require(isinstance(rows, list) and len(rows) == 6 and all(isinstance(r, dict) for r in rows),
            "complete kernel run set")
    require({r.get("name") for r in rows} == expected, "exact kernel ids")
    return {r["name"]: r for r in rows}


def rc_json(root):
    check = command(["lake", "env", "lean", "tests/replay/RcJson.lean"])
    if check.returncode:
        if "assertion: replay-rc-json-exact:" in check.stdout + check.stderr:
            raise AssertionError(check.stdout + check.stderr)
        raise SetupError(check.stdout + check.stderr)
    axioms = ["propext", "Classical.choice", "Quot.sound"]
    for case_id, expected in (("P3-R10-unmapped-exit", 9), ("P3-R09-signal", 143)):
        rc, record = replay(root / case_id, axioms)
        rows = kernels(record)
        require(rc == 1 and record.get("verdict") == "fail", f"{case_id}: failure verdict")
        require(rows["con-ron"].get("rc") == expected and type(rows["con-ron"].get("rc")) is int,
                f"{case_id}: exact raw rc {expected}")
        require(rows["con-ron"].get("status") == "crash", f"{case_id}: crash status")
        require(all(r.get("rc") == 0 for k, r in rows.items() if k != "con-ron"), "other raw exits zero")
    case = root / "P3-R01-valid"
    shim = case / "bin/setsid"
    shim.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
if any(arg.endswith("/con-ron.pgid") for arg in sys.argv[1:]):
    Path(os.environ["BINDING_LAUNCH_TRACE"]).write_text(json.dumps(sys.argv[1:]))
    raise SystemExit(97)
os.execv("/usr/bin/setsid", ["setsid", *sys.argv[1:]])
''')
    shim.chmod(0o755)
    trace = case / "launch.json"
    rc, record = replay(case, axioms, {"PATH": str(case / "bin") + ":" + os.environ["PATH"],
                                     "BINDING_LAUNCH_TRACE": str(trace)})
    rows = kernels(record)
    require(trace.is_file() and any(a.endswith("/con-ron.pgid") for a in json.loads(trace.read_text())),
            "controlled launcher must run before any con-ron process")
    require(rc == 1 and record.get("verdict") == "fail" and "kernel_crashed" in record["causes"],
            "launcher failure must fail the claim")
    require("rc" in rows["con-ron"] and rows["con-ron"]["rc"] is None,
            "absent kernel exit must be null, not the launcher exit or invented zero")
    require(rows["con-ron"].get("status") == "crash", "launch failure must be a crash")
    print("replay-rc-json-exact: forall-some + none definition, raw 9/143, controlled absent exit")
    return 4


def relative_paths(root):
    case = root / "P3-R01-valid"
    axioms = ["propext", "Classical.choice", "Quot.sound"]
    rc_absolute, absolute = replay(case, axioms)
    rc_relative, relative = replay(case, axioms, relative=True)
    require(rc_absolute == rc_relative == 0, "absolute and relative replay must both succeed")
    for record in (absolute, relative):
        require(record.get("verdict") == "pass" and record.get("causes") == [],
                "same valid inputs keep PASS across subprocess cwd changes")
        kernels(record)
    for field in ("profile", "snapshot", "exports", "config"):
        require(absolute.get(field) == relative.get(field),
                "absolute/relative identity differs: " + field)
    print("replay-relative-paths: package/inventory/profile/snapshot relative argv keep PASS + identities")
    return 1


def exit128(root):
    case = root / "P3-R01-valid"
    path = case / "profile.json"
    profile = json.loads(path.read_text())
    executable = case / "bin/exit128"
    executable.write_text('''#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
export=Path(sys.argv[1])
Path(os.environ["EXIT128_TRACE"]).write_text(json.dumps({"export":str(export),
    "sha256":hashlib.sha256(export.read_bytes()).hexdigest()}))
raise SystemExit(128)
''')
    executable.chmod(0o755)
    for kernel in profile["kernels"]:
        if kernel["name"] == "con-ron":
            kernel.update(executable=str(executable), sha256=hashlib.sha256(
                executable.read_bytes()).hexdigest(), args=["{export}"],
                status_map={"128": "accept"})
    relock(path, profile)
    trace = case / "exit128.json"
    rc, record = replay(case, ["propext", "Classical.choice", "Quot.sound"],
                        {"EXIT128_TRACE": str(trace)})
    require(trace.is_file(), "ordinary exit128 kernel actually ran")
    event = json.loads(trace.read_text())
    require(event["sha256"] == record["exports"]["solution_sha256"],
            "exit128 kernel read the immutable solution export")
    row = kernels(record)["con-ron"]
    require(type(row.get("rc")) is int and row["rc"] == 128, "exact ordinary exit128")
    require(row.get("status") == "accept", "normal mapped exit128 must accept")
    require(rc == 0 and record.get("verdict") == "pass" and record.get("causes") == [],
            "mapped exit128 must not fail an otherwise valid claim")
    print("replay-exit128: executed normal exit128, raw rc128, mapped accept, final PASS")
    return 1


FAKE = '''#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
name,mode=sys.argv[1:3]
args=sys.argv[3:]
config=None
raw=None
if mode=="config":
    config_path=Path(args[0]); raw=config_path.read_bytes(); config=json.loads(raw)
    export=Path(config["export"])
else:
    export=Path(args[0]); config_path=Path(args[-1].removeprefix("none:"))
row={"name":name,"args":args,"config":config,"config_path":str(config_path),
     "config_exists":config_path.exists(),"raw_hex":None if raw is None else raw.hex(),
     "export":str(export),"export_sha256":hashlib.sha256(export.read_bytes()).hexdigest()}
with Path(os.environ["BINDING_TRACE"]).open("a") as stream: stream.write(json.dumps(row)+"\\n")
'''


def placeholders(root):
    original = root / "P3-R01-valid"
    for label, axioms in (("nonempty", ["propext", "Classical.choice", "Quot.sound"]), ("empty", [])):
        case = root / ("placeholder-" + label)
        shutil.copytree(original, case)
        # Profiles carry absolute fixture paths: keep the original source trees, but all changed
        # executable/config traces are owned by this case and pinned again below.
        profile_path = case / "profile.json"
        profile = json.loads(profile_path.read_text())
        custom = case / "bin/binding-kernel"
        custom.write_text(FAKE)
        custom.chmod(0o755)
        digest = hashlib.sha256(custom.read_bytes()).hexdigest()
        for kernel in profile["kernels"]:
            if kernel["name"] == "con-ron":
                kernel["executable"], kernel["sha256"] = str(custom), digest
                kernel["args"] = ["con-ron", "config", "{config}", "pre:{config}:post", "{export}",
                                  "repeated:{export}|{export}", "{axioms}", "inline:{axioms}"]
                kernel["config_template"] = {"export": "{export}", "literal": "pre:{export}:post",
                    "repeat": "{export}|{export}|{config}|{config}", "self": "{config}",
                    "axioms": "{axioms}", "inline": "pre:{axioms}:post",
                    "array": ["{axioms}", "literal", None, 7, True], "empty": ""}
            elif kernel["name"] == "nanoda":
                kernel["executable"], kernel["sha256"] = str(custom), digest
                kernel["args"] = ["nanoda", "direct", "{export}", "{axioms}", "inline:{axioms}",
                                  "repeated:{export}|{export}", "none:{config}"]
                kernel.pop("config_template", None)
        relock(profile_path, profile)
        trace = case / "binding.jsonl"
        rc, record = replay(case, axioms, {"BINDING_TRACE": str(trace)})
        require(rc == 0 and record.get("verdict") == "pass" and record.get("causes") == [],
                f"{label}: complete valid replay")
        rows = kernels(record)
        require(trace.is_file(), f"{label}: custom kernel trace exists")
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        require(len(events) == 2 and {e["name"] for e in events} == {"con-ron", "nanoda"},
                f"{label}: both custom kernels actually run")
        for event in events:
            export, config = event["export"], event["config_path"]
            require(event["export_sha256"] == record["exports"]["solution_sha256"], "solution bytes bound")
            require(Path(export).name == "solution-export.stdout", "exact solution-export path")
            comma = ",".join(axioms)
            if event["name"] == "con-ron":
                expected = {"export": export, "literal": f"pre:{export}:post",
                    "repeat": f"{export}|{export}|{config}|{config}", "self": config,
                    "axioms": axioms, "inline": f"pre:{comma}:post",
                    "array": [axioms, "literal", None, 7, True], "empty": ""}
                require(event["config"] == expected and event["config_exists"], "exact generated config")
                require(event["args"] == [config, f"pre:{config}:post", export,
                        f"repeated:{export}|{export}", *axioms, f"inline:{comma}"], "exact config argv")
                raw = bytes.fromhex(event["raw_hex"])
                canonical = subprocess.run(["jq", "-S", "-c", "."], input=json.dumps(expected).encode(),
                                           capture_output=True, check=True).stdout[:-1]
                require(raw == canonical, "exact canonical config bytes")
                require(rows["con-ron"].get("config") == "sha256:" + hashlib.sha256(raw).hexdigest(),
                        "record binds actual generated config bytes")
            else:
                require(event["config"] is None and not event["config_exists"] and "config" not in rows["nanoda"],
                        "no template means no file or reported config digest")
                require(event["args"] == [export, *axioms, f"inline:{comma}",
                        f"repeated:{export}|{export}", f"none:{config}"], "exact direct argv")
    print("replay-placeholder-substitution: nonempty/empty axioms, generated/no config, exact argv/bytes/digests")
    return 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=("rc-json", "placeholders", "exit128", "relative"))
    parser.add_argument("--prebuilt", action="store_true")
    args = parser.parse_args()
    for tool in ("lake", "jq", "setsid"):
        if not shutil.which(tool):
            raise SetupError(f"missing {tool}")
    if not args.prebuilt:
        build = command(["lake", "build", "fvapi"])
        if build.returncode:
            raise SetupError(build.stdout + build.stderr)
    (ROOT / ".lake").mkdir(exist_ok=True)
    suites = {"rc-json": ("replay-rc-json-exact", rc_json),
              "placeholders": ("replay-placeholder-substitution", placeholders),
              "exit128": ("replay-exit128", exit128),
              "relative": ("replay-relative-paths", relative_paths)}
    suite, run = suites[args.case]
    with tempfile.TemporaryDirectory(prefix="bindings-", dir=ROOT / ".lake") as directory:
        root = Path(directory)
        prepared = command(["python3", "-I", "TestsU2/fixtures.py", "prepare", "--root", str(root),
                            "--repo", str(ROOT), "--base", str(ROOT / "verify/profile.json")])
        if prepared.returncode:
            raise SetupError(prepared.stdout + prepared.stderr)
        try:
            cases = run(root)
        except (AssertionError, KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
            print(f"assertion: {suite}: {error}", file=sys.stderr)
            print(json.dumps({"suite": suite, "cases": 1, "failures": 1}))
            return 1
    print(json.dumps({"suite": suite, "cases": cases, "failures": 0}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SetupError as error:
        print(f"setup: {error}", file=sys.stderr)
        sys.exit(2)
    except SubjectCrash as error:
        print(f"crash: {error}", file=sys.stderr)
        sys.exit(3)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"setup: {error}", file=sys.stderr)
        sys.exit(2)
