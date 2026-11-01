#!/usr/bin/env -S python3 -I
"""Materialize fvapi's expected-source inputs + a replay inventory; print their identity."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="Use a new, empty output directory.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if any(destination.iterdir()):
        parser.error("The output directory is not empty. Use a new directory.")
    snapshot = destination / "expected-source"
    snapshot.mkdir()
    roots = {"lakefile.lean", "lake-manifest.json", "lean-toolchain", "Fvapi.lean", "Main.lean"}
    prefixes = ("Fvapi/", "FvapiSpec/", "FvapiSelf/", "c/", "vendor/")
    paths = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z"],
        capture_output=True, check=True,
    ).stdout.split(b"\x00")
    files = {}
    for raw in sorted(set(paths)):
        if not raw:
            continue
        relative = raw.decode()
        if (relative not in roots and relative != "tools/lean/Inventory.lean"
                and not relative.startswith(prefixes)):
            continue
        source = root / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError("non-regular snapshot input: " + relative)
        target = snapshot / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        files[relative] = hashlib.sha256(target.read_bytes()).hexdigest()
    manifest = json.dumps(
        {"version": 1, "files": files}, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode()
    (snapshot / "snapshot.json").write_bytes(manifest)
    identity = "sha256:" + hashlib.sha256(manifest).hexdigest()
    inventory = json.loads((root / "verify/claims.json").read_text())
    for claim in inventory["claims"]:
        claim["expected_snapshot"] = identity
    (destination / "claims.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(json.dumps({"snapshot": identity, "files": len(files), "claims": len(inventory["claims"])}))


if __name__ == "__main__":
    main()
