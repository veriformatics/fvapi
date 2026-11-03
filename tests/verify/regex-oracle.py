#!/usr/bin/env python3
"""G1 reference: finite greedy AST histories, independent of the production Thompson graph."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import itertools
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Iterator

ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Atom:
    kind: str
    value: str = ""
    ranges: tuple[tuple[str, str], ...] = ()
    negated: bool = False
    equal_range: bool = False


@dataclass(frozen=True)
class Group:
    body: tuple[Piece, ...]


@dataclass(frozen=True)
class Piece:
    atom: Atom | Group
    quantifier: str = ""


Capture = str | None
History = tuple[int, Capture]


def atom_histories(atom: Atom | Group, line: str, pos: int, capture: Capture) -> Iterator[History]:
    if isinstance(atom, Group):
        for end, _ in sequence(atom.body, line, pos, capture):
            yield end, line[pos:end]
    elif atom.kind == "start":
        if pos == 0:
            yield pos, capture
    elif atom.kind == "finish":
        if pos == len(line):
            yield pos, capture
    elif pos < len(line):
        char = line[pos]
        if atom.kind == "any":
            matches = True
        elif atom.kind == "literal":
            matches = char == atom.value
        else:
            matches = any(lo <= char <= hi for lo, hi in atom.ranges) != atom.negated
        if matches:
            yield pos + 1, capture


def repetitions(atom: Atom | Group, line: str, pos: int, capture: Capture,
                minimum: bool) -> Iterator[History]:
    for end, latest in atom_histories(atom, line, pos, capture):
        if end == pos:
            yield end, latest  # One zero-width body iteration finishes this repetition.
        else:
            yield from repetitions(atom, line, end, latest, False)
    if not minimum:
        yield pos, capture


def piece_histories(piece: Piece, line: str, pos: int, capture: Capture) -> Iterator[History]:
    if piece.quantifier in {"*", "+"}:
        yield from repetitions(piece.atom, line, pos, capture, piece.quantifier == "+")
    else:
        yield from atom_histories(piece.atom, line, pos, capture)
        if piece.quantifier == "?":
            yield pos, capture


def sequence(pieces: tuple[Piece, ...], line: str, pos: int, capture: Capture) -> Iterator[History]:
    if not pieces:
        yield pos, capture
    else:
        for end, latest in piece_histories(pieces[0], line, pos, capture):
            yield from sequence(pieces[1:], line, end, latest)


def expected(pieces: tuple[Piece, ...], text: str) -> Capture:
    for line in text.split("\n"):
        for start in range(len(line) + 1):
            best_end = -1
            best_capture = None
            for end, capture in sequence(pieces, line, start, None):
                if end > best_end:
                    best_end, best_capture = end, capture or ""
            if best_end >= 0:
                return best_capture
    return None


def quote(char: str, inside: bool = False) -> str:
    if char in {"\n", "\r", "\t"}:
        return {"\n": r"\n", "\r": r"\r", "\t": r"\t"}[char]
    special = "\\]-^" if inside else "\\.[]()*+?^$|"
    return "\\" + char if char in special else char


def render_atom(atom: Atom | Group) -> str:
    if isinstance(atom, Group):
        return "(" + render(atom.body) + ")"
    if atom.kind == "literal":
        return quote(atom.value)
    if atom.kind == "any":
        return "."
    if atom.kind in {"start", "finish"}:
        return "^" if atom.kind == "start" else "$"
    content = "".join(quote(lo, True) if lo == hi and not atom.equal_range else
                      quote(lo, True) + "-" + quote(hi, True) for lo, hi in atom.ranges)
    return "[" + ("^" if atom.negated else "") + content + "]"


def render(pieces: tuple[Piece, ...]) -> str:
    return "".join(render_atom(piece.atom) + piece.quantifier for piece in pieces)


def literal(char: str, quantifier: str = "") -> Piece:
    return Piece(Atom("literal", char), quantifier)


START, FINISH = Piece(Atom("start")), Piece(Atom("finish"))


def corpus():
    rows: dict[tuple[str, str], Capture] = {}

    def add(pieces, text, spelling=None):
        pattern = spelling or render(pieces)
        result = expected(pieces, text)
        key = pattern, text
        if key in rows:
            assert rows[key] == result, "reference AST/render disagreement"
        rows[key] = result

    lines = ["".join(chars) for length in range(4) for chars in itertools.product("ab", repeat=length)]
    lines += ["λ", "😀", "aλ", "λa", "\r", "\t", "-", "z", ".", "d", "a\tb", "a\rb"]
    atoms = [Atom("literal", char) for char in "abλ😀\r\t.-d"] + [Atom("any"),
             Atom("class", ranges=(("a", "b"),)),
             Atom("class", ranges=(("a", "a"),), negated=True),
             Atom("class", ranges=(("a", "a"),), equal_range=True),
             Atom("class", ranges=(("a", "a"), ("-", "-"), ("z", "z"))),
             Atom("class", ranges=(("\r", "\r"), ("\t", "\t"))),
             Atom("class", ranges=(("λ", "ω"),))]
    for atom, quantifier in itertools.product(atoms, ("", "*", "+", "?")):
        for pieces in [(Piece(Group((Piece(atom, quantifier),))),),
                       (START, Piece(Group((Piece(atom, quantifier),))), FINISH),
                       (Piece(Group((literal("x"),))), Piece(atom, quantifier))]:
            for line in lines + ["xa", "xb", "xλ", "x\t"]:
                add(pieces, line)
    pool = [literal("a"), literal("b"), literal("a", "*"), literal("a", "?"),
            literal("b", "+"), Piece(Atom("any"), "*")]
    bodies = [()] + [(piece,) for piece in pool] + list(itertools.product(pool, repeat=2))
    bodies += [(START, literal("a", "*")), (literal("a", "?"), FINISH), (START, FINISH)]
    contexts = [((), ()), ((START,), (FINISH,)), ((literal("a", "*"),), (FINISH,)),
                ((literal("a", "?"),), (literal("b", "?"),)),
                ((START, literal("a", "*"), literal("a", "*")), (FINISH,)),
                ((literal("a", "*"), literal("a", "*"), literal("a", "*"),
                  literal("a", "*")), (FINISH,))]
    for body, quantifier, (before, after) in itertools.product(bodies, ("", "*", "+", "?"), contexts):
        pieces = before + (Piece(Group(tuple(body)), quantifier),) + after
        for line in lines:
            add(pieces, line)
    for count in range(2, 9):
        pieces = ((START,) + (literal("a", "*"),) * count +
                  (Piece(Group((literal("b", "?"),))), FINISH))
        for length in range(9):
            add(pieces, "a" * length)
            add(pieces, "a" * length + "b")
    text_cases = ["noise\nU: \t\nU:named", "U:\nU:named", "U:a U:longer", "U:λ\r\nU:later"]
    for text in text_cases:
        add((START, literal("U"), literal(":"), Piece(Group((Piece(Atom("any"), "*"),))), FINISH), text)
    # The grammar quotes arbitrary scalars; Python's character-class shorthands do not apply.
    add((START, Piece(Group((literal("d"),))), FINISH), "d", r"^(\d)$")
    add((START, Piece(Group((literal("\n"),))), FINISH), "\n")
    disagreement = (literal("a", "?"), Piece(Group((literal("a"), literal("b"))), "?"))
    assert expected(disagreement, "ab") == "ab"
    match = re.search(render(disagreement), "ab")
    assert match is not None and match.span() == (0, 1) and match.group(1) is None
    add(disagreement, "ab")
    return rows


def agreement(rows):
    # Python agrees here by structure: fixed literals; anchored prefix+(.*)+$; the pinned
    # optional quote is in the following class, so consuming it cannot shorten the whole span;
    # fixed-width repeated groups always retain the same final group value.
    pinned_class = Atom("class", ranges=(("A", "Z"), ("a", "z"), ("0", "9"),
                                        ("_", "_"), (".", "."), ("'", "'")))
    prefix = tuple(literal(char) for char in "unknown constant ")
    patterns = [tuple(literal(char) for char in "deep recursion detected"),
                (START, literal("U"), literal(":"), Piece(Group((Piece(Atom("any"), "*"),))), FINISH),
                prefix + (literal("'", "?"), Piece(Group((Piece(pinned_class, "+"),)))),
                (START, Piece(Group((literal("a"), literal("b"))), "+"), FINISH)]
    lines = ["", "a", "abab", "U:λ\r", "U: \t", "deep recursion detected", "error: deep recursion detected",
             "unknown constant 'Nat.missing", "unknown constant Foo_2", "unknown constant ''",
             "error: unknown constant 'Nat.missing", "noise"]
    count = 0
    for pieces, line in itertools.product(patterns, lines):
        pattern = render(pieces)
        result = expected(pieces, line)
        match = re.search(pattern, line)
        python = None if match is None else (match.group(1) or "" if match.re.groups else "")
        assert result == python, (pattern, line, result, python)
        rows[pattern, line] = result
        count += 1
    print(f"regex Python agreement: {count} cases; longest-vs-first disagreement control retained")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prebuilt", action="store_true")
    args = parser.parse_args()
    if not args.prebuilt:
        build = subprocess.run(["lake", "build", "fvapi-tests-regex"],
                               cwd=ROOT, capture_output=True, text=True)
        if build.returncode:
            print(build.stdout + build.stderr, file=sys.stderr)
            return 2
    rows = corpus()
    agreement(rows)
    with tempfile.TemporaryDirectory(prefix="regex-oracle-", dir=ROOT / ".lake") as directory:
        path = Path(directory) / "cases.jsonl"
        path.write_text("".join(json.dumps([pattern, text, result], ensure_ascii=False) + "\n"
                                for (pattern, text), result in sorted(rows.items())))
        result = subprocess.run([str(ROOT / ".lake/build/bin/fvapi-tests-regex"), str(path)], cwd=ROOT)
        return 3 if result.returncode < 0 or result.returncode >= 128 else result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"setup: regex-oracle: {error}", file=sys.stderr)
        sys.exit(2)
