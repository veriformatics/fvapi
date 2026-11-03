#!/usr/bin/env python3
"""Pinned replay fixture tools; faults change only this case's owned inputs/artifacts."""

import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

CASE = Path(os.environ["FVAPI_REPLAY_CASE"])
CONFIG = json.loads((CASE / "case.json").read_text())
TRACE = CASE / "events.jsonl"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def event(**values):
    values["time_ns"] = time.time_ns()
    with TRACE.open("a") as stream:
        stream.write(json.dumps(values) + "\n")


def owned(path):
    path = Path(path)
    scratch = Path((CASE / "run-dir").read_text().strip())
    if not (path.is_relative_to(CASE) or path.is_relative_to(scratch)):
        raise RuntimeError("fixture mutation outside its owned trees: " + str(path))
    return path


def change(path, operation="append"):
    path = owned(path)
    before = digest(path) if path.is_file() else None
    path.parent.mkdir(parents=True, exist_ok=True)
    if operation == "unlink":
        path.unlink()
    else:
        if path.exists():
            path.chmod(0o644)
        suffix = b"\n# fixture change\n" if operation == "python" else b"\n-- fixture change\n"
        path.write_bytes((path.read_bytes() if path.exists() else b"") + suffix)
    event(role="fault", operation=operation, path=str(path), before=before,
          after=digest(path) if path.is_file() else None)


def restore():
    kind = CONFIG.get("build_fault")
    if kind not in {"source-add-restore", "source-byte-restore", "challenge-add-restore"}:
        return
    if kind == "challenge-add-restore":
        path = Path((CASE / "run-dir").read_text().strip()) / "challenge/added-input.txt"
    else:
        path = CASE / "expected-source" / ("added-input.txt" if kind == "source-add-restore"
                                          else "FvapiSelf/Tiny.lean")
    if kind.endswith("add-restore"):
        path.unlink(missing_ok=True)
    else:
        path.write_bytes(bytes.fromhex(CONFIG["original_source_hex"]))
    event(role="restore", path=str(path))


def exporter():
    side = "solution" if Path.cwd() == CASE / "package" else "challenge"
    event(role="exporter", side=side, argv=sys.argv[1:])
    restore()
    mode = CONFIG.get("export", {}).get(side, "valid")
    if mode == "empty":
        event(role="exporter-result", side=side, rc=0, size=0)
        return 0
    result = subprocess.run([CONFIG["real_exporter"], *sys.argv[1:]], check=False)
    event(role="exporter-result", side=side, real_rc=result.returncode,
          rc=11 if mode == "nonzero" and result.returncode == 0 else result.returncode,
          size=os.fstat(1).st_size)
    if result.returncode:
        return result.returncode
    if mode == "unlink":
        change(os.readlink("/proc/self/fd/1"), "unlink")
    return 11 if mode == "nonzero" else 0


def comparator():
    argv = sys.argv[1:]
    challenge = Path(argv[argv.index("--challenge-from-export") + 1])
    solution = Path(argv[argv.index("--solution-from-export") + 1])
    event(role="comparator", argv=argv, challenge=digest(challenge), solution=digest(solution))
    mode = CONFIG.get("comparator", "valid")
    if mode == "timeout":
        while True:
            signal.pause()
    if mode == "error":
        print("controlled comparator error", file=sys.stderr)
        event(role="comparator-result", rc=2)
        return 2
    result = subprocess.run([CONFIG["real_lake"], *argv], check=False)
    event(role="comparator-result", rc=result.returncode)
    if result.returncode == 0 and mode == "change-solution":
        change(solution)
    return result.returncode


def kernel(name):
    configured = name in CONFIG.get("configured", [])
    config_path = Path(sys.argv[1]) if configured else None
    raw = config_path.read_bytes() if config_path is not None else None
    config = json.loads(raw) if raw is not None else None
    export = Path(config["export"] if config is not None else sys.argv[1])
    event(role="kernel", name=name, argv=sys.argv[1:], export=str(export), sha256=digest(export),
          config=config, config_path=str(config_path) if config_path is not None else None,
          config_sha256=hashlib.sha256(raw).hexdigest() if raw is not None else None)
    if name == CONFIG.get("fault_kernel", "con-ron"):
        action = CONFIG.get("action")
        scratch = Path((CASE / "run-dir").read_text().strip())
        if action in {"late-pin", "cause-pin"}:
            change(CASE / "bin/con-ron", "python")
        elif action == "late-io":
            export.parent.chmod(0o555)
            event(role="fault", operation="readonly-directory", path=str(export.parent))
        elif action == "solution-change":
            change(export)
        elif action == "solution-unlink":
            change(export, "unlink")
        elif action == "source-byte":
            change(CASE / "expected-source/FvapiSelf/Tiny.lean")
        elif action == "challenge-byte":
            change(scratch / "challenge/FvapiSelf/Tiny.lean")
        elif action == "challenge-missing":
            change(scratch / "challenge/FvapiSelf/Tiny.lean", "unlink")
        elif action == "challenge-unreadable":
            path = owned(scratch / "challenge/FvapiSelf/Tiny.lean")
            before = digest(path)
            path.chmod(0)
            event(role="fault", operation="unreadable", path=str(path), before=before)
        elif action == "source-add":
            change(CASE / "expected-source/added-input.txt")
        elif action == "challenge-add":
            change(scratch / "challenge/added-input.txt")
        elif action == "challenge-output":
            change(scratch / "challenge/.lake/build/fixture-output.bin")
        elif action == "challenge-package":
            change(scratch / "challenge/.lake/packages/fixture/Input.lean")
    mode = CONFIG.get("modes", {}).get(name, "accept")
    if mode == "missing-feature":
        print("no supported-feature diagnostic", file=sys.stderr)
        return 4
    return 0


def main():
    name = Path(sys.argv[0]).name
    if name == "exporter":
        return exporter()
    if name == "comparator":
        return comparator()
    return kernel(name)


if __name__ == "__main__":
    sys.exit(main())
