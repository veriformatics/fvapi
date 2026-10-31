import io
import json
import os
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
from collections import Counter
from datetime import datetime, timezone
from html import escape
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from starlette.exceptions import HTTPException

STORE = Path(os.environ.get("FVAPI_STORE", "/srv/data/fvapi"))
ROOT = Path(__file__).resolve().parents[2]
STARTED = datetime.now(timezone.utc).isoformat()
LOCK = threading.Lock()
app = FastAPI(title="fvapi prototype")


def error(status, code, detail):
    return JSONResponse({"error": code, "detail": detail}, status_code=status)


@app.exception_handler(HTTPException)
async def http_error(request, exc):
    return error(exc.status_code, "not_found" if exc.status_code == 404 else "http_error", str(exc.detail))


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    return error(422, "invalid_request", str(exc))


def entries():
    result = []
    for path in sorted((STORE / "entries").glob("*/entry.json")):
        item = json.loads(path.read_text())
        if item["licence"]["spdx"].startswith("LicenseRef-Veriformatics"):
            item["licence"]["terms"] = "provisional: internal evaluation only; final terms set before outside delivery"
        result.append(item)
    return result


def lookup_matches(query, catalog):
    normal = lambda text: " ".join(text.split())
    matches = []
    for key in ("spec_id", "artifact_sha256", "statement"):
        if key not in query:
            continue
        value = query[key]
        found = []
        if isinstance(value, str) and value.strip():
            for item in catalog:
                artifact = item["subject"].get("artifact") or {}
                hit = (key == "spec_id" and value == item["id"]) or (key == "artifact_sha256" and value == artifact.get("sha256")) or (key == "statement" and any(normal(value) == normal(s["text"]) for s in item["statements"]))
                if hit:
                    found.append(item["id"])
        matches.append((key, value, found))
    common = set.intersection(*(set(ids) for _, _, ids in matches)) if matches else set()
    return matches, next((item for item in catalog if item["id"] in common), None)


def lookup_miss(matches):
    rows, descriptions = [], []
    for key, value, ids in matches:
        rows.append({"key": key, "value": value, "matched_entry": ids[0] if ids else None})
        shown = value[:12] + "…" if key == "artifact_sha256" and isinstance(value, str) and len(value) > 12 else value
        descriptions.append(f"{key} {shown} matches {', '.join(ids) if ids else 'no entry'}")
    return {"mismatch": rows, "detail": "; but ".join(descriptions) + ". All supplied keys must match the same entry. The miss is logged as demand; no agent works on single requests."}


def entry(entry_id):
    return next((e for e in entries() if e["id"] == entry_id), None)


def records(name):
    path = STORE / f"{name}.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def append(name, prefix, payload):
    with LOCK:
        STORE.mkdir(parents=True, exist_ok=True)
        rows = records(name)
        key = "answer_id" if name == "answers" else "miss_id"
        row = {key: f"{prefix}-{len(rows) + 1:06d}", "at": datetime.now(timezone.utc).isoformat(), **payload}
        with (STORE / f"{name}.jsonl").open("a") as stream:
            stream.write(json.dumps(row) + "\n")
        return row[key]


@app.get("/v0/health")
def health():
    try:
        lean = subprocess.run(["lean", "--version"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        lean = "unavailable"
    return {"service": "fvapi", "version": "0-prototype", "host": socket.gethostname(), "entries": len(entries()), "store": str(STORE), "lean": lean, "started_at": STARTED}


@app.get("/v0/catalog")
def catalog(kind: str = "", q: str = ""):
    summaries = []
    for e in entries():
        if kind and e["kind"] != kind:
            continue
        if q and q.casefold() not in json.dumps(e, ensure_ascii=False).casefold():
            continue
        summaries.append({**{k: e[k] for k in ("id", "title", "kind", "claim", "subject", "toolchain")}, "replay_status": e["replay"]["status"], "licence_spdx": e["licence"]["spdx"]})
    return {"entries": summaries}


@app.get("/v0/catalog/{entry_id}")
def show(entry_id: str):
    return entry(entry_id) or error(404, "unknown_entry", entry_id)


@app.post("/v0/lookup")
def lookup(query: dict):
    keys = ("spec_id", "artifact_sha256", "statement")
    if not any(isinstance(query.get(k), str) and query[k].strip() for k in keys):
        return error(422, "empty_query", "Supply spec_id, artifact_sha256 or statement.")
    matches, e = lookup_matches(query, entries())
    if e:
        answer = append("answers", "a", {"kind": "lookup", "entry_id": e["id"]})
        return {"hit": True, "answer_id": answer, "entry_id": e["id"], "matched_on": matches[0][0], "entry": e, "bundle": f"/v0/bundles/{e['id']}.tar.gz"}
    mismatch = lookup_miss(matches)
    miss = append("demand", "m", {"query": query, **mismatch})
    return JSONResponse({"hit": False, "miss_id": miss, "logged": True, "query": query, **mismatch}, status_code=404)


@app.get("/v0/bundles/{entry_id}.tar.gz")
def bundle(entry_id: str):
    e = entry(entry_id)
    if not e:
        return error(404, "unknown_entry", entry_id)
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        manifest = json.dumps(e, indent=2).encode()
        info = tarfile.TarInfo("manifest.json")
        info.size = len(manifest)
        archive.addfile(info, io.BytesIO(manifest))
        for item in e["closure"]:
            archive.add(STORE / "entries" / entry_id / "files" / item["path"], arcname=item["path"], recursive=False)
    return Response(output.getvalue(), media_type="application/gzip", headers={"Content-Disposition": f'attachment; filename="{entry_id}.tar.gz"'})


@app.post("/v0/checks/{entry_id}")
async def check(entry_id: str, request: Request):
    import asyncio
    import hashlib

    e = entry(entry_id)
    if not e:
        return error(404, "unknown_entry", entry_id)
    if not e["check"]:
        return error(409, "no_checker", "This entry has no executable checker.")
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw) > 65536:
            return error(413, "input_too_large", "Checker input must be at most 64 KiB.")
    try:
        json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        return error(422, "invalid_json", "Supply one JSON value.")
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="fvapi-check-") as directory:
        input_path = Path(directory) / "input.json"
        input_path.write_bytes(raw)
        checker_dir = STORE / "checkers" / entry_id
        argv = [arg.replace("{input}", str(input_path)) for arg in e["check"]["recheck"]["run"]]
        try:
            result = await asyncio.to_thread(subprocess.run, argv, cwd=checker_dir, capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired:
            return error(504, "checker_timeout", "Checker exceeded 10 seconds.")
        except OSError as exc:
            return error(503, "checker_unavailable", str(exc))
    if result.returncode not in (0, 2):
        return error(502, "checker_failed", f"Checker exited {result.returncode}: {result.stderr[:1000]}")
    try:
        output = json.loads(result.stdout.splitlines()[-1])
    except (ValueError, IndexError):
        return error(502, "checker_output", "Checker did not return JSON.")
    verdict = "accept" if result.returncode == 0 else "reject"
    answer = append("answers", "a", {"kind": "check", "entry_id": entry_id, "verdict": verdict})
    return {"verdict": verdict, "output": output, "exit_code": result.returncode, "elapsed_ms": round((time.monotonic() - start) * 1000), "ran_on": socket.gethostname(), "answer_id": answer, "entry_id": entry_id, "input_sha256": hashlib.sha256(raw).hexdigest(), "recheck": {"bundle": f"/v0/bundles/{entry_id}.tar.gz", "command": f"fvapi check {entry_id} input.json --recheck"}}


@app.get("/v0/demand")
def demand():
    rows = records("demand")
    counts = Counter(f"{k}:{v}" for row in rows for k, v in row["query"].items())
    return {"misses": rows[::-1], "by_key": [{"key": key, "count": count} for key, count in counts.most_common()]}


@app.get("/v0/answers")
def answers():
    return {"answers": records("answers")[::-1]}


@app.get("/", response_class=HTMLResponse)
def index():
    variants = ROOT / "console" / "variants"
    links = "".join(f'<li><a href="/console/{escape(p.name)}/">{escape(p.name)}</a></li>' for p in sorted(variants.iterdir()) if p.is_dir() and (p / "index.html").exists()) if variants.exists() else ""
    return f'<!doctype html><html lang="en"><meta charset="utf-8"><title>fvapi console variants</title><h1>fvapi console variants</h1><ul>{links}</ul><a href="/docs">API documentation</a></html>'


@app.get("/console/{variant}/{path:path}")
def console(variant: str, path: str = ""):
    root = (ROOT / "console" / "variants").resolve()
    target = (root / variant / (path or "index.html")).resolve()
    if not target.is_relative_to(root) or not target.is_file():
        return error(404, "not_found", "Console file not found.")
    return FileResponse(target)


def main():
    import uvicorn
    uvicorn.run(app, host=os.environ.get("FVAPI_HOST", "0.0.0.0"), port=int(os.environ.get("FVAPI_PORT", "8441")))
