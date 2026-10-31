"""Fixture-backed stand-in for the v0 API (API.md) so console variants build before the server lands.

Usage: python3 mock.py [port]  (default 8442) → http://127.0.0.1:<port>/console/<variant>/
Stdlib only. Routes + shapes = fixtures/v0/*.json; lookup entries come from full catalog fixtures
and all supplied lookup keys must agree. Checks accept only the entry's example input.
"""

import json
import sys
from collections import Counter
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "src" / "fvapi_proto"))
from work import work  # noqa: E402  stdlib-only module shared with server.py
FIX = ROOT / "fixtures" / "v0"
VARIANTS = ROOT / "console" / "variants"
MISSES = []


def fixture(name):
    return json.loads((FIX / f"{name}.json").read_text())


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


class Handler(SimpleHTTPRequestHandler):
    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/":
            items = "".join(f'<li><a href="/console/{d.name}/">{d.name}</a></li>'
                            for d in sorted(VARIANTS.glob("*/")))
            html = f"<!doctype html><title>fvapi mock</title><h1>Console variants (mock)</h1><ul>{items}</ul>"
            body = html.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
        elif p.startswith("/console/"):
            self.path = p[len("/console"):]
            self.directory = str(VARIANTS)
            super().do_GET()
        elif p in ("/v0/demand", "/v0/work"):
            rows = MISSES[::-1] + fixture("demand")["misses"]
            counts = Counter(f"{k}:{v}" for row in rows for k, v in row["query"].items())
            by_key = [{"key": key, "count": count} for key, count in counts.most_common()]
            if p == "/v0/work":
                state = dict(part.partition("=")[::2] for part in self.path.partition("?")[2].split("&") if part).get("state")
                self.send_json(200, work(by_key, force=state))
            else:
                self.send_json(200, {"misses": rows, "by_key": by_key})
        elif p in ("/v0/health", "/v0/catalog", "/v0/answers"):
            self.send_json(200, fixture(p.rsplit("/", 1)[1]))
        elif p.startswith("/v0/catalog/") and (FIX / f"catalog-{p.rsplit('/', 1)[1]}.json").is_file():
            self.send_json(200, fixture(f"catalog-{p.rsplit('/', 1)[1]}"))
        elif p.startswith("/v0/catalog/"):
            self.send_json(404, {"error": "unknown_entry", "detail": p.rsplit("/", 1)[1]})
        else:
            self.send_json(404, {"error": "not_found", "detail": p})

    def do_POST(self):
        p = self.path.split("?")[0]
        q = self.body()
        if p == "/v0/lookup":
            keys = ("spec_id", "artifact_sha256", "statement")
            if not any(isinstance(q.get(k), str) and q[k].strip() for k in keys):
                self.send_json(422, {"error": "empty_query", "detail": "Supply spec_id, artifact_sha256 or statement."})
                return
            catalog = [json.loads(path.read_text()) for path in sorted(FIX.glob("catalog-*.json"))]
            matches, entry = lookup_matches(q, catalog)
            if entry:
                self.send_json(200, fixture("lookup-hit") | {"entry_id": entry["id"], "entry": entry, "matched_on": matches[0][0], "bundle": f"/v0/bundles/{entry['id']}.tar.gz"})
            else:
                miss_id = f"mock-m-{len(MISSES) + 1:06d}"
                mismatch = lookup_miss(matches)
                MISSES.append({"miss_id": miss_id, "at": datetime.now(timezone.utc).isoformat(), "query": q, **mismatch})
                self.send_json(404, fixture("lookup-miss") | {"miss_id": miss_id, "query": q, **mismatch})
        elif p == "/v0/checks/vf.contrast-2x2":
            ok = q == fixture("catalog-vf.contrast-2x2")["check"]["example_input"]
            self.send_json(200, fixture("check-accept" if ok else "check-reject"))
        elif p.startswith("/v0/checks/"):
            self.send_json(409, {"error": "no_checker", "detail": "entry has no runnable checker"})
        else:
            self.send_json(404, {"error": "not_found", "detail": p})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8442
    print(f"mock on http://127.0.0.1:{port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
