"""Driver-output checks: Python's True == 1 must not weaken wire equality."""
from __future__ import annotations

import json
from typing import Any


def exact(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, list):
        return len(left) == len(right) and all(exact(a, b) for a, b in zip(left, right, strict=True))
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(exact(left[k], right[k]) for k in left)
    return left == right


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("driver emitted duplicate keys")
        result[key] = value
    return result


def reject_number(_: str):
    raise ValueError("driver emitted a non-integer number")


def scalars(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from scalars(child)
    elif isinstance(value, list):
        for child in value:
            yield from scalars(child)


def parse_output(data: bytes):
    value = json.loads(data.decode("utf-8", "strict"), object_pairs_hook=unique,
                       parse_float=reject_number, parse_constant=reject_number)
    for text in scalars(value):
        text.encode("utf-8", "strict")
    return value
