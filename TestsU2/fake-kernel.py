#!/usr/bin/env -S python3 -I
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

role = Path(sys.argv[0]).name
if role.startswith("exporter"):
    mode, name, arguments = "export-fail", "exporter", sys.argv[1:]
elif role.startswith("comparator"):
    mode, name, arguments = "comparator-error", "comparator", sys.argv[1:]
else:
    mode, name, arguments = sys.argv[1], sys.argv[2], sys.argv[3:]
inputs = []
for argument in arguments:
    path = Path(argument)
    if path.is_file():
        inputs.append({"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
child = None
if mode == "timeout":
    child = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(120)", "u2-owned-child:" + str(os.getpid())])
record = {"name": name, "mode": mode, "pid": os.getpid(), "argv": arguments, "inputs": inputs}
if child is not None:
    record["child_pid"] = child.pid
with Path(os.environ["U2_TEST_TRACE"]).open("a") as trace:
    trace.write(json.dumps(record, sort_keys=True) + "\n")
    trace.flush()
# Real kernels have exit-code/stderr adapters, not a JSON stdout protocol.
print("opaque non-JSON kernel output", flush=True)
if mode == "accept":
    sys.exit(0)
if mode == "accept-with-decline":
    print("UNSUPPORTED:x", file=sys.stderr, flush=True)
    sys.exit(0)
if mode in {"reject", "reject-with-decline"}:
    print("UNSUPPORTED:x" if mode.endswith("decline") else "rejected", file=sys.stderr, flush=True)
    sys.exit(3)
if mode.startswith("decline-"):
    feature = {"decline-x": "x", "decline-empty": "", "decline-space": " "}.get(mode)
    print("UNSUPPORTED:" + feature if feature is not None else "no feature mapping", file=sys.stderr, flush=True)
    sys.exit(4)
if mode == "unmapped":
    print("UNSUPPORTED:x", file=sys.stderr, flush=True)
    sys.exit(9)
if mode == "signal":
    os.kill(os.getpid(), signal.SIGTERM)
if mode == "timeout":
    while True:
        time.sleep(60)
if mode == "comparator-error":
    print("fixture comparator parse/setup failure", file=sys.stderr, flush=True)
    sys.exit(2)
if mode == "export-fail":
    print("fixture export failure", file=sys.stderr, flush=True)
    sys.exit(11)
raise SystemExit("bad fixture mode: " + mode)
