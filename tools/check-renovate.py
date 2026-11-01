#!/usr/bin/env python3
"""Renovate's custom managers extract every pin they own (gate stage `renovate`).

Each customManager's regex is applied to its files the way Renovate's regex manager does (every
matchString over the whole file); the result must equal an independent parse of the same file:
lean-toolchain, tools/tools.lock and lake-manifest.json, plus a synthetic two-package Lake
manifest (tests/renovate/lake-manifest.json), since the real manifest lists no package. Each
tools.lock line's URL must name its own version (a half-applied Renovate bump = re-pin with
tools/pin-tool.sh). Renovate compiles with RE2; the patterns here use no RE2-incompatible syntax
(the config validator in .claude/rules/gate.md checks that). Usage: python3 -I tools/check-renovate.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def py_pattern(js: str) -> str:
    """Renovate named groups (?<name>…) → Python (?P<name>…)."""
    return re.sub(r"\(\?<([A-Za-z]\w*)>", r"(?P<\1>", js)


def managers():
    config = json.loads((ROOT / "renovate.json").read_text(encoding="utf-8"))
    for m in config.get("customManagers", []):
        files = [re.compile(py_pattern(p.strip("/"))) for p in m["managerFilePatterns"]]
        strings = [re.compile(py_pattern(s)) for s in m["matchStrings"]]
        yield m, files, strings


def extract(path: Path, as_name: str):
    """Deps the managers whose file patterns match `as_name` extract from `path`."""
    text = path.read_text(encoding="utf-8")
    found = []
    for m, files, strings in managers():
        if not any(f.search(as_name) for f in files):
            continue
        for s in strings:
            for hit in s.finditer(text):
                dep = {k: v for k, v in hit.groupdict().items() if v is not None}
                if "depName" not in dep and "depNameTemplate" in m:
                    dep["depName"] = m["depNameTemplate"]
                found.append(dep)
    return found


def main() -> int:
    errors = []

    toolchain = (ROOT / "lean-toolchain").read_text(encoding="utf-8").strip()
    want = [{"depName": "leanprover/lean4", "currentValue": toolchain.split(":v", 1)[1]}]
    got = extract(ROOT / "lean-toolchain", "lean-toolchain")
    if got != want:
        errors.append(f"lean-toolchain: extracted {got}, want {want}")

    want, versions = [], {}
    for line in (ROOT / "tools/tools.lock").read_text(encoding="utf-8").splitlines():
        cols = line.split()
        if not cols or line.startswith("#") or len(cols) != 5:
            continue
        name, version, platform, _digest, url = cols
        if version not in url:
            errors.append(f"tools.lock: {name} URL does not name version {version}; "
                          f"re-pin with tools/pin-tool.sh {name} {version}")
        if versions.setdefault(name, version) != version:
            errors.append(f"tools.lock: {name} lines name {versions[name]} and {version}")
        if platform == "linux-x86_64":
            repo = "/".join(url.removeprefix("https://github.com/").split("/")[:2])
            want.append({"depName": name, "currentValue": version, "packageName": repo})
    got = extract(ROOT / "tools/tools.lock", "tools/tools.lock")
    if got != want:
        errors.append(f"tools/tools.lock: extracted {got}, want {want}")

    for path in (ROOT / "lake-manifest.json", ROOT / "tests/renovate/lake-manifest.json"):
        packages = json.loads(path.read_text(encoding="utf-8")).get("packages", [])
        want = [{"packageName": re.sub(r"\.git$", "", p["url"].removeprefix("https://github.com/")),
                 "currentDigest": p["rev"], "depName": p["name"], "currentValue": p["inputRev"]}
                for p in packages]
        got = extract(path, "lake-manifest.json")
        if got != want:
            errors.append(f"{path.relative_to(ROOT)}: extracted {got}, want {want}")
    if not json.loads((ROOT / "tests/renovate/lake-manifest.json").read_text())["packages"]:
        errors.append("tests/renovate/lake-manifest.json: the fixture must list packages")

    for e in errors:
        print(f"renovate: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
