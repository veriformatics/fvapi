"""Small host/profile fixtures; expected manifests follow the P2 byte rule independently."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".lake/build/bin/fvapi"
NAMES = ["leanchecker", "leanchecker-paranoid", "lean4lean", "nanoda", "con-leche", "con-ron"]
TARGET_SOURCE = """def primitiveTargets : M (Array Lean.Name) := pure #[
  ``Nat.add,
  ``Nat.sub
]
def builtinTargets : M (Array Lean.Name) := do
  /-
Quot.unquoted
  -/
  return #[``Quot]
"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relock(path, value):
    path.write_text(json.dumps(value) + "\n")
    encoded = subprocess.run(["jq", "-S", "-c", "del(.id)", str(path)],
                             capture_output=True, check=True).stdout
    assert encoded.endswith(b"\n")
    value["id"] = "sha256:" + hashlib.sha256(encoded[:-1]).hexdigest()
    path.write_text(json.dumps(value) + "\n")


def manifest(prefix):
    files = []
    for directory, _, names in os.walk(prefix, followlinks=False):
        for name in names:
            path = Path(directory) / name
            if stat.S_ISREG(path.lstat().st_mode):
                files.append(path.relative_to(prefix).as_posix())
    files.sort(key=lambda relative: relative.encode())
    raw = "".join(f"{digest(prefix / relative)}  ./{relative}\n" for relative in files).encode()
    return hashlib.sha256(raw).hexdigest()


def prepare(directory):
    prefix = directory / "prefix"
    (prefix / "bin").mkdir(parents=True)
    executable = prefix / "bin/fixture"
    executable.write_text("#!/bin/sh\nexit 0\n")
    executable.chmod(0o755)
    (prefix / "src").mkdir()
    source = prefix / "src/Check.lean"
    source.write_text(TARGET_SOURCE)
    (prefix / "data/nested").mkdir(parents=True)
    (prefix / "data/nested/bytes").write_bytes(b"fixture\x00\xff\n")
    (prefix / "link-file").symlink_to("bin/fixture")
    (prefix / "link-dir").symlink_to("data", target_is_directory=True)
    tree = directory / "tree"
    (tree / "a").mkdir(parents=True)
    (tree / "top").write_text("top\n")
    (tree / "a/b.txt").write_text("nested\n")
    (tree / "link-file").symlink_to("top")
    (tree / "link-dir").symlink_to("a", target_is_directory=True)
    pin = {"executable": "{lean_prefix}/bin/fixture", "sha256": digest(executable)}
    version = subprocess.run(["lean", "--version"], capture_output=True, text=True, check=True)
    toolchain = "leanprover/lean4:v" + version.stdout.split("version ", 1)[1].split(",", 1)[0]
    profile = {
        "version": 1, "id": "", "toolchain": toolchain,
        "runtime": {"sha256": manifest(prefix)}, "export_format": "fvapi.export.v1",
        "exporter": dict(pin),
        "comparator": dict(pin, source="src/Check.lean", source_sha256=digest(source),
                           targets=["Nat.add", "Nat.sub", "Quot"]),
        "canaries": {"source_repo": "synthetic", "source_commit": "a" * 40,
                     "set_sha256": "b" * 64, "known_sha256": "c" * 64, "files": {}},
        "policy_version": 1,
        "caps": {"export_ms": 1, "comparator_ms": 1, "memory_bytes": 1},
        "kernels": [dict(pin, name=name, args=["{export}"], timeout_ms=1,
                         status_map={"0": "accept"}) for name in NAMES],
    }
    path = directory / "profile.json"
    relock(path, profile)
    # Only --print-prefix changes. Version + all Lean execution keep the installed toolchain.
    lean = shutil.which("lean")
    if lean is None:
        raise FileNotFoundError("lean")
    shim = directory / "shim"
    shim.mkdir()
    wrapper = shim / "lean"
    wrapper.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                       f"if sys.argv[1:] == ['--print-prefix']: print({str(prefix)!r})\n"
                       f"else: os.execv({lean!r}, [{lean!r}, *sys.argv[1:]])\n")
    wrapper.chmod(0o755)
    env = dict(os.environ, PATH=str(shim) + ":" + os.environ["PATH"])
    return prefix, tree, path, profile, env
