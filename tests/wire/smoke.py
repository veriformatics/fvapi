#!/usr/bin/env python3
"""Shipped wire controls. The blind W suite owns the broad schema oracle."""

import json
import reprlib
import subprocess
import sys
from pathlib import Path

BINARY = Path(sys.argv[1] if len(sys.argv) > 1 else ".lake/build/bin/fvapi").resolve()
COUNT = 0
FAILURES = []


def compact(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def invoke(arguments, body=b"", rc=0):
    proc = subprocess.run([str(BINARY), "dev", "wire", *arguments], input=body, capture_output=True)
    if proc.returncode != rc:
        raise AssertionError(f"{arguments}: rc {proc.returncode} != {rc}: {proc.stderr!r}")
    return json.loads(proc.stdout) if rc == 0 else None


def check(name, actual, expected):
    global COUNT
    if actual != expected:
        FAILURES.append(f"wire: {name}: {reprlib.repr(actual)} != {reprlib.repr(expected)}")
    COUNT += 1


def main():
    empty = {"ok": {"query": {}}}
    check("health_none", invoke(["request", "health"]), empty)
    check("none_nonempty", invoke(["request", "health"], b"{}"),
          {"status": 400, "error": "malformed"})
    check("query_syntax_before_duplicate",
          invoke(["request", "health", "--query", "a=1&a=2&x=%"], b"{"),
          {"status": 400, "error": "malformed"})
    check("query_duplicate_before_body",
          invoke(["request", "health", "--query", "a=1&a=2"], b"{"),
          {"status": 400, "error": "duplicate_key"})
    check("body_before_unknown", invoke(["request", "lookup", "--query", "bogus=x"], b"{"),
          {"status": 400, "error": "malformed"})
    check("unknown_before_types", invoke(["request", "admit"], b'{"package":{"x":0}}'),
          {"status": 400, "error": "unknown_key"})
    check("lookup_empty", invoke(["request", "lookup"], b"{}"),
          {"status": 400, "error": "empty_query"})
    check("lookup_tag", invoke(["request", "lookup"],
                               compact({"statement_digest": "sd2:" + "a" * 64})),
          {"status": 400, "error": "unsupported"})
    check("catalog_defaults", invoke(["request", "catalog"]),
          {"ok": {"query": {"limit": 100}}})
    check("query_numeric_spelling", invoke(["request", "catalog", "--query", "limit=01"]),
          {"status": 400, "error": "malformed"})
    check("check_raw", invoke(["request", "check", "--query", "spec=x&revision=1"], b"\xff\0"),
          {"ok": {"query": {"spec": "x", "revision": 1}, "body_hex": "ff00"}})
    check("check_over_cap", invoke(["request", "check", "--query", "spec=x&revision=1"],
                                    b"a" * 65537), {"status": 413, "error": "too_large"})
    check("bundle_raw", invoke(["response", "bundle", "200"], b"\xff\0"),
          {"ok": {"body_hex": "ff00"}})
    check("features_before_status", invoke(["response", "me", "201"],
                                           compact({"required_features": ["z", "a"]})),
          {"outcome": "unsupported", "features": ["z", "a"]})
    check("features_whole_declaration", invoke(["response", "me", "200"],
                                               compact({"required_features": ["z", 1]})),
          {"outcome": "bad_response"})
    check("features_duplicate", invoke(["response", "me", "200"],
                                       compact({"required_features": ["z", "z"]})),
          {"outcome": "bad_response"})
    check("additive_response", invoke(["response", "me", "200"],
                                      compact({"caller_id": "x", "extra": {"future": None}})),
          {"ok": {"caller_id": "x"}})
    check("health_no_401", invoke(["response", "health", "401"],
                                 compact({"error": "unauthorized", "detail": ""})),
          {"outcome": "bad_response"})
    check("check_binding_409", invoke(["response", "check", "409"],
                                     compact({"error": "unknown_entry", "detail": ""})),
          {"ok": {"error": "unknown_entry", "detail": ""}})
    for route in ("health", "me", "catalog", "entry", "matches", "bundle", "rows", "changes",
                  "row", "answers"):
        query = {"matches": "cursor=x", "changes": "since=0"}.get(route, "")
        result = invoke(["request", route, "--query", query])
        if "ok" not in result:
            raise AssertionError(f"wire: route_{route}: {result}")
    for route, body in (("lookup", {"spec_id": "x"}), ("request", {"statement": "x"}),
                        ("claim", {}), ("release", {}), ("decline", {"reason": "x"}),
                        ("resolve", {"statement": "x"}),
                        ("admit", {"package": {"sha256": "a" * 64, "path": "/x"}})):
        check(f"route_{route}", "ok" in invoke(["request", route], compact(body)), True)
    attempt = {"number": 1, "state": "released", "claimed_ms": 0, "expires_ms": 0,
               "ended_ms": 0}
    row = {"id": "x", "revision": 1, "seq": 0, "origin": "miss", "state": "queued",
           "keys": {"spec_id": "x"}, "count": 1, "attempt_count": 101,
           "attempts": [dict(attempt, number=n) for n in range(101, 0, -1)],
           "created_ms": 0, "updated_ms": 0}
    check("row_attempt_page", invoke(["response", "row", "200"], compact(row)), {"ok": row})
    for route in ("claim", "release", "decline", "resolve"):
        check(f"{route}_embedded_attempt_cap", invoke(["response", route, "200"], compact(row)),
              {"outcome": "bad_response"})
    check("list_embedded_attempt_cap", invoke(["response", "rows", "200"], compact({"rows": [row]})),
          {"outcome": "bad_response"})
    first_page = dict(row, attempts=row["attempts"][:100], attempts_next_cursor="x")
    check("embedded_attempt_page", invoke(["response", "claim", "200"], compact(first_page)),
          {"ok": first_page})
    without_cursor = dict(first_page)
    del without_cursor["attempts_next_cursor"]
    check("embedded_attempt_cursor", invoke(["response", "claim", "200"], compact(without_cursor)),
          {"outcome": "bad_response"})
    later = dict(row, attempt_count=0, attempts=[], seq=2)
    earlier = dict(later, seq=1)
    check("changes_sequence_order", invoke(["response", "changes", "200"],
                                            compact({"rows": [later, earlier], "last_seq": 1,
                                                     "more": False})),
          {"outcome": "bad_response"})
    key = {"key": "spec_id", "value": "x", "matched": [], "matched_count": 0}
    check("miss_unique_key_names", invoke(["response", "lookup", "404"],
                                          compact({"error": "miss", "detail": "", "keys": [key, key],
                                                   "row": {"id": "x", "state": "queued"}})),
          {"outcome": "bad_response"})
    reference = {"id": "y", "revision": 1}
    check("matches_cursor_nonempty", invoke(["response", "matches", "200"],
                                             compact({"count": 1, "items": [],
                                                      "next_cursor": "cursor"})),
          {"outcome": "bad_response"})
    later_matches = {"count": 2, "items": [reference]}
    check("matches_later_page_without_cursor", invoke(["response", "matches", "200"],
                                                      compact(later_matches)),
          {"ok": later_matches})
    continuing_matches = dict(later_matches, next_cursor="cursor")
    check("matches_nonempty_continuation", invoke(["response", "matches", "200"],
                                                  compact(continuing_matches)),
          {"ok": continuing_matches})
    bundle = {"sha256": "a" * 64, "path": "/v1/bundles/" + "a" * 64,
              "packed_bytes": 1, "unpacked_bytes": 1}
    hit = {"outcome": "hit", "entry": "x", "revision": 1, "bundle": bundle,
           "other_matches": later_matches}
    check("lookup_first_page_cursor", invoke(["response", "lookup", "200"], compact(hit)),
          {"outcome": "bad_response"})
    empty_key_page = dict(key, matched_count=1, next_cursor="cursor")
    check("key_matches_cursor_nonempty", invoke(["response", "lookup", "404"],
                                                 compact({"error": "miss", "detail": "",
                                                          "keys": [empty_key_page],
                                                          "row": {"id": "x", "state": "queued"}})),
          {"outcome": "bad_response"})
    empty_attempt_page = dict(row, attempt_count=1, attempts=[], attempts_next_cursor="cursor")
    check("attempts_cursor_nonempty", invoke(["response", "row", "200"], compact(empty_attempt_page)),
          {"outcome": "bad_response"})
    request = {"statement": "\x01" * 65536, "note": "\0" * 65536,
               "artifact_sha256": "a" * 64, "idempotency_key": "A" * 128}
    encoded = invoke(["encode-request", "request"], compact({"query": {}, "body": request}))
    body = bytes.fromhex(encoded["body_hex"])
    check("largest_request_bytes", len(body), 786692)
    check("largest_request_query", encoded["query_string"], "")
    check("largest_request_round_trip", invoke(["request", "request"], body),
          {"ok": {"query": {}, "body": request}})
    raw = bytes(range(256)) * 256
    encoded = invoke(["encode-request", "check"],
                     compact({"query": {"spec": "x", "revision": 1}, "body_hex": raw.hex()}))
    check("check_cap_encoded", bytes.fromhex(encoded["body_hex"]), raw)
    check("check_cap_round_trip", invoke(["request", "check", "--query", encoded["query_string"]],
                                         raw)["ok"]["body_hex"], raw.hex())
    encoded = invoke(["encode-response", "me", "200"], compact({"caller_id": "x"}))
    check("response_encoded", bytes.fromhex(encoded["body_hex"]), b'{"caller_id":"x"}')
    invoke(["encode-request", "catalog"], compact({"query": {}}), rc=2)
    invoke(["request", "not-a-route"], rc=2)
    invoke(["response", "me", "0200"], rc=2)
    if FAILURES:
        raise AssertionError("\n".join(FAILURES))
    print(f"wire: {COUNT} controls passed; largest_request=786692 bytes; raw_check=65536 bytes")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
