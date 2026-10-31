"""Fixture-backed stand-in for the v0 API (API.md) so console variants build before the server lands.

Usage: python3 mock.py [port]  (default 8442) → http://127.0.0.1:<port>/console/<variant>/
Stdlib only. Routes + shapes = fixtures/v0/*.json; lookups hit on spec_id `vf.contrast-2x2`
alone, checks accept only the entry's example input.
"""

import json
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIX = ROOT / "fixtures" / "v0"
VARIANTS = ROOT / "console" / "variants"


def fixture(name):
    return json.loads((FIX / f"{name}.json").read_text())


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
        elif p in ("/v0/health", "/v0/catalog", "/v0/demand", "/v0/answers"):
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
            if not q:
                self.send_json(422, {"error": "empty_query", "detail": "give spec_id, artifact_sha256 or statement"})
            elif q.get("spec_id") == "vf.contrast-2x2":
                self.send_json(200, fixture("lookup-hit"))
            else:
                self.send_json(404, fixture("lookup-miss") | {"query": q})
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
