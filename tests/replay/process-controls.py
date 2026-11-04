#!/usr/bin/env python3
"""Exact delegated deadlines, authentic pgid2, and a held-orphan reaping handshake."""

import argparse
import ctypes
from decimal import Decimal
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / ".lake/build/bin/fvapi-tests-replay"


class SetupError(RuntimeError):
    pass


def need(ok, message):
    if not ok:
        raise AssertionError(message)


def run(directory, milliseconds, command, args=(), env=None, prefix=(), mode="process"):
    argv = [*prefix, str(HARNESS), mode, str(directory), str(milliseconds), command, *args]
    result = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True)
    if result.returncode:
        raise SetupError(result.stdout + result.stderr)
    try:
        value = json.loads(result.stdout)
    except ValueError as error:
        raise SetupError("malformed IO harness envelope: " + result.stdout + result.stderr) from error
    if not isinstance(value, dict):
        raise SetupError("IO harness object")
    return value


def deadline(root):
    bin_dir = root / "bin"
    bin_dir.mkdir()
    trace = root / "timeouts.jsonl"
    wrapper = bin_dir / "timeout"
    wrapper.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
with Path(os.environ["DEADLINE_TRACE"]).open("a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")
os.execv("/usr/bin/timeout",["timeout",*sys.argv[1:]])
''')
    wrapper.chmod(0o755)
    env = dict(os.environ, PATH=str(bin_dir) + ":" + os.environ["PATH"], DEADLINE_TRACE=str(trace))
    marker = root / "real-command"
    command = root / "quick"
    command.write_text("#!/bin/sh\nprintf run >>\"$DEADLINE_MARKER\"\n")
    command.chmod(0o755)
    env["DEADLINE_MARKER"] = str(marker)
    for milliseconds in (1, 1000, 1010):
        directory = root / str(milliseconds)
        directory.mkdir()
        before = marker.read_bytes() if marker.exists() else b""
        value = run(directory, milliseconds, str(command), env=env)
        rows = [json.loads(line) for line in trace.read_text().splitlines()]
        args = rows[-1]
        need("prlimit" in args, "real timeout received the resource-capped command")
        duration = args[args.index("prlimit") - 1]
        need(duration.endswith("s") and Decimal(duration[:-1]) == Decimal(milliseconds) / 1000,
             f"deadline {milliseconds}ms: delegated {duration}, expected {milliseconds}/1000 seconds")
        if milliseconds != 1:
            need(value.get("rc") == 0 and value.get("timed_out") is False and
                 marker.read_bytes() != before, "real quick command ran under unchanged GNU timeout")
        # 1ms is a legal budget, not a guarantee that prlimit+bash startup finishes within it.
        print(f"PASS replay-process: deadline {milliseconds}ms = {duration}")


def pgid2(root):
    prefix = ["sudo", "-n", "unshare", "--pid", "--fork", "--mount-proc", "--", "sh", "-c",
              'printf 100 > /proc/sys/kernel/ns_last_pid; exec "$@"', "pid2-fixture",
              "env", "LEAN_NUM_THREADS=1", "LEAN_IMPORT_WORKERS=1"]
    value = run(root, 1000, "/usr/bin/true", prefix=prefix, mode="pid2")
    if value.get("pgid") != "2":
        raise SetupError("PID namespace not qualified: first supervisor pgid=" + repr(value.get("pgid")))
    need(value.get("rc") == 0 and value.get("timed_out") is False and
         "cleanup failed" not in value.get("stderr", ""), "authentic pgid2 exits successfully + is gone")
    print("PASS replay-process: authentic first child pgid2, rc0, no cleanup error")


def exists_group(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def reap_wait(root):
    libc = ctypes.CDLL(None, use_errno=True)
    previous = ctypes.c_int()
    if libc.prctl(37, ctypes.byref(previous), 0, 0, 0) or libc.prctl(36, 1, 0, 0, 0):
        raise SetupError("subreaper qualification")
    pid = None
    process = None
    try:
        bin_dir = root / "bin"
        bin_dir.mkdir()
        kill = bin_dir / "kill"
        kill.write_text('''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
result=subprocess.run(["/usr/bin/kill",*sys.argv[1:]],capture_output=True)
if sys.argv[1]=="-0":
 with Path(os.environ["REAP_PROBES"]).open("a") as f:
  f.write(json.dumps({"argv":sys.argv[1:],"rc":result.returncode})+"\\n")
sys.stdout.buffer.write(result.stdout);sys.stderr.buffer.write(result.stderr)
raise SystemExit(result.returncode)
''')
        kill.chmod(0o755)
        child_file, probes = root / "child.pid", root / "probes.jsonl"
        leader = root / "leader.py"
        # The pid is published by rename: a reader never sees the created-but-unwritten file.
        leader.write_text('''import os,signal,sys
from pathlib import Path
pid=os.fork()
if pid==0:
 fd=os.open("/dev/null",os.O_RDWR);os.dup2(fd,1);os.dup2(fd,2);os.close(fd)
 while True: signal.pause()
Path(sys.argv[1]+".tmp").write_text(str(pid))
os.replace(sys.argv[1]+".tmp",sys.argv[1])
''')
        env = dict(os.environ, PATH=str(bin_dir) + ":" + os.environ["PATH"], REAP_PROBES=str(probes))
        process = subprocess.Popen([str(HARNESS), "process", str(root), "2000", "python3", "-I",
                                    str(leader), str(child_file)], cwd=ROOT, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        end = time.monotonic() + 15
        released = False
        while time.monotonic() < end:
            if pid is None and not released and child_file.exists():
                # Empty = created, not yet written: a writer without the rename still races here.
                text = child_file.read_text()
                pid = int(text) if text else None
            observed = [json.loads(line) for line in probes.read_text().splitlines()] if probes.exists() else []
            if pid is not None and not released and any(r["rc"] == 0 for r in observed):
                # The first real kill(-pgid,0) has observed the held child. Only now may it be reaped.
                os.waitpid(pid, 0)
                released = True
                pid = None
            if process.poll() is not None:
                break
            time.sleep(0.001)
        if process.poll() is None:
            raise SetupError("reaper handshake did not terminate")
        stdout, stderr = process.communicate()
        if process.returncode:
            raise SetupError(stdout + stderr)
        value = json.loads(stdout)
        group = int(value["pgid"])
        live = exists_group(group)
        need(released and not live and value.get("rc") == 0 and value.get("timed_out") is False,
             f"reaper waits for observed liveness + actual reap before return (released={released}, group_live={live})")
        print("PASS replay-process: real -0 observes held orphan; release/reap precedes return")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        if pid is not None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass
        libc.prctl(36, previous.value, 0, 0, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=("all", "deadline", "pgid2", "reap-wait"))
    parser.add_argument("--prebuilt", action="store_true")
    args = parser.parse_args()
    if not args.prebuilt:
        result = subprocess.run(["lake", "build", "fvapi-tests-replay"], cwd=ROOT,
                                capture_output=True, text=True)
        if result.returncode:
            raise SetupError(result.stdout + result.stderr)
    cases = {"deadline": deadline, "pgid2": pgid2, "reap-wait": reap_wait}
    selected = cases if args.case == "all" else {args.case: cases[args.case]}
    failures = 0
    with tempfile.TemporaryDirectory(prefix="process-ruled-", dir=ROOT / ".lake") as temporary:
        for name, function in selected.items():
            directory = Path(temporary) / name
            directory.mkdir()
            try:
                function(directory)
            except AssertionError as error:
                print(f"assertion: replay-process: {name}: {error}", file=sys.stderr)
                failures += 1
    print(f"replay-process: {len(selected)} families, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"setup: replay-process: {error}", file=sys.stderr)
        sys.exit(2)
