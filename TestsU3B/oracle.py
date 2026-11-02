"""Independent U3B wire oracle; docs/api.md + U3 J1–J7, never implementation imports."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Callable

MAX_INT = 9007199254740991
HASH = "0" * 64
DIGEST = "sd1:" + HASH
PROFILE = "sha256:" + HASH


class JsonFailure(ValueError):
    pass


class Pairs(list):
    pass


def lexical_depth(data: bytes) -> int:
    level = top = 0
    quoted = escaped = False
    for byte in data:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            level += 1
            top = max(level, top)
        elif byte in (93, 125):
            level = max(0, level - 1)
    return top


def reject_number(_: str) -> Any:
    raise JsonFailure("malformed")


def integer(token: str) -> int:
    if re.fullmatch(r"0|-?[1-9][0-9]*", token) is None or len(token) > 17:
        raise JsonFailure("malformed")
    value = int(token)
    if abs(value) > MAX_INT:
        raise JsonFailure("malformed")
    return value


def walk_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, Pairs):
        for key, child in value:
            yield key
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def duplicates(value: Any) -> bool:
    if isinstance(value, Pairs):
        keys = [key for key, _ in value]
        return len(set(keys)) != len(keys) or any(duplicates(child) for _, child in value)
    return isinstance(value, list) and any(duplicates(child) for child in value)


def normalize(value: Any) -> Any:
    if isinstance(value, Pairs):
        return {key: normalize(child) for key, child in sorted(value, key=lambda p: p[0].encode())}
    if isinstance(value, list):
        return [normalize(child) for child in value]
    return value


def decode(data: bytes) -> Any:
    if lexical_depth(data) > 32:
        raise JsonFailure("too_large")
    try:
        text = data.decode("utf-8", "strict")
        raw = json.loads(text, parse_int=integer, parse_float=reject_number,
                         parse_constant=reject_number, object_pairs_hook=Pairs)
        # JSON accepts escaped lone surrogate halves; the fvapi scalar grammar does not.
        lengths = [len(s.encode("utf-8", "strict")) for s in walk_strings(raw)]
    except (UnicodeError, ValueError, RecursionError) as error:
        raise JsonFailure("malformed") from error
    if any(n > 65536 for n in lengths):
        raise JsonFailure("too_large")
    if duplicates(raw):
        raise JsonFailure("duplicate_key")
    return normalize(raw)


def quote(text: str) -> str:
    short = {8: r"\b", 9: r"\t", 10: r"\n", 12: r"\f", 13: r"\r"}
    return '"' + "".join(
        r'\"' if c == '"' else r"\\" if c == "\\" else short.get(ord(c), f"\\u{ord(c):04x}")
        if ord(c) < 32 or ord(c) == 127 else c for c in text) + '"'


def canonical(value: Any) -> bytes:
    def render(v: Any) -> str:
        if v is None:
            return "null"
        if type(v) is bool:
            return "true" if v else "false"
        if type(v) is int:
            return str(v)
        if isinstance(v, str):
            return quote(v)
        if isinstance(v, list):
            return "[" + ",".join(map(render, v)) + "]"
        return "{" + ",".join(quote(k) + ":" + render(v[k]) for k in sorted(v, key=lambda k: k.encode())) + "}"
    return render(value).encode("utf-8")


@dataclass(frozen=True)
class Scalar:
    name: str
    accepts: Callable[[Any], bool]
    sample: Any
    good: tuple[Any, ...] = ()
    bad: tuple[Any, ...] = ()


@dataclass(frozen=True)
class Array:
    child: Any
    low: int
    high: int


@dataclass(frozen=True)
class Record:
    required: dict[str, Any]
    optional: dict[str, Any]
    refinement: Callable[[dict[str, Any]], bool] = lambda _: True


@dataclass(frozen=True)
class Union:
    tag: str
    branches: dict[str, Record]


def regex(name: str, pattern: str, sample: str, good=(), bad=()) -> Scalar:
    return Scalar(name, lambda v: isinstance(v, str) and re.fullmatch(pattern, v, re.ASCII) is not None,
                  sample, tuple(good), tuple(bad))


def string(name: str, low: int, high: int, sample: str, extra=lambda _: True, good=(), bad=()) -> Scalar:
    return Scalar(name, lambda v: isinstance(v, str) and low <= len(v.encode()) <= high and extra(v),
                  sample, tuple(good), tuple(bad))


def enum(*values: str) -> Scalar:
    return Scalar("enum:" + "|".join(values), lambda v: isinstance(v, str) and v in values,
                  values[0], values[1:], ("", "invalid"))


def rec(required=None, optional=None, refinement=lambda _: True) -> Record:
    return Record(required or {}, optional or {}, refinement)


NAT = Scalar("nat", lambda v: type(v) is int and 0 <= v <= MAX_INT, 0,
             (1, MAX_INT), (-1, True, "0"))
POS = Scalar("pos", lambda v: type(v) is int and 1 <= v <= MAX_INT, 1,
             (2, MAX_INT), (0, -1, True, "1"))
BOOL = Scalar("bool", lambda v: type(v) is bool, True, (False,), (0, 1, "true"))
IDENT = regex("ident", r"[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?", "sample",
              ("a", "0", "a.b_c-d", "a" * 128),
              ("", "A", "_a", "a_", "a~b", "a" * 129, "λ", "a\x00"))
SHA = regex("sha256", r"[0-9a-f]{64}", HASH, ("f" * 64,), ("0" * 63, "0" * 65, "F" * 64))
PROFILE_ID = regex("profile_id", r"sha256:[0-9a-f]{64}", PROFILE,
                   (), (HASH, "sha256:" + "F" * 64, "SHA256:" + HASH))
DIG = regex("digest", r"[a-z0-9]{1,16}:[0-9a-f]{64}", DIGEST,
            ("a:" + HASH, "a" * 16 + ":" + HASH),
            ("A:" + HASH, ":" + HASH, "a" * 17 + ":" + HASH, DIGEST + "x"))
TOKEN = regex("token", r"[A-Za-z0-9._~-]{1,128}", "tok",
              ("A._~-0", "T" * 128), ("", "T" * 129, "a/b", "λ"))
CURSOR = regex("cursor", r"[A-Za-z0-9_-]{1,1024}", "cursor",
               ("A_-0", "x" * 1024), ("", "x" * 1025, "a.b", "a~b", "%"))
LABEL = regex("label", r"[\x21-\x7e]{1,256}", "lean-4.35.0",
              ("!", "~" * 256), ("", "a b", "x" * 257, "é", "a\x7f"))
SPDX = regex("spdx", r"[\x21-\x7e](?:[\x20-\x7e]{0,254}[\x21-\x7e])?", "Apache-2.0",
             ("A OR B", "x" * 256), ("", " A", "A ", "x" * 257, "a\tB"))
SOURCE = string("source", 1, 65536, "theorem sample : True := by trivial",
                lambda s: "\x00" not in s and any(c not in " \t\n\r" for c in s),
                ("x", " λ\n", "x" * 65536), ("", " \t\n\r", "x\x00", "λ" * 32769))
LEAN_NAME = string("lean_name", 1, 1024, "Example.sample",
                   lambda s: all(ord(c) >= 32 and ord(c) != 127 for c in s),
                   (" ", "«λ»", "x" * 1024), ("", "x" * 1025, "x\x00", "a\x1f", "a\x7f"))
ABS_PATH = string("abs_path", 1, 4096, "/tmp/sample",
                  lambda s: s.startswith("/") and "\x00" not in s,
                  ("/", "/" + "x" * 4095, "/../source"), ("", "relative", "/a\x00", "/" + "x" * 4096))
ANY = Scalar("any", lambda _: True, None, (0, False, "", [], {}, [None, {"k": None}]), ())
ROW_STATE = enum("queued", "being_proved", "added", "declined")
COVERAGE = enum("full", "partial")
VERDICT = enum("accept", "reject")
TEXT_256 = string("text[1,256]", 1, 256, "Synthetic", good=("λ", "x" * 256), bad=("", "x" * 257))
TEXT_1024 = string("text[1,1024]", 1, 1024, "Synthetic claim", good=("x" * 1024,), bad=("", "x" * 1025))
TEXT_4096 = string("text[1,4096]", 1, 4096, "reason", good=("x" * 4096,), bad=("", "x" * 4097))
NOTE = string("text[0,65536]", 0, 65536, "note", good=("", "x" * 65536, "λ" * 32768), bad=("x" * 65537,))
DETAIL = string("text[0,4096]", 0, 4096, "detail", good=("", "x" * 4096), bad=("x" * 4097,))

ENTRY_REF = rec({"id": IDENT, "revision": POS})
ROW_REF = rec({"id": TOKEN, "state": ROW_STATE})
KEYS = rec(optional={"spec_id": IDENT, "artifact_sha256": SHA, "statement_digest": DIG})
BUNDLE_REF = rec({"sha256": SHA, "path": string("bundle_path", 1, 4096, "/v1/bundles/" + HASH),
                  "packed_bytes": POS, "unpacked_bytes": POS},
                 refinement=lambda v: v["path"] == "/v1/bundles/" + v["sha256"])
SUBJECT = rec({"name": TEXT_256}, {"artifact_sha256": SHA})
TARGET = rec({"spec_id": IDENT, "statement_digest": DIG, "module": LEAN_NAME, "declaration": LEAN_NAME})
CHECKER = rec({"spec_id": IDENT, "declaration": LEAN_NAME, "coverage": COVERAGE})
SUMMARY = rec({"id": IDENT, "revision": POS, "title": TEXT_256, "kind": IDENT,
               "claim": TEXT_1024, "subject": SUBJECT, "targets": Array(TARGET, 1, 256),
               "toolchain": LABEL, "licence_spdx": SPDX, "has_checker": BOOL}, {"terms": TEXT_1024})
REVISION = rec({**SUMMARY.required, "bundle": BUNDLE_REF, "admitted_ms": NAT},
               {**SUMMARY.optional, "checker": CHECKER},
               lambda v: v["has_checker"] == ("checker" in v))


def page(v: dict[str, Any], items: str, count: str, cursor: str, first=False) -> bool:
    size, total, continuation = len(v[items]), v[count], cursor in v
    if size > total or continuation and (size == 0 or size >= total):
        return False
    return not first or continuation == (size < total)


MATCHES = rec({"count": NAT, "items": Array(ENTRY_REF, 0, 1000)}, {"next_cursor": CURSOR},
              lambda v: page(v, "items", "count", "next_cursor"))
KEY_MATCH = Union("key", {
    name: rec({"key": enum(name), "value": scalar, "matched": Array(ENTRY_REF, 0, 100),
               "matched_count": NAT}, {"next_cursor": CURSOR},
              lambda v: page(v, "matched", "matched_count", "next_cursor", first=True))
    for name, scalar in KEYS.optional.items()
})
CERT = rec({"export_sha256": SHA, "path": string("certificate_path", 1, 4096, "/v1/bundles/" + HASH)},
           refinement=lambda v: v["path"] == "/v1/bundles/" + v["export_sha256"])
VERIFICATION = Union("status", {
    "kernel_certificate": rec({"status": enum("kernel_certificate"), "label": enum("kernel certificate"), "certificate": CERT}),
    "compiled_evaluation": rec({"status": enum("compiled_evaluation"), "label": enum("compiled evaluation (trusts the Lean compiler)")}),
    "failed": rec({"status": enum("failed"), "label": enum("verification failed")}),
})
ATTEMPT = rec({"number": POS, "state": enum("active", "released", "expired", "closed"),
               "claimed_ms": NAT, "expires_ms": NAT}, {"ended_ms": NAT},
              lambda v: ("ended_ms" in v) == (v["state"] != "active"))
ROW = rec({"id": TOKEN, "revision": POS, "seq": NAT, "origin": enum("request", "miss"),
           "state": ROW_STATE, "keys": KEYS, "count": POS, "attempt_count": NAT,
           "attempts": Array(ATTEMPT, 0, 1000), "created_ms": NAT, "updated_ms": NAT},
          {"statement": SOURCE, "note": NOTE, "attempts_next_cursor": CURSOR,
           "entry_revision": ENTRY_REF, "reason": TEXT_4096},
          lambda v: ("entry_revision" in v) == (v["state"] == "added")
          and ("reason" in v) == (v["state"] == "declined")
          and page(v, "attempts", "attempt_count", "attempts_next_cursor")
          and (v["origin"] == "miss" and bool(v["keys"])
               or v["origin"] == "request" and "statement" in v and v["count"] == 1
               and set(v["keys"]) <= {"artifact_sha256"}))
KERNELS = {"leanchecker": "lean", "leanchecker-paranoid": "lean", "lean4lean": "lean",
           "nanoda": "nanoda", "con-leche": "con", "con-ron": "con"}
KERNEL_STATUS = rec({"name": enum(*KERNELS), "lineage": enum("lean", "nanoda", "con"),
                     "status": enum("accept", "reject", "decline", "crash", "timeout")}, {"feature": NOTE},
                    lambda v: v["lineage"] == KERNELS[v["name"]]
                    and ("feature" in v) == (v["status"] == "decline"))
RECEIPT = rec({"build": LABEL, "verification_profile": PROFILE_ID, "comparator": LABEL,
               "kernels": Array(KERNEL_STATUS, 1, 16), "at_ms": NAT})
ANSWER_BASE = {"id": TOKEN, "at_ms": NAT, "caller_id": TOKEN}
ANSWER = Union("operation", {
    "lookup": rec({**ANSWER_BASE, "operation": enum("lookup"), "outcome": enum("hit", "miss"), "keys": KEYS},
                  {"entry": ENTRY_REF}, lambda v: bool(v["keys"]) and ("entry" in v) == (v["outcome"] == "hit")),
    "check": rec({**ANSWER_BASE, "operation": enum("check"), "entry": ENTRY_REF, "input_sha256": SHA,
                  "verdict": VERDICT, "verification": VERIFICATION, "coverage": COVERAGE}),
})
CAUSES = ("challenge_mismatch", "forbidden_axiom", "kernel_missing", "kernel_rejected", "kernel_crashed",
          "kernel_timeout", "unnamed_unsupported", "insufficient_independent_kernels", "profile_mismatch",
          "kernel_identity_mismatch", "export_failed", "comparator_error", "input_mismatch",
          "package_mismatch", "invalid_package", "revision_exists", "missing_challenge")
LIMIT = Scalar("limit", lambda v: type(v) is int and 1 <= v <= 1000, 100,
               (1, 1000), (0, -1, 1001, "100", True))


@dataclass(frozen=True)
class Route:
    mode: str
    query: Record
    body: Record | None
    status: int
    response: Record | None
    errors: dict[int, tuple[str, ...]]


ROUTES = {
    "health": Route("none", rec(), None, 200, rec({"status": enum("ok"), "version": LABEL, "toolchain": LABEL,
                                                        "profile": PROFILE_ID, "catalog_revision": NAT}), {}),
    "me": Route("none", rec(), None, 200, rec({"caller_id": TOKEN}), {}),
    "catalog": Route("none", rec(optional={"cursor": CURSOR, "limit": LIMIT}), None, 200,
                     rec({"catalog_revision": NAT, "entries": Array(SUMMARY, 0, 1000)}, {"next_cursor": CURSOR}), {}),
    "entry": Route("none", rec(optional={"revision": POS}), None, 200, REVISION, {404: ("unknown_entry",)}),
    "lookup": Route("json", rec(optional={"limit": LIMIT}), KEYS, 200,
                    rec({"outcome": enum("hit"), "entry": IDENT, "revision": POS, "bundle": BUNDLE_REF,
                         "other_matches": MATCHES}), {400: ("empty_query", "unsupported"), 404: ("miss",)}),
    "matches": Route("none", rec({"cursor": CURSOR}, {"limit": LIMIT}), None, 200, MATCHES, {}),
    "bundle": Route("none", rec(), None, 200, None, {404: ("unknown_bundle",)}),
    "check": Route("bytes", rec({"spec": IDENT, "revision": POS}), None, 200,
                   rec({"verdict": VERDICT, "output": ANY, "input_sha256": SHA, "verification": VERIFICATION,
                        "coverage": COVERAGE, "entry": IDENT, "revision": POS, "bundle": BUNDLE_REF}),
                   {404: ("unknown_entry",), 409: ("no_checker", "unknown_entry")}),
    "request": Route("json", rec(), rec({"statement": SOURCE}, {"artifact_sha256": SHA, "note": NOTE, "idempotency_key": TOKEN}),
                     202, rec({"row": ROW_REF}), {}),
    "rows": Route("none", rec(optional={"state": ROW_STATE, "cursor": CURSOR, "limit": LIMIT}), None, 200,
                  rec({"rows": Array(ROW, 0, 1000)}, {"next_cursor": CURSOR}), {}),
    "changes": Route("none", rec({"since": NAT}, {"limit": LIMIT}), None, 200,
                     rec({"rows": Array(ROW, 0, 1000), "last_seq": NAT, "more": BOOL},
                         refinement=lambda v: (not v["more"] or bool(v["rows"]))
                         and all(a["seq"] < b["seq"] for a, b in zip(v["rows"], v["rows"][1:]))
                         and (not v["rows"] or v["last_seq"] == v["rows"][-1]["seq"])), {}),
    "row": Route("none", rec(optional={"attempt_cursor": CURSOR, "limit": LIMIT}), None, 200, ROW, {404: ("unknown_row",)}),
    "claim": Route("json", rec(), rec(), 200, ROW, {404: ("unknown_row",), 409: ("bad_transition",)}),
    "release": Route("json", rec(), rec(), 200, ROW, {404: ("unknown_row",), 409: ("bad_transition",)}),
    "decline": Route("json", rec(), rec({"reason": TEXT_4096}), 200, ROW, {404: ("unknown_row",), 409: ("bad_transition",)}),
    "resolve": Route("json", rec(), rec({"statement": SOURCE}), 200, ROW, {404: ("unknown_row",), 409: ("bad_transition",)}),
    "answers": Route("none", rec(optional={"cursor": CURSOR, "limit": LIMIT}), None, 200,
                     rec({"answers": Array(ANSWER, 0, 1000)}, {"next_cursor": CURSOR}), {}),
    "admit": Route("json", rec(), rec({"package": rec({"sha256": SHA, "path": ABS_PATH})}, {"row": TOKEN}),
                   200, rec({"entry": IDENT, "revision": POS, "admission": RECEIPT}),
                   {404: ("unknown_row",), 422: ("not_admitted",)}),
}
COMMON_ERRORS = {400: ("malformed", "duplicate_key", "unknown_key"), 401: ("unauthorized",),
                 413: ("too_large",), 500: ("internal",), 503: ("busy",)}
FEATURES = Array(IDENT, 0, 32)


def sample(schema: Any, rich=False) -> Any:
    if isinstance(schema, Scalar):
        return schema.sample
    if isinstance(schema, Array):
        return [sample(schema.child, rich) for _ in range(max(1 if rich else 0, schema.low))]
    if isinstance(schema, Union):
        return sample(next(iter(schema.branches.values())), rich)
    result = {k: sample(v, rich) for k, v in schema.required.items()}
    if rich:
        result.update({k: sample(v, rich) for k, v in schema.optional.items()})
    if schema is KEYS:
        return {"spec_id": "sample"}
    if schema is REVISION:
        result["has_checker"] = "checker" in result
    if schema is ROW:
        result.update(origin="request", state="queued", keys={}, count=1,
                      statement=SOURCE.sample, attempt_count=len(result["attempts"]))
        for k in ("entry_revision", "reason", "attempts_next_cursor"):
            result.pop(k, None)
    elif schema is ATTEMPT:
        result.pop("ended_ms", None)
    elif schema is KERNEL_STATUS:
        result.pop("feature", None)
    elif schema is MATCHES:
        result["count"] = len(result["items"])
        result.pop("next_cursor", None)
    elif isinstance(result, dict) and "matched_count" in result:
        result["matched_count"] = len(result["matched"])
        result.pop("next_cursor", None)
    elif isinstance(result, dict) and result.get("operation") == "lookup":
        result["entry"] = sample(ENTRY_REF)
    if "last_seq" in result and "more" in result:
        result["more"] = bool(result["rows"])
        for seq, row in enumerate(result["rows"]):
            row["seq"] = seq
        if result["rows"]:
            result["last_seq"] = result["rows"][-1]["seq"]
    return result


def fields(schema: Record) -> dict[str, Any]:
    return {**schema.required, **schema.optional}


def unknown_members(schema: Any, value: Any) -> bool:
    if isinstance(schema, Union):
        if not isinstance(value, dict):
            return False
        branch = schema.branches.get(value.get(schema.tag))
        return branch is not None and unknown_members(branch, value)
    if isinstance(schema, Record) and isinstance(value, dict):
        declared = fields(schema)
        return bool(set(value) - set(declared)) or any(unknown_members(declared[k], v) for k, v in value.items() if k in declared)
    if isinstance(schema, Array) and isinstance(value, list):
        return any(unknown_members(schema.child, v) for v in value)
    return False


def typed(schema: Any, value: Any) -> bool:
    if isinstance(schema, Scalar):
        return value is not None and schema.accepts(value) if schema is not ANY else True
    if isinstance(schema, Array):
        return isinstance(value, list) and schema.low <= len(value) <= schema.high and all(typed(schema.child, v) for v in value)
    if isinstance(schema, Union):
        return isinstance(value, dict) and isinstance(value.get(schema.tag), str) and value[schema.tag] in schema.branches and typed(schema.branches[value[schema.tag]], value)
    return isinstance(value, dict) and set(schema.required) <= set(value) and all(
        typed(s, value[k]) for k, s in fields(schema).items() if k in value)


def refined(schema: Any, value: Any) -> bool:
    if isinstance(schema, Scalar):
        return True
    if isinstance(schema, Array):
        return all(refined(schema.child, v) for v in value)
    if isinstance(schema, Union):
        return refined(schema.branches[value[schema.tag]], value)
    # Additive response members are outside a record's cross-member domain.
    known = project(schema, value)
    return schema.refinement(known) and all(refined(s, known[k]) for k, s in fields(schema).items() if k in known)


def project(schema: Any, value: Any) -> Any:
    if isinstance(schema, Scalar):
        return value
    if isinstance(schema, Array):
        return [project(schema.child, v) for v in value]
    if isinstance(schema, Union):
        return project(schema.branches[value[schema.tag]], value)
    return {k: project(s, value[k]) for k, s in fields(schema).items() if k in value}


def parse_query(query: str) -> dict[str, str]:
    if not query:
        return {}
    items = query.split("&")
    if any(re.fullmatch(r"[A-Za-z0-9._~-]+=[A-Za-z0-9._~-]+", item, re.ASCII) is None for item in items):
        raise JsonFailure("malformed")
    pairs = [item.split("=") for item in items]
    if len({k for k, _ in pairs}) != len(pairs):
        raise JsonFailure("duplicate_key")
    return dict(pairs)


def request(route: str, query: str, body: bytes) -> dict[str, Any]:
    r = ROUTES[route]
    try:
        q = parse_query(query)
        if r.mode == "json":
            value = decode(body)
            if not isinstance(value, dict):
                raise JsonFailure("malformed")
        elif r.mode == "none":
            if body:
                raise JsonFailure("malformed")
            value = None
        else:
            if len(body) > 65536:
                raise JsonFailure("too_large")
            value = body
        if set(q) - set(fields(r.query)) or r.mode == "json" and unknown_members(r.body, value):
            raise JsonFailure("unknown_key")
        normalized = {}
        for key, raw in q.items():
            scalar = fields(r.query)[key]
            if scalar in (NAT, POS, LIMIT):
                if re.fullmatch(r"0|[1-9][0-9]*", raw) is None or len(raw) > 16:
                    raise JsonFailure("malformed")
                normalized[key] = int(raw)
            else:
                normalized[key] = raw
        if not typed(r.query, normalized) or r.mode == "json" and (not typed(r.body, value) or not refined(r.body, value)):
            raise JsonFailure("malformed")
        if "limit" in fields(r.query) and "limit" not in normalized:
            normalized["limit"] = 100
        if route == "lookup":
            if not value:
                raise JsonFailure("empty_query")
            if "statement_digest" in value and not value["statement_digest"].startswith("sd1:"):
                raise JsonFailure("unsupported")
        result = {"query": normalized}
        if r.mode == "json":
            result["body"] = project(r.body, value)
        elif r.mode == "bytes":
            result["body_hex"] = body.hex()
        return {"ok": result}
    except JsonFailure as error:
        code = str(error)
        return {"status": 413 if code == "too_large" else 400, "error": code}


def error_schema(route: str, status: int) -> Record | None:
    codes = COMMON_ERRORS.get(status, ()) + ROUTES[route].errors.get(status, ())
    if route == "health" and status == 401:
        codes = ()
    if not codes:
        return None
    required = {"error": enum(*codes), "detail": DETAIL}
    if route == "lookup" and status == 404:
        required.update(keys=Array(KEY_MATCH, 1, 3), row=ROW_REF)
    if route == "admit" and status == 422:
        required.update(statuses=Array(KERNEL_STATUS, 0, 16), causes=Array(enum(*CAUSES), 1, 32))
    return rec(required, refinement=lambda v: len({m["key"] for m in v["keys"]}) == len(v["keys"])) if route == "lookup" and status == 404 else rec(required)


def response(route: str, status: int, body: bytes) -> dict[str, Any]:
    r = ROUTES[route]
    if route == "bundle" and status == 200:
        return {"ok": {"body_hex": body.hex()}}
    try:
        value = decode(body)
    except JsonFailure:
        return {"outcome": "bad_response"}
    if not isinstance(value, dict):
        return {"outcome": "bad_response"}
    if "required_features" in value:
        f = value["required_features"]
        if not typed(FEATURES, f) or len(set(f)) != len(f):
            return {"outcome": "bad_response"}
        if f:
            return {"outcome": "unsupported", "features": f}
    schema = r.response if status == r.status else error_schema(route, status)
    if schema is None or not typed(schema, value) or not refined(schema, value):
        return {"outcome": "bad_response"}
    # Lists and mutation replies embed the first attempt page, at most 100 entries.
    rows = value.get("rows", []) if route in ("rows", "changes") and status == r.status else [value] if route in ("claim", "release", "decline", "resolve") and status == r.status else []
    if any(len(v["attempts"]) > 100 or not page(v, "attempts", "attempt_count", "attempts_next_cursor", first=True) for v in rows):
        return {"outcome": "bad_response"}
    if route == "lookup" and status == 200 and not page(value["other_matches"], "items", "count", "next_cursor", first=True):
        return {"outcome": "bad_response"}
    result = project(schema, value)
    if "required_features" in value:
        result["required_features"] = value["required_features"]
    return {"ok": result}


def normalized_query(route: str, rich=False) -> dict[str, Any]:
    r = ROUTES[route]
    q = sample(r.query, rich)
    if "limit" in fields(r.query):
        q.setdefault("limit", 100)
    return q


def query_text(query: dict[str, Any]) -> str:
    return "&".join(k + "=" + str(v) for k, v in sorted(query.items()))
