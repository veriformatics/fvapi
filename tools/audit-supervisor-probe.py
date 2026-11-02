#!/usr/bin/env python3
"""P6 resource-check controls use the production supervisor with small test-only budgets."""

import importlib.util
import sys
import tempfile
from pathlib import Path
from typing import Any, Protocol, cast


class Supervisor(Protocol):
    AGGREGATE_MEMORY_BYTES: int
    WHOLE_TIMEOUT_SECONDS: int

    def invoke(self, argv: list[str], out: Path, err: Path) -> dict[str, Any]: ...


root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("self_audit", root / "tools/self-audit.py")
if spec is None or spec.loader is None:
    raise RuntimeError("self-audit loader unavailable")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
audit = cast(Supervisor, module)
kind = sys.argv[1]
planted = (Path.cwd() / ".planted").exists()
audit.AGGREGATE_MEMORY_BYTES = 64 * 1024**2
audit.WHOLE_TIMEOUT_SECONDS = 1
code = "pass"
if planted:
    code = "import time; time.sleep(5)" if kind == "timeout" else \
        "import time; data=bytearray(128*1024**2); time.sleep(5)"
with tempfile.TemporaryDirectory() as tmp:
    result = audit.invoke([sys.executable, "-I", "-c", code], Path(tmp) / "out", Path(tmp) / "err")
    if result["cause"]:
        print(result["cause"])
        sys.exit(1)
    sys.exit(0 if result["rc"] == 0 else 2)
