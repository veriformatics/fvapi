#!/usr/bin/env python3
"""Blind F policy oracle + syscall trace checks. All effects stay in fresh test directories."""
from __future__ import annotations

import argparse
import errno
import json
import os
from pathlib import Path
import random
import select
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from support import exact, parse_output


@dataclass
class Rule:
    op: str
    kind: str
    value: int = 0
    count: int = 1

    def text(self):
        return f"{self.op} {self.kind} {self.value} {self.count}\n"


@dataclass
class Case:
    id: str
    row: str
    operations: list[tuple]
    rules: list[Rule]
    rc: int = 0
    reuse: bool = False
    argv_override: list[str] | None = None
    stdin_override: bytes | None = None
    zfs: bool = False
    fixture: str | None = None


def ok(op):
    return {"op": op, "ok": True}


def failure(op, cause, number=None, secondary=None):
    value = {"op": op, "cause": cause}
    if number is not None:
        value["errno"] = number
    if secondary is not None:
        value["secondary"] = secondary
    return value


class Reference:
    def __init__(self, case: Case):
        self.rules = [Rule(r.op, r.kind, r.value, r.count) for r in case.rules]
        if case.fixture in ("existing", "symlink"):
            self.rules.append(Rule("create", "errno", errno.EEXIST))
        elif case.fixture == "regular-dir":
            self.rules.append(Rule("openDir", "errno", errno.ENOTDIR))
        self.slot = None
        self.closed = False
        self.next_owner = 0
        self.trace = []
        self.files = {"file": b"sentinel"} if case.fixture in ("existing", "symlink", "regular-dir") else {}

    def call(self, op, owner, count=0):
        rule = next((r for r in self.rules if r.op == op and r.count), Rule(op, "pass"))
        if rule in self.rules:
            rule.count -= 1
        number = rule.value if rule.kind == "errno" else 0
        result = -1 if number else min(rule.value, count) if rule.kind == "short" else 0 if rule.kind == "zero" else count if op == "write" else 0
        self.trace.append({"op": op, "owner": owner, "count": count, "ret": result, "errno": number})
        return result, number

    def retry(self, op, owner, count=0) -> tuple[int | None, dict[str, Any] | None]:
        interrupted = 0
        while True:
            result, number = self.call(op, owner, count)
            if number == errno.EINTR:
                if interrupted == 64:
                    return None, failure(op, "retryExhausted")
                interrupted += 1
            elif number:
                return None, failure(op, "errno", number)
            else:
                return result, None

    def close(self, op, owner):
        _, number = self.call(op, owner)
        return failure(op, "errno", number) if number else None

    def decide(self, operation):
        op, *args = operation
        error = None
        if op == "create":
            assert self.slot is None
            owner = self.next_owner
            self.next_owner += 1
            _, error = self.retry("create", owner)
            if error is None:
                self.slot = (owner, args[0])
                self.closed = False
                self.files[args[0]] = b""
        elif op in ("write", "sync", "close"):
            assert self.slot is not None
            owner, name = self.slot
            if self.closed:
                error = failure(op, "alreadyClosed")
            elif op == "close":
                self.closed = True
                error = self.close("close", owner)
            elif op == "sync":
                _, error = self.retry("sync", owner)
            else:
                remaining = args[0]
                offset = 0
                while remaining:
                    amount = min(remaining, 1 << 30)
                    result, error = self.retry("write", owner, amount)
                    if error is not None:
                        break
                    assert result is not None
                    if result == 0:
                        error = failure("write", "noProgress")
                        break
                    data = bytes((i % 251 for i in range(offset, offset + result)))
                    self.files[name] += data
                    offset += result
                    remaining -= result
        elif op == "drop":
            if self.slot and not self.closed:
                self.close("close", self.slot[0])
            self.slot = None
            self.closed = False
        elif op == "syncdir":
            owner = self.next_owner
            self.next_owner += 1
            _, error = self.retry("openDir", owner)
            if error is None:
                _, error = self.retry("syncDir", owner)
                close_error = self.close("closeDir", owner)
                if error is None:
                    error = close_error
                elif close_error:
                    error["secondary"] = {"op": "closeDir", "errno": close_error["errno"]}
        else:
            raise AssertionError(op)
        return {"op": op, "ok": False, "error": error} if error else ok(op)

    def run(self, operations):
        output = [self.decide(op) for op in operations]
        # Process exit drops the driver's slot too.
        if self.slot and not self.closed:
            self.close("close", self.slot[0])
        return output


def generate():
    out = []
    ops: list[tuple]

    def add(row, name, operations, rules=(), **kwargs):
        out.append(Case(f"{row}-{name}", row, operations, list(rules), **kwargs))

    bad = [[], ["write", "0"], ["sync"], ["close"], ["drop"], ["create"], ["syncdir"],
           ["create", "$file", "create", "$other"], ["create", "$file", "0777"],
           ["create", "$file", "8"], ["create", "$file", "-1"], ["create", "$file", "0o644"],
           ["create", "$file", "write", "-1"], ["create", "$file", "write", "+1"],
           ["create", "$file", "write", "1.0"], ["create", "$file", "write"],
           ["create", "$file", "write", "1"], ["create", "$file", "write", "18446744073709551616"],
           ["create", "$file", "write", "9" * 100], ["unexpected"], ["run"]]
    for i, argv in enumerate(bad):
        add("T1", f"usage-{i}", [], rc=2, argv_override=argv, stdin_override=b"")
    for mode in ("0", "00", "000", "1", "64", "644", "777"):
        add("T1", "mode-" + mode, [("create", "file", mode), ("close",), ("drop",)])
    add("T1", "leading-zero-count", [("create", "file"), ("write", 3), ("close",), ("drop",)],
        argv_override=["create", "$file", "write", "0003", "close", "drop"])
    for op in ("create", "write", "sync", "close", "openDir", "syncDir", "closeDir"):
        for number in (errno.EPERM, errno.EIO, errno.EACCES, errno.EINVAL, errno.ENOSPC, errno.EDQUOT):
            ops = [("syncdir",)] if op.endswith("Dir") else [("create", "file")]
            if op == "create":
                ops += [("create", "other"), ("close",), ("drop",)]
            elif op == "write":
                ops += [("write", 3), ("close",), ("drop",)]
            elif op == "sync":
                ops += [("write", 3), ("sync",), ("close",), ("drop",)]
            elif op == "close":
                ops += [("close",), ("drop",)]
            add("T2", f"{op}-errno-{number}", ops, [Rule(op, "errno", number)])
    for op in ("create", "write", "sync", "openDir", "syncDir"):
        for count in (1, 63, 64, 65, 66):
            ops = [("syncdir",)] if op.endswith("Dir") else [("create", "file")]
            if op == "create":
                if count >= 65:
                    ops.append(("create", "other"))
                ops += [("close",), ("drop",)]
            elif op == "write":
                ops += [("write", 3), ("close",), ("drop",)]
            elif op == "sync":
                ops += [("sync",), ("close",), ("drop",)]
            add("T3", f"{op}-eintr-{count}", ops, [Rule(op, "errno", errno.EINTR, count)])
    for op in ("close", "closeDir"):
        ops = [("syncdir",)] if op == "closeDir" else [("create", "file"), ("close",), ("drop",)]
        add("T3", f"{op}-eintr-once", ops, [Rule(op, "errno", errno.EINTR, 65)])
    add("T3", "progress-resets-budget", [("create", "file"), ("write", 3), ("close",), ("drop",)],
        [Rule("write", "errno", errno.EINTR, 64), Rule("write", "short", 1),
         Rule("write", "errno", errno.EINTR, 64), Rule("write", "short", 1),
         Rule("write", "errno", errno.EINTR, 64)])
    add("T3", "later-exhaustion-after-progress", [("create", "file"), ("write", 3), ("close",), ("drop",)],
        [Rule("write", "short", 1), Rule("write", "errno", errno.EINTR, 65)])
    add("T4", "empty-no-syscall", [("create", "file"), ("write", 0), ("close",), ("drop",)],
        [Rule("write", "errno", errno.EIO)])
    add("T4", "zero-is-no-progress", [("create", "file"), ("write", 3), ("close",), ("drop",)],
        [Rule("write", "zero")])
    add("T4", "zero-after-progress", [("create", "file"), ("write", 3), ("close",), ("drop",)],
        [Rule("write", "short", 1), Rule("write", "zero")])
    add("T5", "owned-description", [("create", "file"), ("write", 17), ("sync",), ("sync",), ("close",), ("drop",)])
    add("T5", "owned-writeback-error", [("create", "file"), ("write", 17), ("sync",), ("close",), ("drop",)],
        [Rule("sync", "errno", errno.EIO)])
    for primary in (errno.EIO, errno.ENOSPC):
        for secondary in (0, errno.EINTR, errno.EDQUOT):
            rules = [Rule("syncDir", "errno", primary)]
            if secondary:
                rules.append(Rule("closeDir", "errno", secondary))
            add("T6", f"syncdir-primary-{primary}-secondary-{secondary}", [("syncdir",)], rules)
    for secondary in (0, errno.EINTR, errno.EIO):
        rules = [Rule("syncDir", "errno", errno.EINTR, 65)]
        if secondary:
            rules.append(Rule("closeDir", "errno", secondary))
        add("T6", f"syncdir-exhaustion-secondary-{secondary}", [("syncdir",)], rules)
    add("T6", "failed-open-has-no-close", [("syncdir",)], [Rule("openDir", "errno", errno.ENOENT)])
    for number in (errno.EINTR, errno.EIO, errno.ENOSPC):
        add("T7", f"close-error-{number}-terminal", [("create", "file"), ("close",), ("close",),
            ("write", 3), ("write", 0), ("sync",), ("drop",)], [Rule("close", "errno", number)], reuse=True)
    add("T7", "successful-close-terminal", [("create", "file"), ("close",), ("close",), ("write", 3),
        ("write", 0), ("sync",), ("drop",)], reuse=True)
    for kind, rules in (("open", []), ("closed", []), ("finalizer-error", [Rule("close", "errno", errno.EIO)])):
        ops = [("create", "file"), ("write", 3)]
        if kind == "closed":
            ops.append(("close",))
        ops += [("drop",), ("create", "other"), ("close",), ("drop",)]
        add("T8", f"drop-{kind}", ops, rules)
    for zfs in (False, True):
        add("T10", "zfs" if zfs else "gate-filesystem", [("create", "file", "640"), ("write", 65537),
            ("sync",), ("close",), ("drop",), ("syncdir",)], zfs=zfs)
    for fixture in ("existing", "symlink"):
        add("T10", "create-" + fixture, [("create", "file"), ("create", "other"), ("close",), ("drop",)], fixture=fixture)
    add("T10", "directory-open-rejects-file", [("syncdir", "file")], fixture="regular-dir")
    add("T10", "directory-open-follows-directory-link", [("syncdir", "file")], fixture="directory-link")
    rng = random.Random(0xF5A3)
    for i in range(48):
        size = rng.randrange(1, 4097)
        rules = []
        remaining = size
        for _ in range(rng.randrange(1, 8)):
            rules.append(Rule("write", "errno", errno.EINTR, rng.randrange(1, 5)))
            take = rng.randrange(1, remaining + 1)
            rules.append(Rule("write", "short", take))
            remaining -= take
            if remaining == 0:
                break
        add("T4", f"generated-short-write-{i}", [("create", "file"), ("write", size), ("sync",), ("close",), ("drop",)], rules)
    assert len({c.id for c in out}) == len(out)
    return out


def environment(temp: Path, rules: list[Rule], preload: str, reuse=False):
    data = temp / "data"
    control = temp / "control"
    data.mkdir()
    control.mkdir()
    script = control / "script"
    script.write_text("".join(r.text() for r in rules))
    trace = control / "trace.jsonl"
    env = {**os.environ, "LD_PRELOAD": str(Path(preload).resolve()), "U3B_ROOT": str(data),
           "U3B_SCRIPT": str(script), "U3B_TRACE": str(trace), "U3B_CONTROL": str(control)}
    if reuse:
        env["U3B_REUSE"] = "1"
    else:
        env.pop("U3B_REUSE", None)
    return data, control, trace, env


def read_trace(path: Path):
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def compare_trace(expected, actual, operations):
    actual = [e for e in actual if e["phase"] == "return"]
    assert len(actual) == len(expected), f"trace count expected={len(expected)} observed={len(actual)}"
    owners = {}
    modes = iter(int(op[2], 8) if len(op) > 2 else 0o644 for op in operations if op[0] == "create")
    owner_modes = {}
    for i, (a, e) in enumerate(zip(actual, expected, strict=True)):
        assert a["op"] == e["op"], (i, a, e)
        assert not a["reused"], f"syscall on reused descriptor: {a}"
        assert a["count"] == e["count"], (i, a, e)
        assert a["errno"] == e["errno"], (i, a, e)
        if a["op"] in ("create", "openDir"):
            if a["ret"] >= 0:
                assert a["fd"] == a["ret"]
                owners[e["owner"]] = a["fd"]
            else:
                assert a["ret"] == e["ret"] == -1
            required = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC if a["op"] == "openDir" else os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW
            assert a["flags"] == required, ("open flags", a["flags"], required)
            if a["op"] == "create":
                if e["owner"] not in owner_modes:
                    owner_modes[e["owner"]] = next(modes)
                wanted = owner_modes[e["owner"]]
                assert a["mode"] == wanted, ("create mode", a["mode"], wanted)
        else:
            assert a["fd"] == owners[e["owner"]], ("description changed", a, owners)
            assert a["ret"] == e["ret"], (i, a, e)
        if a["op"] == "write":
            assert 0 < a["count"] <= 1 << 30


def driver_args(case: Case, binary: str, data: Path):
    stdin = b""
    argv = [binary, "dev", "fsync", "run"]
    for op in case.operations:
        if op[0] == "create":
            argv.extend(["create", str(data / op[1])])
            if len(op) > 2:
                argv.append(op[2])
        elif op[0] == "write":
            argv.extend(["write", str(op[1])])
            stdin += bytes(i % 251 for i in range(op[1]))
        elif op[0] == "syncdir":
            argv.extend(["syncdir", str(data / op[1]) if len(op) > 1 else str(data)])
        else:
            argv.append(op[0])
    if case.argv_override is not None:
        argv = [binary, "dev", "fsync", "run"] + [arg.replace("$file", str(data / "file")).replace("$other", str(data / "other")) for arg in case.argv_override]
    return argv, case.stdin_override if case.stdin_override is not None else stdin


def run_case(case: Case, binary: str, preload: str, zfs_root: str | None):
    parent = zfs_root if case.zfs else None
    if case.zfs and not parent:
        return 2, None, "ZFS test root unavailable (FVAPI_U3B_ZFS_ROOT)", None
    try:
        with tempfile.TemporaryDirectory(prefix="fvapi-u3b-", dir=parent) as directory:
            temp = Path(directory)
            data, _, trace, env = environment(temp, case.rules, preload, case.reuse)
            if case.fixture in ("existing", "regular-dir"):
                (data / "file").write_bytes(b"sentinel")
            elif case.fixture == "symlink":
                (data / "target").write_bytes(b"sentinel")
                (data / "file").symlink_to(data / "target")
            elif case.fixture == "directory-link":
                (data / "target").mkdir()
                (data / "file").symlink_to(data / "target", target_is_directory=True)
            argv, stdin = driver_args(case, binary, data)
            p = subprocess.run(argv, input=stdin, capture_output=True, env=env, timeout=20)
            observed = None
            if p.returncode < 0 or p.returncode >= 128:
                return 3, p.returncode, p.stderr.decode(errors="replace")[:200], None
            if p.returncode == 122:
                return 2, p.returncode, p.stderr.decode(errors="replace")[:200], None
            try:
                assert p.returncode == case.rc, f"rc expected={case.rc}, got={p.returncode}; {p.stderr.decode(errors='replace')[:120]}"
                if case.rc == 2:
                    # A separate positive control pins the supported driver, even for --case usage-only runs.
                    return 0, p.returncode, "", None
                observed = [parse_output(line) for line in p.stdout.splitlines()]
                ref = Reference(case)
                expected = ref.run(case.operations)
                assert exact(observed, expected), f"output expected={expected}, got={observed}"
                actual_trace = read_trace(trace)
                compare_trace(ref.trace, actual_trace, case.operations)
                for name, content in ref.files.items():
                    if not content:
                        assert (data / name).stat().st_size == 0, f"expected an empty file: {name}"
                        continue
                    disk = (data / name).read_bytes()
                    assert disk == content, f"on-disk bytes differ: {name}, expected={len(content)} got={len(disk)}"
                if case.row == "T10" and case.fixture is None:
                    assert stat.S_IMODE((data / "file").stat().st_mode) == 0o640 & ~current_umask()
                return 0, p.returncode, "", actual_trace
            except (AssertionError, ValueError) as error:
                return 1, p.returncode, str(error)[:1200], observed
    except subprocess.TimeoutExpired:
        return 3, -1, "timeout", None
    except OSError as error:
        return 2, None, str(error), None


def current_umask():
    value = os.umask(0)
    os.umask(value)
    return value


def selftest(preload: str, probe: str):
    controls = 0
    for variant in ("open", "__open_2", "open64", "openat"):
        for fault in (None, ("create", errno.EACCES), ("write", errno.ENOSPC), ("sync", errno.EIO), ("close", errno.EINTR), ("short", 1), ("zero", 0)):
            rules = [Rule(fault[0], "errno", fault[1])] if fault and fault[0] not in ("short", "zero") else [Rule("write", fault[0], fault[1])] if fault else []
            with tempfile.TemporaryDirectory(prefix="u3b-interposer-control-") as d:
                data, _, trace, env = environment(Path(d), rules, preload)
                path = data / "probe"
                if variant == "__open_2":
                    path.touch()
                p = subprocess.run([probe, variant, str(path)], capture_output=True, env=env, check=True)
                got = json.loads(p.stdout)
                events = read_trace(trace)
                assert events, (variant, fault, "no interception")
                if fault and fault[0] == "create":
                    assert got["open"] == -1 and got["open_errno"] == fault[1]
                    assert len(events) == 1
                else:
                    assert [x["op"] for x in events] == ["create", "write", "sync", "close"]
                    assert len({x["fd"] for x in events}) == 1
                    expected_write = 1 if fault and fault[0] == "short" else 0 if fault and fault[0] == "zero" else -1 if fault and fault[0] == "write" else 3
                    assert got["write"] == expected_write
                    if fault and fault[0] in ("write", "sync", "close"):
                        assert got[fault[0] + "_errno"] == fault[1]
                controls += 1
    for fault in (None,) + tuple((op, number) for op in ("openDir", "syncDir", "closeDir") for number in (errno.EIO, errno.EINTR)):
        rules = [Rule(fault[0], "errno", fault[1])] if fault else []
        with tempfile.TemporaryDirectory(prefix="u3b-directory-control-") as d:
            data, _, trace, env = environment(Path(d), rules, preload)
            p = subprocess.run([probe, "directory", str(data)], capture_output=True, env=env, check=True)
            got = parse_output(p.stdout)
            events = read_trace(trace)
            assert got["write"] == -2
            if fault and fault[0] == "openDir":
                assert [e["op"] for e in events] == ["openDir"]
                assert got["open"] == -1 and got["open_errno"] == fault[1]
            else:
                assert [e["op"] for e in events] == ["openDir", "syncDir", "closeDir"]
                assert len({e["fd"] for e in events}) == 1
                if fault:
                    assert got[("sync" if fault[0] == "syncDir" else "close") + "_errno"] == fault[1]
            controls += 1
    # Pure-policy checks pin the oracle's retry semantics before it judges fvapi.
    for n in (64, 65):
        c = Case("control", "T3", [("create", "file"), ("write", 3), ("close",)], [Rule("write", "errno", errno.EINTR, n)])
        ref = Reference(c)
        lines = ref.run(c.operations)
        assert lines[1]["ok"] == (n == 64)
        assert sum(e["op"] == "write" for e in ref.trace) == 65
    for case in generate():
        if case.rc == 0:
            Reference(case).run(case.operations)
    for kind in ("write", "sync"):
        result, _, detail, _ = race_case(kind, ".lake/tests-u3b/race-probe", preload)
        assert result == 0, ("guarded observer control", kind, detail)
        os.environ["U3B_PROBE_UNGUARDED"] = "1"
        try:
            result, _, detail, _ = race_case(kind, ".lake/tests-u3b/race-probe", preload)
            assert result == 1, ("unguarded observer must fire", kind, result, detail)
        finally:
            os.environ.pop("U3B_PROBE_UNGUARDED", None)
    print(f"fsync-oracle/interposer: {controls} real-libc positive/fault controls + 2 retry controls + 4 race-observer controls")


def race_case(kind: str, executable: str, preload: str):
    with tempfile.TemporaryDirectory(prefix="fvapi-u3b-task-") as d:
        temp = Path(d)
        op = "write" if kind == "write" else "sync"
        rules = [Rule(op, "block")] if kind in ("write", "sync") else [Rule("write", "ack", 0, 4)] if kind == "chunk" else []
        data, control, trace, env = environment(temp, rules, preload, reuse=True)
        fifo = control / "release"
        os.mkfifo(fifo)
        gate = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        p = subprocess.Popen([executable, kind, str(data / "file"), str(control)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            if kind in ("write", "sync"):
                deadline = time.monotonic() + 10
                # select is a bounded wait; close-started is written by the second real Lean Task.
                while not (control / "entered").exists() or not (control / "close-started").exists():
                    if p.poll() is not None or time.monotonic() > deadline:
                        raise AssertionError("Tasks did not reach blocked operation + concurrent close")
                    select.select([], [], [], 0.005)
                before = read_trace(trace)
                assert not any(e["op"] == "close" for e in before), "close bypassed an in-flight operation's guard"
                select.select([], [], [], 0.075)
                assert not (control / "close-done").exists(), "close finished while operation stayed blocked"
                assert not any(e["op"] == "close" for e in read_trace(trace)), "close syscall ran before release"
                os.write(gate, b"x")
            stdout, stderr = p.communicate(timeout=30)
            if p.returncode < 0 or p.returncode >= 128:
                return 3, p.returncode, stderr.decode(errors="replace")[:300], None
            assert p.returncode == 0, f"Tasks harness rc={p.returncode}: {stderr.decode(errors='replace')[:300]}"
            value = parse_output(stdout)
            assert exact(value, {"ok": True, "mode": kind}), value
            events = read_trace(trace)
            returns = [e for e in events if e["phase"] == "return"]
            assert not any(e["reused"] for e in events), "post-close operation reached reused fd"
            assert sum(e["op"] == "create" for e in returns) == 1
            assert sum(e["op"] == "close" for e in returns) == 1, "double/missing close"
            if kind in ("write", "sync"):
                assert [e["op"] for e in returns] == ["create", op, "close"], returns
                assert len({e["fd"] for e in returns}) == 1
            elif kind == "chunk":
                writes = [e for e in returns if e["op"] == "write"]
                assert [e["count"] for e in writes] == [1 << 30, 1]
                assert sum(e["ret"] for e in writes) == (1 << 30) + 1
            return 0, p.returncode, "", events
        except (AssertionError, ValueError) as error:
            return 1, p.returncode, str(error), read_trace(trace)
        except subprocess.TimeoutExpired:
            return 3, None, "Tasks timeout", read_trace(trace)
        finally:
            os.close(gate)
            if p.poll() is None:
                p.kill()
                p.communicate()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--records", default=".lake/tests-u3b/fsync.jsonl")
    parser.add_argument("--binary", default=os.environ.get("FVAPI_U3B_BIN", ".lake/build/bin/fvapi"))
    parser.add_argument("--preload", default=".lake/tests-u3b/interpose.so")
    parser.add_argument("--tasks", default=".lake/build/bin/fvapi-tests-u3b")
    parser.add_argument("--tasks-build-log", default=".lake/tests-u3b/tasks-build.log")
    args = parser.parse_args()
    if args.selftest:
        selftest(args.preload, ".lake/tests-u3b/probe")
        return 0
    cases = generate()
    task_names = ("write", "sync", "close-race", "lifecycle", "chunk")
    if args.list:
        for c in cases:
            print(c.id + "\t" + c.row)
        for name in task_names:
            print("T9-task-" + name + "\tT9")
        return 0
    if not Path(args.binary).is_file() or not Path(args.preload).is_file():
        print("setup: missing fvapi binary/interposer", file=sys.stderr)
        return 2
    if args.case:
        cases = [c for c in cases if c.id == args.case]
        task_names = tuple(n for n in task_names if "T9-task-" + n == args.case)
        if not cases and not task_names:
            return 2
    records = Path(args.records)
    records.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    highest = 0
    totals = {}
    # The ZFS case is opt-in integration evidence outside the portable gate (U3 F5): it runs
    # only when the caller names a writable ZFS scratch root.
    zfs_root = os.environ.get("FVAPI_U3B_ZFS_ROOT")
    if not zfs_root:
        cases = [case for case in cases if not case.zfs]
    if zfs_root:
        filesystem = subprocess.run(["stat", "-f", "-c", "%T", zfs_root], capture_output=True, text=True)
        if filesystem.returncode != 0 or filesystem.stdout.strip() != "zfs":
            zfs_root = None
    with tempfile.TemporaryDirectory(prefix="u3b-driver-control-") as d:
        data, _, _, env = environment(Path(d), [], args.preload)
        control = subprocess.run([args.binary, "dev", "fsync", "run", "create", str(data / "positive"), "close", "drop"],
                                 input=b"", capture_output=True, env=env, timeout=20)
        try:
            supported = control.returncode == 0 and exact([parse_output(line) for line in control.stdout.splitlines()], [ok("create"), ok("close"), ok("drop")])
        except ValueError:
            supported = False
    with records.open("w") as out:
        for case in cases:
            before = time.monotonic()
            result, rc, diagnostic, observed = run_case(case, args.binary, args.preload, zfs_root)
            if case.rc == 2 and not supported:
                result = max(result, 1)
                diagnostic = "supported-mode positive control failed"
            highest = max(highest, result)
            stats = totals.setdefault(case.row, [0, 0])
            stats[0] += 1
            stats[1] += result != 0
            out.write(json.dumps({"id": case.id, "row": case.row,
                "command": "python3 -I TestsU3B/fsync.py --case " + shlex.quote(case.id),
                "driver_rc": rc, "result": result, "diagnostic": diagnostic, "observed": observed,
                "wall_ms": round((time.monotonic() - before) * 1000, 2)}, separators=(",", ":")) + "\n")
        if task_names:
            before = time.monotonic()
            build = subprocess.run(["lake", "build", "fvapi-tests-u3b"], capture_output=True)
            Path(args.tasks_build_log).write_bytes(build.stdout + build.stderr)
            for name in task_names:
                if build.returncode:
                    result, rc, diagnostic, observed = 2, build.returncode, "public API Tasks target did not build; " + args.tasks_build_log, None
                else:
                    result, rc, diagnostic, observed = race_case(name, args.tasks, args.preload)
                highest = max(highest, result)
                stats = totals.setdefault("T9", [0, 0])
                stats[0] += 1
                stats[1] += result != 0
                out.write(json.dumps({"id": "T9-task-" + name, "row": "T9",
                    "command": "python3 -I TestsU3B/fsync.py --case T9-task-" + name,
                    "driver_rc": rc, "result": result, "diagnostic": diagnostic, "observed": observed,
                    "wall_ms": round((time.monotonic() - before) * 1000, 2)}, separators=(",", ":")) + "\n")
    for row, (total, failed) in sorted(totals.items(), key=lambda x: int(x[0][1:])):
        print(f"{row}: {total} cases, {failed} failed")
    print(f"fsync: rc={highest}; wall={time.monotonic() - start:.3f}s; records={records}")
    return highest


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, ValueError) as error:
        print(f"setup: {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2) from error
