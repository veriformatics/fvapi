#!/usr/bin/env python3
"""P5 capsule acquisition + byte revalidation. Public inputs alone; stdout = capsule path."""

import argparse
import fcntl
import hashlib
import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fail(message):
    raise ValueError(message)


def run(args, cwd=None, timeout=3600, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=True, timeout=timeout,
                          stdout=sys.stderr, stderr=sys.stderr)


def text(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, timeout=120).decode().strip()


def runtime(lock):
    prefix = Path(text(["lean", "--print-prefix"]))
    # Same relative-path manifest rule as the profile; stream instead of holding 3 GB in RAM.
    proc = subprocess.run(["bash", "-o", "pipefail", "-c",
                           "find . -type f -print0 | LC_ALL=C sort -z | "
                           "xargs -0 sha256sum | sha256sum"], cwd=prefix,
                          capture_output=True, check=True, timeout=300)
    got = proc.stdout.decode().split()[0]
    if got != lock["runtime_sha256"]:
        fail(f"runtime manifest {got} != capsule.lock runtime_sha256")
    return got


def inputs():
    lock_path = ROOT / "verify/capsule.lock"
    lock = json.loads(lock_path.read_text())
    if lock["version"] != 1 or lock["upstream"] != "https://github.com/veriformatics/fva":
        fail("capsule.lock version/upstream")
    if len(lock["commit"]) != 40 or any(c not in "0123456789abcdef" for c in lock["commit"]):
        fail("capsule.lock commit = 40 lowercase hex")
    if (ROOT / "lean-toolchain").read_text().strip() != lock["toolchain"]:
        fail("capsule.lock toolchain != lean-toolchain")
    profile = json.loads((ROOT / "verify/profile.json").read_text())
    if profile["runtime"]["sha256"] != lock["runtime_sha256"]:
        fail("capsule.lock runtime_sha256 != profile.runtime")
    pins = profile["canaries"]
    for left, right in (("upstream", "source_repo"), ("commit", "source_commit"),
                        ("canary_set_sha256", "set_sha256"),
                        ("canary_known_sha256", "known_sha256")):
        if lock[left] != pins[right]:
            fail(f"capsule.lock {left} != profile.canaries.{right}")
    identity = {"lock_sha256": sha(lock_path), "runtime_sha256": runtime(lock),
                "manifest_sha256": lock["manifest_sha256"],
                "platform": f"{platform.system()}-{platform.machine()}",
                "builder_sha256": sha(Path(__file__).resolve())}
    return lock, profile, identity, digest(canonical(identity))


def clean_source(repo, revision, label, tree=None):
    if text(["git", "rev-parse", "HEAD"], repo) != revision:
        fail(f"{label}: HEAD != pinned revision")
    detached = subprocess.run(["git", "symbolic-ref", "-q", "HEAD"], cwd=repo,
                              capture_output=True, timeout=30)
    if detached.returncode != 1:
        fail(f"{label}: checkout is not detached")
    if tree and text(["git", "rev-parse", "HEAD^{tree}"], repo) != tree:
        fail(f"{label}: source tree != capsule.lock")
    # Raw blobs, not mtime/index shortcuts; this also detects changed ignored tracked files.
    listing = subprocess.check_output(["git", "ls-tree", "-rz", "--full-tree", revision],
                                     cwd=repo, timeout=60)
    manifest = []
    for entry in listing.split(b"\0"):
        if not entry:
            continue
        header, name = entry.split(b"\t", 1)
        mode, kind, oid = header.decode().split()
        rel = os.fsdecode(name)
        path = repo / rel
        if kind != "blob" or mode not in ("100644", "100755", "120000"):
            fail(f"{label}: unsupported source entry {rel}")
        if mode == "120000":
            if not path.is_symlink():
                fail(f"{label}: source {rel} missing symlink")
            data = os.fsencode(os.readlink(path))
        else:
            if not path.is_file() or path.is_symlink():
                fail(f"{label}: source {rel} missing regular file")
            data = path.read_bytes()
            if bool(path.stat().st_mode & stat.S_IXUSR) != (mode == "100755"):
                fail(f"{label}: source {rel} executable mode differs")
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if blob != oid:
            fail(f"{label}: source {rel} differs from pinned bytes")
        manifest.append([rel, digest(data)])
    status = text(["git", "status", "--porcelain", "--untracked-files=all"], repo)
    if status:
        fail(f"{label}: source not clean: {status[:400]}")
    return {"revision": revision, "files": len(manifest),
            "source_sha256": digest(canonical(manifest)), "clean": True}


def canaries(repo, lock, profile):
    set_file = repo / "trust/canaries/set.tsv"
    known = repo / "trust/canaries/known.tsv"
    for path, want in ((set_file, lock["canary_set_sha256"]),
                       (known, lock["canary_known_sha256"])):
        if not path.is_file() or sha(path) != want:
            fail(f"canary {path.name}: missing or sha256 differs")
    files = {}
    for line in set_file.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        name, want, kind = line.split("\t")
        if name in files or kind not in ("bad", "good") or ".." in Path(name).parts:
            fail(f"canary set entry {name}")
        path = repo / ".cache/canaries" / (name + ".ndjson")
        if not path.is_file() or path.is_symlink() or sha(path) != want:
            fail(f"canary {name}: missing or sha256 differs")
        files[name] = want
    if not files or files != profile["canaries"]["files"]:
        fail("canaries.files != pinned canary set")
    return files


def facts(dest, lock, profile):
    repo = dest / "fva"
    if not repo.is_dir():
        fail("partial capsule: fva checkout missing")
    source = clean_source(repo, lock["commit"], "fva", lock["source_tree"])
    for field, rel in (("toolchain_sha256", "lean-toolchain"),
                       ("manifest_sha256", "lake-manifest.json")):
        if sha(repo / rel) != lock[field]:
            fail(f"{rel}: sha256 != capsule.lock {field}")
    deps = {}
    manifest = json.loads((repo / "lake-manifest.json").read_text())
    for package in manifest["packages"]:
        deps[package["name"]] = clean_source(repo / ".lake/packages" / package["name"],
                                               package["rev"], package["name"])
    bins = {}
    for name in ("fva", "fvamut"):
        path = repo / ".lake/build/bin" / name
        if not path.is_file() or path.is_symlink() or not os.access(path, os.X_OK):
            fail(f"tool {name}: missing executable")
        bins[name] = sha(path)
    runners = {str(p.relative_to(repo)): sha(p)
               for p in sorted((repo / "FVATest/Mutate").glob("*.lean"))}
    if not runners:
        fail("runner sources missing")
    return {"source": source, "dependencies": deps, "binaries": bins,
            "runner_sources": runners, "canaries": canaries(repo, lock, profile)}


def verify(dest, lock, profile, identity, key):
    record_file = dest / "capsule.json"
    if not record_file.is_file():
        fail("partial capsule: capsule.json missing")
    record = json.loads(record_file.read_text())
    if record.get("version") != 1 or record.get("identity") != identity or record.get("key") != key:
        fail("capsule.json identity/key differs")
    if record.get("pre_clean") is not True or record.get("post_clean") is not True:
        fail("capsule.json pre/post cleanliness")
    got = facts(dest, lock, profile)
    for field in ("source", "dependencies", "binaries", "runner_sources", "canaries"):
        if got[field] != record.get(field):
            fail(f"capsule {field}: bytes differ from published identities")
    return record


def build(dest, lock, profile, identity, key):
    repo = dest / "fva"
    writable = dest / "writable"
    writable.mkdir()
    run(["git", "init", "-q", str(repo)])
    run(["git", "-C", str(repo), "remote", "add", "origin", lock["upstream"]])
    run(["git", "-C", str(repo), "fetch", "-q", "--depth", "1", "origin", lock["commit"]])
    run(["git", "-C", str(repo), "-c", "advice.detachedHead=false", "checkout", "-q",
         "--detach", lock["commit"]])
    clean_source(repo, lock["commit"], "fva", lock["source_tree"])
    # Toolchain/manifest pins are checked before executing any source from the fresh clone.
    if sha(repo / "lean-toolchain") != lock["toolchain_sha256"] or \
            sha(repo / "lake-manifest.json") != lock["manifest_sha256"]:
        fail("fresh checkout toolchain/manifest differs from capsule.lock")
    (repo / ".cache").mkdir()
    env = dict(os.environ, MATHLIB_CACHE_DIR=str(writable / "mathlib-cache"))
    started = time.monotonic()
    run(["lake", "exe", "cache", "get"], repo, env=env)
    run(["lake", "build", "fva", "fvamut"], repo, env=env)
    # The pinned upstream fetch verifies archive + prelude bytes and never repins the TSV.
    run(["bash", "scripts/fetch-canaries"], repo, timeout=900)
    (writable / "canary-results").mkdir()
    (repo / ".cache/canaries/results").symlink_to(
        Path("../../../writable/canary-results"), target_is_directory=True)
    measured = facts(dest, lock, profile)
    record = {"version": 1, "identity": identity, "key": key, "pre_clean": True,
              "post_clean": True, "toolchain": lock["toolchain"],
              "build_wall_s": round(time.monotonic() - started, 3), **measured}
    (dest / "capsule.json").write_text(json.dumps(record, indent=2) + "\n")
    verify(dest, lock, profile, identity, key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", type=Path, help="revalidate only; changed/partial cache fails")
    parser.add_argument("--key", action="store_true", help="print the verified cache key")
    args = parser.parse_args()
    lock, profile, identity, key = inputs()
    if args.key:
        print(key)
        return
    cache = Path(os.environ.get("FVAPI_CAPSULE_ROOT", str(Path.home() / "gate/capsules")))
    cache.mkdir(parents=True, exist_ok=True)
    # Callers hold this lock shared while running capsule tools. Revalidation only reads, so it
    # shares too (an exclusive revalidation would wait out every running campaign); publishing a
    # build takes it exclusive and re-checks, since flock's upgrade is not atomic.
    with (cache / ".lock").open("a") as stream:
        dest = args.check.resolve() if args.check else cache.resolve() / key
        fcntl.flock(stream, fcntl.LOCK_SH)
        if not (args.check or dest.exists()):
            fcntl.flock(stream, fcntl.LOCK_EX)
        if args.check or dest.exists():
            verify(dest, lock, profile, identity, key)
            print(f"capsule: revalidated {key}", file=sys.stderr)
        else:
            staging = Path(tempfile.mkdtemp(prefix=".building-", dir=cache))
            try:
                build(staging, lock, profile, identity, key)
                staging.rename(dest)
                print(f"capsule: published {key}", file=sys.stderr)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        print(dest)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print(f"capsule: {exc}", file=sys.stderr)
        sys.exit(1)
