#!/usr/bin/env python3
"""Blind W suite; generated contract cases + independent staged oracle."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import random
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oracle as O
from support import exact, parse_output


@dataclass
class Case:
    id: str
    row: str
    direction: str
    route: str
    query: str
    status: int
    body: bytes
    expected: Any
    rc: int = 0
    roundtrip: bool = False

    def argv(self, binary: str) -> list[str]:
        command = [binary, "dev", "wire", self.direction, self.route]
        if self.direction in ("response", "encode-response"):
            command.append(str(self.status))
        elif self.direction == "request" and self.query:
            command.extend(["--query", self.query])
        return command


class Cases:
    def __init__(self):
        self.cases: list[Case] = []
        self.ids: set[str] = set()

    def add(self, row: str, name: str, direction="request", route="lookup", query="", status=200,
            value=None, raw: bytes | None = None, expected=None, rc=0, roundtrip=False):
        ident = f"{row}-{name}"
        assert ident not in self.ids, ident
        self.ids.add(ident)
        body = raw if raw is not None else O.canonical(value)
        if expected is None and rc == 0:
            expected = O.request(route, query, body) if direction == "request" else O.response(route, status, body)
        self.cases.append(Case(ident, row, direction, route, query, status, body, expected, rc, roundtrip))


def at(value: Any, path: tuple) -> Any:
    for key in path:
        value = value[key]
    return value


def replaced(value: Any, path: tuple, new: Any) -> Any:
    if not path:
        return copy.deepcopy(new)
    result = copy.deepcopy(value)
    at(result, path[:-1])[path[-1]] = copy.deepcopy(new)
    return result


def nodes(schema, value, path=()):
    yield path, schema, value
    if isinstance(schema, O.Record) and isinstance(value, dict):
        for k, sub in O.fields(schema).items():
            if k in value:
                yield from nodes(sub, value[k], path + (k,))
    elif isinstance(schema, O.Array) and value:
        yield from nodes(schema.child, value[0], path + (0,))
    elif isinstance(schema, O.Union) and isinstance(value, dict) and value.get(schema.tag) in schema.branches:
        branch = schema.branches[value[schema.tag]]
        for k, sub in O.fields(branch).items():
            if k in value:
                yield from nodes(sub, value[k], path + (k,))


def valid_body(route: str, rich=True):
    r = O.ROUTES[route]
    return O.sample(r.body, rich) if r.mode == "json" else None


def response_value(route: str, rich=True):
    return O.sample(O.ROUTES[route].response, rich)


def schema_cases(out: Cases):
    for route, r in O.ROUTES.items():
        for rich in (False, True):
            query = O.query_text(O.normalized_query(route, rich))
            raw = O.canonical(valid_body(route, rich)) if r.mode == "json" else b"\xff\x00\x80" if r.mode == "bytes" else b""
            expected = O.request(route, query, raw)
            assert "ok" in expected, (route, "request", expected)
            out.add("T11", f"{route}-request-{'rich' if rich else 'minimal'}", route=route, query=query, raw=raw)
            raw = b"\xff\x00\x80" if route == "bundle" else O.canonical(response_value(route, rich))
            expected = O.response(route, r.status, raw)
            assert "ok" in expected, (route, "response", expected)
            out.add("T11", f"{route}-response-{'rich' if rich else 'minimal'}", "response", route, status=r.status, raw=raw)
        query = O.query_text(O.normalized_query(route, True))
        for key, scalar in O.fields(r.query).items():
            badq = O.normalized_query(route, True)
            badq[key] = "." if scalar is O.CURSOR else "INVALID"
            out.add("T12", f"{route}-query-{key}-wrong", route=route, query=O.query_text(badq),
                    raw=O.canonical(valid_body(route)) if r.mode == "json" else b"")
            if key in r.query.required:
                absent = O.normalized_query(route, True)
                del absent[key]
                out.add("T12", f"{route}-query-{key}-absent", route=route, query=O.query_text(absent),
                        raw=O.canonical(valid_body(route)) if r.mode == "json" else b"")
        out.add("T12", f"{route}-query-extra", route=route, query=query + ("&" if query else "") + "extra=1",
                raw=O.canonical(valid_body(route)) if r.mode == "json" else b"")
        for direction, schema, base in (("request", r.body, valid_body(route)),
                                         ("response", r.response, response_value(route) if r.response else None)):
            if schema is None:
                continue
            for i, (path, node, value) in enumerate(nodes(schema, base)):
                if isinstance(node, O.Scalar):
                    for suffix, wrong in (("null", None), ("kind", [] if not isinstance(value, list) else False)):
                        if node is O.ANY:
                            continue
                        out.add("T12", f"{route}-{direction}-n{i}-{suffix}", direction, route, query,
                                r.status, value=replaced(base, path, wrong))
                    if node.name.startswith("enum:"):
                        for j, alternative in enumerate(node.good):
                            out.add("T12", f"{route}-{direction}-n{i}-enum{j}", direction, route, query,
                                    r.status, value=replaced(base, path, alternative))
                elif isinstance(node, (O.Record, O.Union)):
                    out.add("T12", f"{route}-{direction}-n{i}-null-record", direction, route, query,
                            r.status, value=replaced(base, path, None))
                    record = node.branches[value[node.tag]] if isinstance(node, O.Union) else node
                    if isinstance(node, O.Union):
                        for tag, branch in node.branches.items():
                            out.add("T11", f"{route}-{direction}-n{i}-branch-{tag}", direction, route, query,
                                    r.status, value=replaced(base, path, O.sample(branch, True)))
                    for key in record.required:
                        missing = copy.deepcopy(base)
                        del at(missing, path)[key]
                        out.add("T12", f"{route}-{direction}-n{i}-missing-{key}", direction, route,
                                query, r.status, value=missing)
                    extra = copy.deepcopy(base)
                    at(extra, path)["unlisted"] = {"nested": None}
                    out.add("T12", f"{route}-{direction}-n{i}-extra", direction, route, query,
                            r.status, value=extra)
                elif isinstance(node, O.Array):
                    out.add("T12", f"{route}-{direction}-n{i}-not-array", direction, route, query,
                            r.status, value=replaced(base, path, {}))
                    if node.low:
                        out.add("T12", f"{route}-{direction}-n{i}-below", direction, route, query,
                                r.status, value=replaced(base, path, []))
                    for suffix, size in (("maximum", node.high), ("above", node.high + 1)):
                        boundary = replaced(base, path, [O.sample(node.child) for _ in range(size)])
                        if path and path[-1] in ("items", "matched", "attempts"):
                            parent = at(boundary, path[:-1])
                            parent[{"items": "count", "matched": "matched_count", "attempts": "attempt_count"}[path[-1]]] = size
                            parent.pop("next_cursor" if path[-1] != "attempts" else "attempts_next_cursor", None)
                        if route == "changes" and direction == "response" and path == ("rows",):
                            for seq, row in enumerate(boundary["rows"]):
                                row["seq"] = seq
                            boundary["last_seq"] = boundary["rows"][-1]["seq"] if boundary["rows"] else 0
                        out.add("T12", f"{route}-{direction}-n{i}-{suffix}", direction, route, query,
                                r.status, value=boundary)
                    out.add("T12", f"{route}-{direction}-n{i}-null-array", direction, route, query,
                            r.status, value=replaced(base, path, None))
            if direction == "response":
                # Tolerant means additions at every known record depth, not just the root.
                enriched = copy.deepcopy(base)
                for path, node, _ in nodes(schema, base):
                    if isinstance(node, (O.Record, O.Union)):
                        at(enriched, path)["addition"] = {"null": None, "arbitrary": [False, 0]}
                out.add("T12", f"{route}-recursive-additive", direction, route, status=r.status, value=enriched)


def driver_usage(out: Cases):
    out.add("T12", "unknown-route", route="not-a-route", raw=b"", rc=2)
    out.add("T12", "unknown-direction", direction="invalid", route="health", raw=b"", rc=2)
    for i, spelling in enumerate(("x", "200x", "1.0", "")):
        out.add("T12", f"status-spelling-{i}", "response", "me", status=spelling, value={"caller_id": "tok"}, rc=2)


def lookup_combinations(out: Cases):
    keys = [("spec_id", "sample"), ("artifact_sha256", O.HASH), ("statement_digest", O.DIGEST)]
    for mask in range(1, 8):
        out.add("T11", f"lookup-keys-{mask}", route="lookup",
                value={key: value for i, (key, value) in enumerate(keys) if mask & (1 << i)})


def scalars(out: Cases):
    contexts = [
        (O.IDENT, "request", "lookup", ("spec_id",), {"spec_id": "sample"}, "", 200),
        (O.SHA, "request", "lookup", ("artifact_sha256",), {"artifact_sha256": O.HASH}, "", 200),
        (O.DIG, "request", "lookup", ("statement_digest",), {"statement_digest": O.DIGEST}, "", 200),
        (O.TOKEN, "request", "request", ("idempotency_key",), valid_body("request"), "", 200),
        (O.SOURCE, "request", "request", ("statement",), valid_body("request"), "", 200),
        (O.NOTE, "request", "request", ("note",), valid_body("request"), "", 200),
        (O.TEXT_4096, "request", "decline", ("reason",), valid_body("decline"), "", 200),
        (O.ABS_PATH, "request", "admit", ("package", "path"), valid_body("admit"), "", 200),
        (O.PROFILE_ID, "response", "health", ("profile",), response_value("health"), "", 200),
        (O.LABEL, "response", "health", ("version",), response_value("health"), "", 200),
        (O.NAT, "response", "health", ("catalog_revision",), response_value("health"), "", 200),
        (O.SPDX, "response", "catalog", ("entries", 0, "licence_spdx"), response_value("catalog"), "", 200),
        (O.TEXT_256, "response", "catalog", ("entries", 0, "title"), response_value("catalog"), "", 200),
        (O.TEXT_1024, "response", "catalog", ("entries", 0, "claim"), response_value("catalog"), "", 200),
        (O.BOOL, "response", "catalog", ("entries", 0, "has_checker"), response_value("catalog"), "", 200),
        (O.LEAN_NAME, "response", "entry", ("targets", 0, "module"), response_value("entry"), "", 200),
        (O.ANY, "response", "check", ("output",), response_value("check"), "", 200),
        (O.DETAIL, "response", "me", ("detail",), {"error": "malformed", "detail": ""}, "", 400),
    ]
    for scalar, direction, route, path, base, query, status in contexts:
        for kind, values in (("good", (scalar.sample,) + scalar.good), ("bad", scalar.bad + (None,))):
            for i, value in enumerate(values):
                out.add("T13", f"{scalar.name}-{kind}-{i}", direction, route, query, status,
                        value=replaced(base, path, value))
    for scalar, route, field in ((O.CURSOR, "catalog", "cursor"), (O.POS, "check", "revision"),
                                  (O.LIMIT, "rows", "limit"), (O.NAT, "changes", "since")):
        for i, v in enumerate((scalar.sample,) + scalar.good + scalar.bad + ("00", "01", "1.0", "1e0", "-0")):
            query = O.normalized_query(route)
            query[field] = str(v).lower() if isinstance(v, bool) else str(v)
            out.add("T13", f"{scalar.name}-query-{i}", route=route, query=O.query_text(query), raw=b"")
    for n in (-O.MAX_INT, -1, 0, 1, O.MAX_INT):
        value = response_value("check")
        value["output"] = n
        out.add("T13", f"signed-any-{n}", "response", "check", value=value)


def mixed(out: Cases):
    # Every pair of server stages. Later faults remain present in the same invocation.
    for early in range(1, 5):
        for late in range(early + 1, 6):
            query = ""
            body = {"statement_digest": "new:" + O.HASH}
            if 4 in (early, late):
                body["spec_id"] = None
            if 3 in (early, late):
                body["unlisted"] = 0
            raw = O.canonical(body)
            if 2 in (early, late):
                raw = raw[:-1] + b",}"
            if 1 in (early, late):
                query = "x=%"
            out.add("T14", f"server-{early}-before-{late}", route="lookup", query=query, raw=raw)
    for early in range(1, 4):
        for late in range(early + 1, 5):
            value = response_value("entry")
            value["has_checker"] = False  # checker still present: stage 4.
            status = 200
            if 3 in (early, late):
                status = 201
            if 2 in (early, late):
                value["required_features"] = ["future-b", "future-a"]
            raw = O.canonical(value)
            if 1 in (early, late):
                raw += b"x"
            out.add("T14", f"client-{early}-before-{late}", "response", "entry", status=status, raw=raw)
    for name, raw in {
        "depth-before-syntax": b"x" + b"[" * 33,
        "syntax-before-oversize": b'{"note":"' + b"x" * 65537 + b'","statement":"x"}x',
        "oversize-before-duplicate": b'{"note":"' + b"x" * 65537 + b'","statement":"x","statement":"y"}',
        "syntax-before-duplicate": b'{"statement":"x","statement":"y"}x',
        "duplicate-before-unknown": b'{"unlisted":0,"unlisted":1}',
        "body-before-query-unknown": b'{"statement":}',
    }.items():
        out.add("T14", name, route="request", query="extra=1" if name.endswith("query-unknown") else "", raw=raw)


def json_composition(out: Cases):
    cases = [b'{"probe":-0}', b'{"probe":00}', b'{"probe":-01}', b'{"probe":1E0}',
             b'\xef\xbb\xbf{"spec_id":"sample"}', b'{"spec_id":"\\ud800"}', b'{"spec_id":"\\udc00"}',
             b'{"note":"' + b'[' * 33]
    for i, raw in enumerate(cases):
        out.add("T14", f"json-composition-{i}", route="lookup", raw=raw)
    for size in (65536, 65537):
        raw = b'{"' + b'x' * size + b'":0}'
        out.add("T14", f"decoded-key-{size}", route="lookup", raw=raw)
    out.add("T14", "noncharacter-is-content", route="request", value={"statement": "￿"})


def query_cases(out: Cases):
    invalid = ("?limit=1", "limit", "=1", "limit=", "&limit=1", "limit=1&", "limit=1&&cursor=x",
               "limit=1=2", "limit=%31", "limit=+1", "cursor=a+b", "cursor=a/b", "cursor=λ",
               "limit=1\\0", "limit=1\n", "limit=1&limit=2&extra=%", "extra=1&extra=2&limit=%")
    valid = ("", "limit=1", "limit=1000", "cursor=A_-0", "cursor=abc&limit=2",
             "limit=1&limit=2", "extra=1&extra=2", "extra=1&limit=0", "limit=0001", "limit=9007199254740992")
    for i, q in enumerate(invalid + valid):
        out.add("T15", f"query-{i}", route="catalog", query=q, raw=b"")
    for route in O.ROUTES:
        out.add("T15", f"{route}-repeat-wins-fields", route=route, query="unlisted=1&unlisted=2",
                raw=O.canonical(valid_body(route)) if O.ROUTES[route].mode == "json" else b"")


def body_modes(out: Cases):
    for route, r in O.ROUTES.items():
        if r.mode == "none":
            for i, body in enumerate((b"", b" ", b"{}", b"\xff")):
                out.add("T16", f"{route}-none-{i}", route=route,
                        query=O.query_text(O.normalized_query(route)), raw=body)
    for size in (0, 1, 65535, 65536, 65537):
        out.add("T16", f"check-bytes-{size}", route="check", query="spec=sample&revision=1", raw=b"\xff" * size)
    for i, raw in enumerate((b"", b"\xff\x00\x80", b"{", b"[]" * 40000, b"[" * 100000)):
        out.add("T16", f"bundle-raw-{i}", "response", "bundle", raw=raw)


def null_depth(out: Cases):
    for depth in (0, 1, 30, 31, 32, 33):
        output = None
        for _ in range(depth):
            output = [output]
        value = response_value("check")
        value["output"] = output
        out.add("T17", f"output-depth-{depth}", "response", "check", value=value)
    for value in (None, {"field": None}, [None, {"field": None}], {"x": [None]}):
        body = response_value("check")
        body["output"] = value
        out.add("T17", f"any-null-{len(out.cases)}", "response", "check", value=body)
    for route, r in O.ROUTES.items():
        if r.body:
            base = valid_body(route)
            for key in O.fields(r.body):
                v = copy.deepcopy(base)
                v[key] = None
                out.add("T17", f"{route}-{key}-null", route=route, value=v,
                        query=O.query_text(O.normalized_query(route)))
        if r.response:
            value = response_value(route)
            value["unlisted"] = None
            out.add("T17", f"{route}-unknown-null", "response", route, status=r.status, value=value)


def features(out: Cases):
    declarations = [None, False, "feature", {}, [None], [1], [["a"]], [""], ["Upper"],
                    ["a", "a"], ["a", "a", "b"], ["a", None], ["a", "not-valid-"],
                    ["f" + str(i) for i in range(33)], [], ["future"], ["z", "a", "m"]]
    for route, r in O.ROUTES.items():
        if route == "bundle":
            continue
        for i, declaration in enumerate(declarations):
            value = response_value(route)
            value["required_features"] = declaration
            out.add("T18", f"{route}-features-{i}", "response", route, status=r.status, value=value)
    for i, value in enumerate(({"error": "malformed", "detail": "", "required_features": ["z", "a"]},
                               {"required_features": ["future"]},
                               {"required_features": ["future", None]},
                               {"error": "unsupported", "detail": ""})):
        out.add("T18", f"before-status-{i}", "response", "lookup", status=400 if i == 3 else 299, value=value)


def pairings(out: Cases):
    all_codes = sorted({code for codes in O.COMMON_ERRORS.values() for code in codes}
                       | {code for r in O.ROUTES.values() for codes in r.errors.values() for code in codes})
    statuses = (200, 202, 400, 401, 404, 409, 413, 422, 500, 503)
    for route, r in O.ROUTES.items():
        for status in statuses:
            # Every route/status/code combination: invalid pairings fail even if body has all extra fields.
            for code in all_codes:
                body = {"error": code, "detail": "synthetic",
                        "keys": [O.sample(O.KEY_MATCH)], "row": O.sample(O.ROW_REF),
                        "statuses": [], "causes": ["missing_challenge"]}
                out.add("T19", f"{route}-{status}-{code}", "response", route, status=status, value=body)
    for cause in O.CAUSES + ("invalid",):
        out.add("T19", f"admission-cause-{cause}", "response", "admit", status=422,
                value={"error": "not_admitted", "detail": "", "statuses": [], "causes": [cause]})
    for kid, lineage in O.KERNELS.items():
        for status in ("accept", "reject", "decline", "crash", "timeout"):
            body = response_value("admit")
            fact = {"name": kid, "lineage": lineage, "status": status}
            if status == "decline":
                fact["feature"] = ""  # A blank captured diagnostic is legal on the wire, not a policy PASS.
            body["admission"]["kernels"] = [fact]
            out.add("T19", f"kernel-{kid}-{status}", "response", "admit", value=body)
            fact["lineage"] = "nanoda" if lineage != "nanoda" else "con"
            out.add("T19", f"kernel-{kid}-{status}-wrong-lineage", "response", "admit", value=body)


def refinements(out: Cases):
    entry = response_value("entry")
    entry["has_checker"] = False
    out.add("T12", "entry-checker-present-false", "response", "entry", value=entry)
    del entry["checker"]
    entry["has_checker"] = True
    out.add("T12", "entry-checker-absent-true", "response", "entry", value=entry)
    for route, path in (("entry", ("bundle", "path")), ("check", ("verification", "certificate", "path"))):
        body = response_value(route)
        out.add("T12", f"{route}-hash-path-binding", "response", route,
                value=replaced(body, path, "/v1/bundles/" + "1" * 64))
    for name, v in O.VERIFICATION.branches.items():
        value = response_value("check")
        value["verification"] = O.sample(v)
        out.add("T12", f"verification-{name}-valid", "response", "check", value=value)
        value["verification"]["label"] = "wrong label"
        out.add("T12", f"verification-{name}-wrong-label", "response", "check", value=value)
    for count, size, cursor in ((0, 0, False), (0, 1, False), (2, 1, True), (2, 1, False), (1, 1, True), (1, 0, True)):
        value = {"count": count, "items": [O.sample(O.ENTRY_REF)] * size}
        if cursor:
            value["next_cursor"] = "cursor"
        out.add("T12", f"matches-{count}-{size}-{cursor}", "response", "matches", value=value)
    for continuation in (False, True):
        value = response_value("lookup")
        value["other_matches"] = {"count": 2, "items": [O.sample(O.ENTRY_REF)]}
        if continuation:
            value["other_matches"]["next_cursor"] = "cursor"
        out.add("T12", f"lookup-first-page-continuation-{continuation}", "response", "lookup", value=value)
    for key, branch in O.KEY_MATCH.branches.items():
        match = O.sample(branch, True)
        body = {"error": "miss", "detail": "", "keys": [match], "row": O.sample(O.ROW_REF)}
        out.add("T11", f"key-match-{key}-valid", "response", "lookup", status=404, value=body)
        match["value"] = []
        out.add("T12", f"key-match-{key}-wrong-type", "response", "lookup", status=404, value=body)
        match["value"] = "sample" if key != "spec_id" else "UPPER"
        out.add("T12", f"key-match-{key}-wrong-scalar", "response", "lookup", status=404, value=body)
    for state in ("queued", "being_proved", "added", "declined"):
        row = O.sample(O.ROW, True)
        row["state"] = state
        if state == "added":
            row["entry_revision"] = O.sample(O.ENTRY_REF)
        if state == "declined":
            row["reason"] = "reason"
        out.add("T12", f"row-state-{state}-valid", "response", "row", value=row)
        if state in ("added", "declined"):
            row.pop("entry_revision" if state == "added" else "reason")
        else:
            row["reason"] = "not declined"
        out.add("T12", f"row-state-{state}-binding", "response", "row", value=row)
    for origin, keys, statement, count in (("request", {}, True, 1), ("request", {"artifact_sha256": O.HASH}, True, 1),
                                            ("request", {"spec_id": "sample"}, True, 1), ("request", {}, False, 1),
                                            ("request", {}, True, 2), ("miss", {}, False, 1),
                                            ("miss", {"spec_id": "sample"}, False, 2)):
        row = O.sample(O.ROW, True)
        row.update(origin=origin, keys=keys, count=count)
        if not statement:
            row.pop("statement", None)
        out.add("T12", f"row-origin-{len(out.cases)}", "response", "row", value=row)
    for state in ("active", "released", "expired", "closed"):
        for ended in (False, True):
            row = O.sample(O.ROW, True)
            row["attempts"][0]["state"] = state
            if ended:
                row["attempts"][0]["ended_ms"] = 0
            out.add("T12", f"attempt-{state}-ended-{ended}", "response", "row", value=row)
    for size in (100, 101, 1000, 1001):
        row = O.sample(O.ROW)
        row["attempts"] = [O.sample(O.ATTEMPT)] * size
        row["attempt_count"] = size
        for route in ("row", "claim"):
            out.add("T12", f"{route}-attempts-{size}", "response", route, value=row)


def ruled_refinements(out: Cases):
    for name, seqs, last_seq in (("out-of-order", (2, 1), 1), ("repeated", (1, 1), 1),
                                 ("last-mismatch", (1, 2), 1)):
        rows = [O.sample(O.ROW) for _ in seqs]
        for row, seq in zip(rows, seqs):
            row["seq"] = seq
        out.add("T12", f"changes-seq-{name}", "response", "changes",
                value={"rows": rows, "last_seq": last_seq, "more": False})
    for known_key in (False, True):
        row = O.sample(O.ROW)
        row["origin"] = "miss"
        row.pop("statement")
        row["keys"] = {"unlisted": True}
        if known_key:
            row["keys"]["spec_id"] = "sample"
        out.add("T12", f"miss-additive-known-key-{known_key}", "response", "row", value=row)


def encoders(out: Cases):
    rng = random.Random(0xF0A31)
    for route, r in O.ROUTES.items():
        for i in range(4):
            query = O.normalized_query(route, bool(i % 2))
            if "limit" in query:
                query["limit"] = rng.choice((1, 100, 1000))
            body = O.canonical(valid_body(route, bool(i % 2))) if r.mode == "json" else bytes(rng.randrange(256) for _ in range(i * 17)) if r.mode == "bytes" else b""
            normalized = O.request(route, O.query_text(query), body)
            assert "ok" in normalized, (route, normalized)
            out.add("T20", f"{route}-request-{i}", "encode-request", route,
                    value=normalized["ok"], expected=normalized, roundtrip=True)
            raw = bytes(rng.randrange(256) for _ in range(i * 13)) if route == "bundle" else O.canonical(response_value(route, bool(i % 2)))
            normalized = O.response(route, r.status, raw)
            assert "ok" in normalized, (route, normalized)
            out.add("T20", f"{route}-response-{i}", "encode-response", route, status=r.status,
                    value=normalized["ok"], expected=normalized, roundtrip=True)
        for bad in (None, [], {}, {"query": {}, "body": None}, {"query": {"unlisted": 0}}):
            out.add("T20", f"{route}-invalid-request-{len(out.cases)}", "encode-request", route,
                    value=bad, rc=2)
        for i, bad in enumerate((None, [], 42, {})):
            out.add("T20", f"{route}-invalid-response-{i}", "encode-response", route,
                    status=r.status, value=bad, rc=2)
        for status in sorted(set(O.COMMON_ERRORS) | set(r.errors)):
            schema = O.error_schema(route, status)
            if schema is None:
                continue
            error = O.sample(schema)
            normalized = O.response(route, status, O.canonical(error))
            assert "ok" in normalized, (route, status, normalized)
            out.add("T20", f"{route}-error-response-{status}", "encode-response", route,
                    status=status, value=normalized["ok"], expected=normalized, roundtrip=True)
    # Generated exact-byte property: arbitrary checker inputs, including NUL + invalid UTF-8.
    for i in range(32):
        raw = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 2048)))
        normalized = O.request("check", "spec=sample&revision=1", raw)
        out.add("T20", f"generated-check-{i}", "encode-request", "check", value=normalized["ok"],
                expected=normalized, roundtrip=True)
    for i in range(32):
        # Schema-preserving perturbations, not a finite expected-answer table.
        value = response_value("check")
        value["verdict"] = rng.choice(("accept", "reject"))
        value["coverage"] = rng.choice(("full", "partial"))
        value["verification"] = O.sample(rng.choice(list(O.VERIFICATION.branches.values())))
        value["output"] = {"n": rng.randrange(-O.MAX_INT, O.MAX_INT), "s": "λ\x00\x7f", "a": [None, bool(i % 2)]}
        normalized = O.response("check", 200, O.canonical(value))
        out.add("T20", f"generated-response-{i}", "encode-response", "check", value=normalized["ok"],
                expected=normalized, roundtrip=True)


def acceptance(out: Cases):
    for i, raw in enumerate((b"", b"{", b"[]", b"null", b"true", b"1", b'{"statement":}', b'{"statement":"x",}', b'{"statement":"x"}false')):
        out.add("T21", f"IF03-{i}", route="request", raw=raw)
    for i, raw in enumerate((b'{"spec_id":"a","spec_id":"b"}', b'{"spec_id":"a","spec_id":"a"}',
                              b'{"spec_id":"a","spec_\\u0069d":"b"}', b'{"probe":{"x":1,"x":2}}')):
        out.add("T21", f"IF04-{i}", raw=raw)
    for i, value in enumerate(({}, {"statement": "legacy text"}, {"spec_id": "x", "probe": True},
                                {"spec_id": None}, {"spec_id": 1}, {"artifact_sha256": []}, {"statement_digest": {}})):
        out.add("T21", f"IF05-{i}", value=value)
    for i, raw in enumerate((b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\x80", b"\x00")):
        out.add("T21", f"IF06-{i}", route="request", raw=b'{"statement":"' + raw + b'"}')
    out.add("T21", "IF06-unicode", route="request", value={"statement": "theorem unicode : α = α := rfl", "note": "valid UTF-8: λ"})
    numbers = ["0", "1", "-1", str(O.MAX_INT), str(-O.MAX_INT), "9007199254740992", "-9007199254740992",
               "1.0", "1e0", "0.1", "NaN", "Infinity", "01", "+1"]
    numbers += [sign + str(O.MAX_INT + 1 + i) for sign in ("", "-") for i in range(32)]
    for i, n in enumerate(numbers):
        out.add("T21", f"IF07-{i}", raw=b'{"probe":' + n.encode() + b'}')
    for depth in (0, 1, 30, 31, 32, 33, 64):
        out.add("T21", f"IF08-{depth}", raw=b'{"probe":' + b"[" * depth + b"0" + b"]" * depth + b"}")
    for n in (0, 1, 65535, 65536, 65537, 65538, 131072):
        out.add("T21", f"IF09-ascii-{n}", route="request", value={"statement": O.SOURCE.sample, "note": "a" * n})
    for n in (32768, 32769):
        out.add("T21", f"IF09-multibyte-{n}", route="request", value={"statement": O.SOURCE.sample, "note": "λ" * n})


def largest(out: Cases):
    # Both source + note encode 65,536 one-byte controls as six-byte escapes; source needs content.
    body = {"statement": "\x01" * 65536, "note": "\x00" * 65536,
            "artifact_sha256": "f" * 64, "idempotency_key": "T" * 128}
    raw = O.canonical(body)
    assert len(raw) == 786692, len(raw)
    assert "ok" in O.request("request", "", raw)
    out.add("T22", "max-canonical-request-786692", route="request", raw=raw)


def generate() -> list[Case]:
    out = Cases()
    for generator in (schema_cases, driver_usage, lookup_combinations, scalars, mixed, json_composition, query_cases, body_modes, null_depth, features,
                      pairings, refinements, encoders, acceptance, largest, ruled_refinements):
        generator(out)
    return out.cases


def selftest(cases: list[Case]):
    controls = [(b"-0", "malformed"), (b"1e0", "malformed"), (b'"\\ud800"', "malformed"),
                (b'"\\udc00"', "malformed"), (b'"\xed\xa0\x80"', "malformed"),
                (b"x" + b"[" * 33, "too_large"), (b'"' + b"[" * 33, "malformed"),
                (b'{"a":0,"\\u0061":1}', "duplicate_key"),
                (b'"' + b"x" * 65537 + b'"x', "malformed")]
    for raw, expected in controls:
        try:
            O.decode(raw)
        except O.JsonFailure as e:
            assert str(e) == expected, (raw[:50], str(e), expected)
        else:
            raise AssertionError((raw[:50], "accepted"))
    for value in ({"λ": "\x00\x01\b\t\n\r\f\x1f\x7f \U0010ffff", "a": [None, True, -O.MAX_INT]},
                  {"\U00010000": 1, "": 2}, O.sample(O.ROW, True)):
        raw = O.canonical(value)
        assert O.decode(raw) == value
        cross = subprocess.run(["jq", "-S", "-c"], input=raw, capture_output=True, check=True).stdout.rstrip(b"\n")
        assert cross == raw, (cross[:100], raw[:100])
    table = {case.id: case for case in cases}
    assert all("ok" in case.expected for case in cases if case.row == "T11"), "positive schema control rejected by oracle"
    assert table["T17-output-depth-31"].expected.get("ok")
    assert table["T17-output-depth-32"].expected == {"outcome": "bad_response"}
    assert table["T21-IF07-0"].expected == {"status": 400, "error": "unknown_key"}
    assert table["T21-IF09-ascii-65536"].expected.get("ok")
    assert table["T21-IF09-ascii-65537"].expected == {"status": 413, "error": "too_large"}
    assert len(table["T22-max-canonical-request-786692"].body) == 786692
    bad = {"outcome": "bad_response"}
    regressions = {
        **{f"T12-{route}-recursive-additive": "ok" in table[f"T12-{route}-recursive-additive"].expected
           for route in ("rows", "changes", "row", "claim", "release", "decline", "resolve")},
        **{f"T12-changes-seq-{name}": table[f"T12-changes-seq-{name}"].expected == bad
           for name in ("out-of-order", "repeated", "last-mismatch")},
        "T12-changes-response-n1-maximum": "ok" in table["T12-changes-response-n1-maximum"].expected,
        "T12-miss-additive-known-key-False": table["T12-miss-additive-known-key-False"].expected == bad,
        "T12-miss-additive-known-key-True": "ok" in table["T12-miss-additive-known-key-True"].expected,
        "T12-matches-1-0-True": table["T12-matches-1-0-True"].expected == bad,
        "T12-lookup-first-page-continuation-False": table["T12-lookup-first-page-continuation-False"].expected == bad,
    }
    failures = [name for name, passed in regressions.items() if not passed]
    assert not failures, ("oracle regression controls", failures)
    print(f"wire-oracle: {len(controls)} priority/scalar controls + 3 jq crosschecks + {len(regressions)} regression controls; {len(cases)} cases generated")


def invoke(argv, body):
    try:
        p = subprocess.run(argv, input=body, capture_output=True, timeout=30)
    except subprocess.TimeoutExpired:
        return 3, None, "timeout", -1
    if p.returncode < 0 or p.returncode >= 128:
        return 3, None, p.stderr.decode(errors="replace")[:200], p.returncode
    try:
        value = parse_output(p.stdout)
    except (ValueError, UnicodeError, RecursionError):
        value = None
    diagnostic = p.stderr.decode(errors="replace")[:200]
    if value is None and p.stdout:
        diagnostic += " stdout=" + repr(p.stdout[:200])
    return 0, value, diagnostic, p.returncode


def execute(case: Case, binary: str):
    classification, value, diagnostic, rc = invoke(case.argv(binary), case.body)
    if classification:
        return classification, rc, value, diagnostic
    if rc != case.rc:
        return 1, rc, value, diagnostic
    if case.rc == 2:
        # This assertion is paired with a supported-mode control by main(); a missing driver is not a pass.
        return 0, rc, value, diagnostic
    if case.roundtrip:
        if not isinstance(value, dict) or not isinstance(value.get("body_hex"), str):
            return 1, rc, value, diagnostic
        try:
            raw = bytes.fromhex(value["body_hex"])
        except ValueError:
            return 1, rc, value, diagnostic
        if value["body_hex"] != raw.hex():
            return 1, rc, value, "encoder hex is not lowercase canonical"
        if case.direction == "encode-request":
            q = value.get("query_string")
            if not isinstance(q, str):
                return 1, rc, value, "missing query_string"
            oracle = O.request(case.route, q, raw)
            cmd = [binary, "dev", "wire", "request", case.route, "--query", q]
        else:
            oracle = O.response(case.route, case.status, raw)
            cmd = [binary, "dev", "wire", "response", case.route, str(case.status)]
        c2, v2, d2, r2 = invoke(cmd, raw)
        if c2:
            return c2, r2, v2, d2
        if not exact(oracle, case.expected) or r2 != 0 or not exact(v2, case.expected):
            return 1, r2, v2, "encoder/decoder/oracle roundtrip differs"
        if case.direction == "encode-request" and O.ROUTES[case.route].mode == "json":
            if raw != O.canonical(case.expected["ok"]["body"]):
                return 1, rc, value, "request encoder differs from canonical bytes"
        elif case.direction == "encode-response" and not (case.route == "bundle" and case.status == 200):
            if raw != O.canonical(case.expected["ok"]):
                return 1, rc, value, "response encoder differs from canonical bytes"
        return 0, rc, value, ""
    return (0 if exact(value, case.expected) else 1), rc, value, diagnostic


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--records", default=".lake/tests-u3b/wire.jsonl")
    parser.add_argument("--binary", default=os.environ.get("FVAPI_U3B_BIN", ".lake/build/bin/fvapi"))
    args = parser.parse_args()
    cases = generate()
    if args.selftest:
        selftest(cases)
        return 0
    if args.list:
        for c in cases:
            print(f"{c.id}\t{c.row}\t{shlex.join(c.argv(args.binary))}\t{len(c.body)}")
        return 0
    if args.case:
        cases = [c for c in cases if c.id == args.case]
        if not cases:
            print("setup: no such case", file=sys.stderr)
            return 2
    if not Path(args.binary).is_file():
        print("setup: fvapi binary absent", file=sys.stderr)
        return 2
    start = time.monotonic()
    records = Path(args.records)
    records.parent.mkdir(parents=True, exist_ok=True)
    totals: dict[str, list[int]] = {}
    highest = 0
    # Invalid-invocation controls alone would pass on any CLI that exits 2. Pin the supported driver too.
    c0, v0, d0, r0 = invoke([args.binary, "dev", "wire", "request", "health"], b"")
    supported = c0 == 0 and r0 == 0 and exact(v0, {"ok": {"query": {}}})
    with records.open("w") as output:
        for c in cases:
            before = time.monotonic()
            result, rc, value, diagnostic = execute(c, args.binary)
            if c.rc == 2 and not supported:
                result = max(result, 1)
                diagnostic = "supported-mode positive control failed: " + d0
            highest = max(highest, result)
            stats = totals.setdefault(c.row, [0, 0])
            stats[0] += 1
            stats[1] += result != 0
            record = {"id": c.id, "row": c.row, "command": "python3 -I TestsU3B/wire.py --case " + shlex.quote(c.id),
                      "driver": c.argv(args.binary), "input_bytes": len(c.body),
                      "input_sha256": hashlib.sha256(c.body).hexdigest(), "expected_sha256": hashlib.sha256(O.canonical(c.expected)).hexdigest(),
                      "driver_rc": rc, "result": result, "observed": value,
                      "diagnostic": diagnostic, "wall_ms": round((time.monotonic() - before) * 1000, 2)}
            # Wide successful outputs stay reproducible by case id; avoid recording hundreds of KiB per record.
            if len(O.canonical(value)) > 1024:
                record["observed"] = {"sha256": hashlib.sha256(O.canonical(value)).hexdigest(), "bytes": len(O.canonical(value))}
            output.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n")
    for row, (total, failed) in sorted(totals.items()):
        print(f"{row}: {total} cases, {failed} failed")
    print(f"wire: {len(cases)} cases; rc={highest}; wall={time.monotonic() - start:.3f}s; records={records}")
    return highest


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, ValueError) as error:
        print(f"setup: {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2) from error
