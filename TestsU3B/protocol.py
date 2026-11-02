#!/usr/bin/env python3
"""Plant adapter assertions, setup faults + signals; test fvamut's 0/1/2/3 classification."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fsync as F
import wire as W


def main():
    assert not W.exact({"n": True}, {"n": 1})
    assert W.exact({"n": [False, 1, None]}, {"n": [False, 1, None]})
    for invalid in (b'{"x":1,"x":1}', b'1.0', b'NaN', b'"\\ud800"', '{"x":1}'.encode("utf-16")):
        try:
            W.parse_output(invalid)
        except (ValueError, UnicodeError):
            pass
        else:
            raise AssertionError("driver output accepted outside its contract")
    with tempfile.TemporaryDirectory(prefix="u3b-protocol-") as directory:
        stub = Path(directory) / "driver"
        stub.write_text("#!/usr/bin/env python3\nimport json,os,signal\n"
                        "mode=os.environ.get('U3B_PROTOCOL','pass')\n"
                        "if mode=='crash': os.kill(os.getpid(), signal.SIGKILL)\n"
                        "print(json.dumps({'ok':{'query':{}}} if mode=='pass' else {'wrong':True}))\n")
        stub.chmod(0o700)
        case = W.Case("protocol", "T11", "request", "health", "", 200, b"", {"ok": {"query": {}}})
        result, *_ = W.execute(case, str(stub))
        assert result == 0
        os.environ["U3B_PROTOCOL"] = "fail"
        for count in (1, 2, 3):
            results = [W.execute(case, str(stub))[0] for _ in range(count)]
            assert max(results) == 1 and results.count(1) == count
        os.environ["U3B_PROTOCOL"] = "crash"
        assert W.execute(case, str(stub))[0] == 3
        fcase = F.Case("protocol", "T10", [("create", "file"), ("close",), ("drop",)], [])
        assert F.run_case(fcase, str(stub), ".lake/tests-u3b/interpose.so", None)[0] == 3
        os.environ["U3B_PROTOCOL"] = "fail"
        for count in (1, 2, 3):
            results = [F.run_case(fcase, str(stub), ".lake/tests-u3b/interpose.so", None)[0] for _ in range(count)]
            assert max(results) == 1 and results.count(1) == count
        missing = str(Path(directory) / "missing")
        assert F.run_case(fcase, missing, ".lake/tests-u3b/interpose.so", None)[0] == 2
        p = subprocess.run([sys.executable, "-I", "TestsU3B/wire.py", "--binary", missing,
                            "--case", "T11-health-request-minimal"], capture_output=True)
        assert p.returncode == 2
        p = subprocess.run(["bash", "TestsU3B/run.sh", "invalid"], capture_output=True)
        assert p.returncode == 2
    os.environ.pop("U3B_PROTOCOL", None)
    print("adapter-protocol: pass=0, 1/2/3 assertions=1, setup=2, signal=3 (F + W)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
