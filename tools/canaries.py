#!/usr/bin/env python3
"""Profile stage's small public canary cache; no verifier build needed on the Lean shard."""

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARENA_URL = ("https://github.com/leanprover/lean-kernel-arena/releases/download/round-2026-09/"
             "lean-arena-round-2026-09-tests.tar.gz")
ARENA_SHA = "98a69742b538296c5f413d0527dfeef8c4d1815fe64b12c8623cd33de63bee0d"
PRELUDE_URL = ("https://raw.githubusercontent.com/gersh/lean-kernel-bug/"
               "aa5157ea29fdf3e6d69566457e728ffb0b814966/exploit.export")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(url, path):
    subprocess.run(["curl", "-fsSL", "--retry", "3", "--connect-timeout", "30", "--max-time", "300",
                    "-o", str(path), url], check=True, timeout=1000)


def check(dest, pins):
    for field, filename in (("set_sha256", "set.tsv"), ("known_sha256", "known.tsv")):
        path = dest / filename
        if not path.is_file() or path.is_symlink() or sha(path) != pins[field]:
            raise ValueError(f"canaries.{field}: {filename} missing or sha256 differs")
    files = {}
    for line in (dest / "set.tsv").read_text().splitlines():
        if line and not line.startswith("#"):
            name, digest, kind = line.split("\t")
            if Path(name).is_absolute() or ".." in Path(name).parts or kind not in ("bad", "good"):
                raise ValueError(f"canaries.files: invalid set entry {name}")
            if name in files:
                raise ValueError(f"canaries.files: duplicate set entry {name}")
            files[name] = digest
    if not files or files != pins["files"]:
        raise ValueError("canaries.files != pinned canary set")
    for name, expected in files.items():
        path = dest / (name + ".ndjson")
        if not path.is_file() or path.is_symlink() or sha(path) != expected:
            raise ValueError(f"canaries.files.{name}: missing or sha256 differs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", type=Path, nargs="?", default=ROOT / "verify/profile.json")
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    pins = json.loads(args.profile.read_text())["canaries"]
    if pins["source_repo"] != "https://github.com/veriformatics/fva":
        raise ValueError("canaries.source_repo")
    key = hashlib.sha256(json.dumps(pins, sort_keys=True).encode()).hexdigest()
    cache = ROOT / ".tools/canaries"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        dest = args.check.resolve() if args.check else cache / key
        if not dest.exists() and not args.check:
            staging = Path(tempfile.mkdtemp(prefix=".fetch-", dir=cache))
            try:
                raw = "https://raw.githubusercontent.com/veriformatics/fva/" + pins["source_commit"]
                for filename in ("set.tsv", "known.tsv"):
                    fetch(raw + "/trust/canaries/" + filename, staging / filename)
                archive = staging / "arena.tar.gz"
                fetch(ARENA_URL, archive)
                if sha(archive) != ARENA_SHA:
                    raise ValueError("canary arena archive sha256 differs")
                (staging / "arena").mkdir()
                with tarfile.open(archive) as tar:
                    tar.extractall(staging / "arena", filter="data")
                archive.unlink()
                (staging / "prelude-15704").mkdir()
                fetch(PRELUDE_URL, staging / "prelude-15704/replaced-prelude.ndjson")
                check(staging, pins)
                staging.rename(dest)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        check(dest, pins)
    print(dest)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, tarfile.TarError) as exc:
        print(f"profile: {exc}", file=sys.stderr)
        sys.exit(1)
