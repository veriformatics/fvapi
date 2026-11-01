#!/usr/bin/env python3
"""P5 pin maintenance: raw public git blobs; replay and audits decide whether a bump is valid."""

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    if len(sys.argv) > 2:
        raise ValueError("usage: tools/pin-capsule.sh [COMMIT]")
    lock_path, profile_path = ROOT / "verify/capsule.lock", ROOT / "verify/profile.json"
    lock, profile = json.loads(lock_path.read_text()), json.loads(profile_path.read_text())
    commit = sys.argv[1] if len(sys.argv) == 2 else lock["commit"]
    if not re.fullmatch("[0-9a-f]{40}", commit):
        raise ValueError("COMMIT = 40 lowercase hex")
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "source"
        for args in (["git", "init", "-q", str(repo)],
                     ["git", "-C", str(repo), "remote", "add", "origin", lock["upstream"]],
                     ["git", "-C", str(repo), "fetch", "-q", "--depth", "1", "origin", commit]):
            subprocess.run(args, check=True, timeout=300)

        def blob(name):
            return subprocess.check_output(["git", "-C", str(repo), "show", f"{commit}:{name}"],
                                           timeout=60)

        def sha(data):
            return hashlib.sha256(data).hexdigest()

        chain = blob("lean-toolchain")
        if chain.decode().strip() != (ROOT / "lean-toolchain").read_text().strip():
            raise ValueError("capsule toolchain differs; update the runtime profile together")
        lock.update(commit=commit, source_tree=subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", f"{commit}^{{tree}}"], timeout=60).decode().strip(),
            toolchain=chain.decode().strip(), toolchain_sha256=sha(chain),
            runtime_sha256=profile["runtime"]["sha256"],
            manifest_sha256=sha(blob("lake-manifest.json")),
            canary_set_sha256=sha(blob("trust/canaries/set.tsv")),
            canary_known_sha256=sha(blob("trust/canaries/known.tsv")))
        files = {}
        for line in blob("trust/canaries/set.tsv").decode().splitlines():
            if line and not line.startswith("#"):
                name, digest, _kind = line.split("\t")
                if name in files:
                    raise ValueError(f"duplicate canary {name}")
                files[name] = digest
        profile["canaries"] = {"source_repo": lock["upstream"], "source_commit": commit,
                               "set_sha256": lock["canary_set_sha256"],
                               "known_sha256": lock["canary_known_sha256"], "files": files}
        # jq owns the profile's canonical-byte rule; native JSON formatting is not its identity.
        canonical = subprocess.check_output(["jq", "-S", "-c", "del(.id)"],
                                            input=json.dumps(profile).encode(), timeout=30)
        profile["id"] = "sha256:" + sha(canonical.removesuffix(b"\n"))
        outputs = ((lock_path, json.dumps(lock, indent=2) + "\n"),
                   (profile_path, json.dumps(profile, indent=2) + "\n"))
        if len(sys.argv) == 1:
            for path, content in outputs:
                if path.read_bytes() != content.encode():
                    raise ValueError(f"{path.name}: relocking is not byte-identical")
        else:
            for path, content in outputs:
                path.write_text(content)
        print(f"pin-capsule: {commit}, {len(files)} canaries, {profile['id']}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print(f"pin-capsule: {exc}", file=sys.stderr)
        sys.exit(1)
