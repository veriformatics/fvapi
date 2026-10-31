import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path


def source_bytes(source):
    if source.startswith("git:"):
        repo_rev, path = source[4:].split(":", 1)
        repo, rev = repo_rev.rsplit("@", 1)
        return subprocess.check_output(["git", "-C", str(Path(repo).expanduser()), "show", f"{rev}:{path}"])
    return Path(source).expanduser().read_bytes()


def safe_path(path):
    result = Path(path)
    if result.is_absolute() or ".." in result.parts or not result.parts:
        raise ValueError(f"Unsafe closure path: {path}")
    return result


def statement(data, name):
    text = data.decode()
    short = name.rsplit(".", 1)[-1]
    # Qualified declaration names can themselves contain dots.
    candidates = (name, short)
    match = next((m for c in candidates if (m := re.search(r"(?m)^(?:private\s+|protected\s+)?(?:theorem|def|lemma)\s+" + re.escape(c) + r"(?=\s|\{|\(|:)", text))), None)
    if match is None:
        raise ValueError(f"Statement not found: {name}")
    end = text.find(":=", match.end())
    if end < 0:
        raise ValueError(f"Statement has no definition boundary: {name}")
    return {"line": text.count("\n", 0, match.start()) + 1, "text": text[match.start():end].rstrip()}


def seed(manifest, store):
    for spec in manifest["entries"]:
        e = copy.deepcopy(spec["entry"])
        base = store / "entries" / safe_path(e["id"])
        files = {}
        e["closure"] = []
        for item in spec["files"]:
            path = safe_path(item["path"])
            data = source_bytes(item["source"])
            target = base / "files" / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            files[str(path)] = data
            e["closure"].append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
        e["statements"] = [{"name": s["name"], "file": s["file"], **statement(files[s["file"]], s.get("declaration", s["name"]))} for s in spec["statements"]]
        if "artifact_source" in spec:
            data = source_bytes(spec["artifact_source"])
            e["subject"]["artifact"].update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        if "example_input_source" in spec:
            e["check"]["example_input"] = json.loads(source_bytes(spec["example_input_source"]))
        (base / "entry.json").write_text(json.dumps(e, indent=2, ensure_ascii=False) + "\n")
        print(f"{e['id']}: {len(files)} files, {sum(len(v) for v in files.values())} bytes")
    for name in ("demand", "answers"):
        (store / f"{name}.jsonl").touch(exist_ok=True)


def main():
    parser = argparse.ArgumentParser(description="Copy private local seed sources into an fvapi store.")
    parser.add_argument("--manifest", default=os.environ.get("FVAPI_SEED", "prototype/fvapi/seed.local.json"))
    parser.add_argument("--store", default=os.environ.get("FVAPI_STORE", "/srv/data/fvapi"))
    args = parser.parse_args()
    seed(json.loads(Path(args.manifest).read_text()), Path(args.store))
