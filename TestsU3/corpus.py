#!/usr/bin/env python3
"""Independent J2/J3 crosscheck + deterministic test inputs; run with python3 -I.

RFC 8259 §§2/4/5/7/8: JSON-text = ws value ws; member = string name-separator
value; array = begin-array [ value *( value-separator value ) ] end-array.
§8.1: 'MUST be encoded using UTF-8'; §9 permits limits on nesting, numbers,
length and character contents. U3 J2 supplies the stricter profile.
Source: https://www.rfc-editor.org/rfc/rfc8259.txt
NIST page: https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/secure-hashing
Link label: 'SHA Test Vectors for Hashing Byte-Oriented Messages'.
Archive sha256: 929ef80b7b3418aca026643f6f248815913b60e01741a44bba9e118067f4c9b8
Raw response bytes are pinned in nist/SHA256SUMS. No fetched code runs.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import re
import subprocess
import sys

LIMIT = 9007199254740991
SEED = 0x8259_0003_35


class Pairs(list):
    pass


class Syntax(ValueError):
    pass


def depth_scan(raw):
    level = top = 0
    quoted = escaped = False
    for byte in raw:
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
            top = max(top, level)
        elif byte in (93, 125):
            level = max(0, level - 1)
    return top


def integer(text):
    if not re.fullmatch(r"0|-?[1-9][0-9]*", text):
        raise Syntax("integer spelling")
    if len(text.lstrip("-")) > 16 or abs(int(text)) > LIMIT:
        raise Syntax("integer range")
    return int(text)


def forbidden(_):
    raise Syntax("float or constant")


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, Pairs):
        for key, child in value:
            yield key
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def duplicate(value):
    if isinstance(value, Pairs):
        keys = [k for k, _ in value]
        return len(keys) != len(set(keys)) or any(duplicate(v) for _, v in value)
    return isinstance(value, list) and any(duplicate(v) for v in value)


def quote(text):
    escapes = {'"': '\\"', '\\': '\\\\', '\b': '\\b', '\f': '\\f',
               '\n': '\\n', '\r': '\\r', '\t': '\\t'}
    return '"' + ''.join(escapes.get(c, f'\\u{ord(c):04x}' if ord(c) < 32 or
                                    ord(c) == 127 else c) for c in text) + '"'


def canonical(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return quote(value)
    if isinstance(value, (dict, Pairs)):
        pairs = value.items() if isinstance(value, dict) else value
        return '{' + ','.join(quote(k) + ':' + canonical(v)
                              for k, v in sorted(pairs)) + '}'
    return '[' + ','.join(map(canonical, value)) + ']'


def outcome(raw):
    # This staged reference is not Python json.loads' default accept/reject policy.
    if depth_scan(raw) > 32:
        return 'tooLarge', b''
    try:
        value = json.loads(raw.decode('utf-8', 'strict'), parse_int=integer,
                           parse_float=forbidden, parse_constant=forbidden,
                           object_pairs_hook=Pairs, strict=True)
        # CPython retains lone escaped UTF-16 halves. The profile rejects them as syntax.
        texts = list(strings(value))
        for text in texts:
            text.encode('utf-8', 'strict')
    except (ValueError, RecursionError):
        return 'malformed', b''
    if any(len(text.encode('utf-8')) > 65536 for text in texts):
        return 'tooLarge', b''
    if duplicate(value):
        return 'duplicateKey', b''
    return 'ok', canonical(value).encode('utf-8')


def generated(rng, depth=4):
    scalars = [None, False, True, 0, -1, LIMIT, -LIMIT,
               ''.join(map(chr, range(160))), 'é/é/𝄞/ / /﷐/￿/\x00/\x7f', '']
    choice = rng.randrange(6 if depth else 4)
    if choice < 3:
        return rng.choice(scalars)
    if choice == 3:
        return rng.randint(-LIMIT, LIMIT)
    if choice == 4:
        return [generated(rng, depth - 1) for _ in range(rng.randrange(5))]
    keys = ['a', 'A', 'é', 'é', '\x00', '\x7f', '\\"', '𐀀', '', '𝄞', '﷐']
    rng.shuffle(keys)
    return {k: generated(rng, depth - 1) for k in keys[:rng.randrange(5)]}


def json_cases():
    rows = []

    def add(group, name, raw, expected=None):
        if isinstance(raw, str):
            raw = raw.encode('utf-8')
        tag, printed = outcome(raw)
        if expected is not None and tag != expected:
            raise AssertionError((group, name, expected, tag))
        rows.append((group, name, raw, tag, printed))

    positives = ['null', 'true', 'false', '0', '1', '-1', str(LIMIT), str(-LIMIT),
                 '[]', '{}', ' [ null , true , false , 1, -1, "" ] ',
                 '\t\r\n { "z" : [], "a": {"x": 0} } \n',
                 '"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0000\\u007f"',
                 '"\\uD800\\uDC00\\udbff\\udfff\\uDa12\\uDc34"',
                 '"/  ﻿﷐￿􏿿"', '{"𐀀":1,"":2,"a":3}',
                 '{"é":0,"é":1,"A":2,"a":3,"\\u0000":4}']
    for i, raw in enumerate(positives):
        add('T1', f'positive-{i:03}', raw, 'ok')
    add('T1', 'raw-del', b'"\x7f"', 'ok')
    for scalar in [*range(0xA0), 0x7FF, 0x800, 0xD7FF, 0xE000, 0xFFFF,
                   0x10000, 0x10FFFF, 0xFDD0, 0xFDEF, 0xFFFE, 0x1FFFE]:
        text = chr(scalar)
        add('T1', f'scalar-{scalar:06x}', json.dumps(text, ensure_ascii=True), 'ok')
        if scalar >= 32:
            add('T1', f'raw-scalar-{scalar:06x}', quote(text), 'ok')
    negatives = ['', ' ', 'nul', 'Null', 'TRUE', 'falsee', '-', '-0', '-00', '+1',
                 '00', '01', '-01', '1.0', '0.0', '1.', '.1', '1e0', '1E+2',
                 'NaN', 'Infinity', '-Infinity', str(LIMIT + 1), str(-LIMIT - 1),
                 '[]x', '{}{}', 'null true', '﻿{}', '[1,]', '[,1]', '[1 2]',
                 '{"a":}', '{"a" 1}', '{1:0}', '{"a":1,}', '"', '"\\"',
                 '"\\v"', '"\\x00"', '"\\u000g"', '"\\u0"',
                 '"\\ud800"', '"\\udc00"', '"\\ud800x\\udc00"',
                 '"\\ud800\\ud800"', '"\\udc00\\ud800"', '"\\ud800\\u0041"']
    for i, raw in enumerate(negatives):
        add('T2', f'negative-{i:03}', raw, 'malformed')
    for c in range(32):
        add('T2', f'raw-control-{c:02x}', b'"a' + bytes([c]) + b'b"', 'malformed')
    for c in [0, 8, 11, 12, 0x7F, 0xA0]:
        add('T2', f'non-ws-{c:02x}', bytes([c]) + b'null', 'malformed')
    bad_utf8 = [b'\x80', b'\xbf', b'\xc0\x80', b'\xc1\xbf', b'\xe0\x80\x80',
                b'\xf0\x80\x80\x80', b'\xc2', b'\xe1\x80', b'\xf1\x80\x80',
                b'\xc2\x20', b'\xe1\x20\x80', b'\xe1\x80\x20',
                b'\xf1\x20\x80\x80', b'\xf1\x80\x20\x80', b'\xf1\x80\x80\x20',
                b'\xed\xa0\x80', b'\xed\xbf\xbf', b'\xf4\x90\x80\x80',
                b'\xf5\x80\x80\x80', b'\xf8\x88\x80\x80\x80', b'\xfc\x84\x80\x80\x80\x80',
                b'\xfe', b'\xff']
    for i, bad in enumerate(bad_utf8):
        add('T2', f'utf8-string-{i:02}', b'"' + bad + b'"', 'malformed')
        add('T2', f'utf8-key-{i:02}', b'{"' + bad + b'":0}', 'malformed')
    cap = b'a' * 65537
    priority = [
        ('garbage-before-depth', b'x' + b'[' * 33, 'tooLarge'),
        ('utf8-before-depth', b'\xff' + b'[' * 33, 'tooLarge'),
        ('unclosed-string-brackets', b'"' + b'[' * 33, 'malformed'),
        ('unclosed-escaped-quote-brackets', b'"\\"' + b'[' * 33, 'malformed'),
        ('cap-before-garbage', b'"' + cap + b'"x', 'malformed'),
        ('cap-and-duplicate', b'{"x":0,"x":"' + cap + b'"}', 'tooLarge'),
        ('duplicate-before-garbage', b'{"x":0,"x":1}x', 'malformed'),
        ('cap-before-integer-range', b'["' + cap + b'",9007199254740992]', 'malformed'),
        ('cap-before-lone-surrogate', b'["' + cap + b'","\\ud800"]', 'malformed'),
        ('duplicate-before-cap', b'{"x":0,"x":1,"z":"' + cap + b'"}', 'tooLarge'),
        ('malformed-before-cap', b'[x,"' + cap + b'"]', 'malformed'),
        ('close-at-zero-depth', b']' * 100 + b'[' * 33, 'tooLarge'),
        ('depth-inside-closed-string', b'"' + b'[' * 100 + b'"', 'ok'),
        ('escaped-backslash-before-depth', b'"\\\\"' + b'[' * 33, 'tooLarge'),
        ('depth-beats-duplicate', b'{"x":0,"x":' + b'[' * 33, 'tooLarge'),
    ]
    for name, raw, tag in priority:
        add('T3', name, raw, tag)
    for n in [0, 1, 31, 32, 33, 64, 1000000]:
        add('T4', f'depth-{n}', b'[' * n + b'0' + b']' * n,
            'ok' if n <= 32 else 'tooLarge')
    for n in [31, 32, 33]:
        add('T4', f'object-depth-{n}', b'{"k":' * n + b'0' + b'}' * n,
            'ok' if n <= 32 else 'tooLarge')
    for name, unit in [('ascii', 'a'), ('two', 'é'), ('three', '界'), ('four', '𝄞')]:
        encoded = unit.encode()
        for target in [65535, 65536, 65537]:
            payload = encoded * (target // len(encoded)) + b'a' * (target % len(encoded))
            tag = 'ok' if target <= 65536 else 'tooLarge'
            add('T4', f'{name}-string-{target}', b'"' + payload + b'"', tag)
            add('T4', f'{name}-key-{target}', b'{"' + payload + b'":0}', tag)
    for n in [65536, 65537]:
        add('T4', f'escaped-string-{n}', b'"' + b'\\u0061' * n + b'"',
            'ok' if n <= 65536 else 'tooLarge')
    duplicates = [('same', '{"x":0,"x":1}'),
                  ('escape-alias', '{"a":0,"\\u0061":1}'),
                  ('slash-alias', '{"/":0,"\\/":1}'),
                  ('nul-alias', '{"a\\u0000b":0,"a\\u0000b":1}'),
                  ('pair-alias', '{"𝄞":0,"\\ud834\\udd1e":1}'),
                  ('nested', '{"a":[{"x":null,"x":false}]}'),
                  ('separated', '{"z":0,"b":1,"a":2,"z":3}'),
                  ('hex-case-alias', '{"\\u00e9":0,"\\u00E9":1}')]
    for name, raw in duplicates:
        add('T5', name, raw, 'duplicateKey')
    add('T5', 'normalization-distinct', '{"é":0,"é":1}', 'ok')
    add('T5', 'case-distinct', '{"a":0,"A":1}', 'ok')
    add('T5', 'complete-nul-keys', '{"a":0,"a\\u0000":1,"a\\u0000b":2}', 'ok')
    rng = random.Random(SEED)
    sources = []
    for i in range(2048):
        v = generated(rng)
        raw = json.dumps(v, ensure_ascii=bool(i % 2),
                         separators=(',', ':') if i % 3 else (', ', ': ')).encode()
        sources.append(raw)
        add('T6', f'generated-print-{i:04}', raw, 'ok')
    for i in range(4096):
        raw = bytearray(rng.choice(sources))
        action = rng.randrange(4)
        at = rng.randrange(len(raw) + 1)
        if action == 0:
            raw[at:at] = bytes([rng.randrange(256)])
        elif action == 1 and at < len(raw):
            del raw[at]
        elif action == 2 and at < len(raw):
            raw[at] = rng.randrange(256)
        else:
            raw = raw[:at]
        add('T2', f'mutation-{i:04}', bytes(raw))
    for i in range(2048):
        add('T2', f'arbitrary-{i:04}', rng.randbytes(rng.randrange(81)))
    return rows


def crosscheck_jq(rows):
    accepted = [row for row in rows if row[3] == 'ok']
    stream = b'\n'.join(row[2] for row in accepted) + b'\n'
    proc = subprocess.run(['jq', '-S', '-c', '.'], input=stream, capture_output=True)
    if proc.returncode:
        raise RuntimeError(f'jq rc={proc.returncode}: {proc.stderr[:300]!r}')
    printed = proc.stdout.split(b'\n')
    if printed[-1] != b'':
        raise AssertionError('jq final LF absent')
    printed.pop()
    if len(printed) != len(accepted):
        raise AssertionError(('jq output count', len(printed), len(accepted)))
    for row, output in zip(accepted, printed, strict=True):
        if output != row[4]:
            raise AssertionError(('jq canonical', row[1], output[:100], row[4][:100]))
    version = subprocess.check_output(['jq', '--version']).decode().strip()
    print(f'python-strict + {version}: {len(rows)} outcomes; {len(accepted)} canonical matches')


def nist_rows(base):
    # Check pins before parsing. Whole-file counts protect against partial fixtures.
    for line in (base / 'SHA256SUMS').read_text().splitlines():
        expected, filename = line.split()
        actual = hashlib.sha256((base / filename).read_bytes()).hexdigest()
        if actual != expected:
            raise AssertionError(('NIST pin', filename, actual, expected))
    rows = []
    for name, count in [('SHA256ShortMsg.rsp', 65), ('SHA256LongMsg.rsp', 64)]:
        text = (base / name).read_text()
        cases = re.findall(r'Len = (\d+)\s+Msg = ([0-9a-f]+)\s+MD = ([0-9a-f]+)', text)
        if len(cases) != count:
            raise AssertionError((name, 'count', len(cases)))
        for i, (bits, message, digest) in enumerate(cases):
            length = int(bits)
            if length % 8:
                raise AssertionError('not byte-oriented')
            raw = bytes.fromhex(message) if length else b''  # NIST's Len=0 has Msg=00.
            if len(raw) * 8 != length or len(digest) != 64:
                raise AssertionError((name, i, 'length'))
            if hashlib.sha256(raw).hexdigest() != digest:
                raise AssertionError((name, i, 'hashlib positive control'))
            rows.append((f'{name}-{i:03}', raw.hex(), digest))
    text = (base / 'SHA256Monte.rsp').read_text()
    seed_match = re.search(r'Seed = ([0-9a-f]+)', text)
    if seed_match is None:
        raise AssertionError('Monte Carlo seed missing')
    seed = seed_match[1]
    monte = re.findall(r'COUNT = (\d+)\s+MD = ([0-9a-f]+)', text)
    if [int(i) for i, _ in monte] != list(range(100)):
        raise AssertionError('Monte Carlo count')
    # NIST's intermediate transcript independently pins the 3-digest concatenation rule.
    transcript = (base / 'SHA256Monte.txt').read_text()
    intermediate = re.findall(r'M = ([0-9a-f]+)\s+MDi = ([0-9a-f]+)', transcript)
    for message, digest in intermediate:
        if hashlib.sha256(bytes.fromhex(message)).hexdigest() != digest:
            raise AssertionError('Monte transcript')
    current = bytes.fromhex(seed)
    for i, expected in monte:
        a = b = c = current
        for _ in range(1000):
            a, b, c = b, c, hashlib.sha256(a + b + c).digest()
        if c.hex() != expected:
            raise AssertionError(('Monte algorithm', i))
        current = c
    print(f'NIST pins: Short=65 Long=64 Monte=100; transcript={len(intermediate)} matches')
    return rows, seed, monte


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    rows = json_cases()
    if len({(r[0], r[1]) for r in rows}) != len(rows):
        raise AssertionError('duplicate case id')
    crosscheck_jq(rows)
    (out / 'json.tsv').write_text(''.join('\t'.join([g, name, raw.hex(), tag, printed.hex()])
                                         + '\n' for g, name, raw, tag, printed in rows))
    base = Path(__file__).resolve().parent / 'nist'
    nist, seed, monte = nist_rows(base)
    (out / 'nist.tsv').write_text(''.join('\t'.join(r) + '\n' for r in nist))
    (out / 'monte.tsv').write_text('seed\t' + seed + '\n' +
                                 ''.join(i + '\t' + md + '\n' for i, md in monte))
    rng = random.Random(SEED ^ 0x256)
    lengths = [0, 1, 55, 56, 63, 64, 65, 119, 120, 127, 128, 4095, 4096, 1048576]
    lengths += [rng.randrange(16385) for _ in range(128)]
    hash_rows = []
    for i, n in enumerate(lengths):
        raw = rng.randbytes(n)
        path = out / f'hash-input-{i:03}.bin'
        path.write_bytes(raw)
        # External differential oracle, not hashlib or the Lean oracle.
        digest = subprocess.check_output(['sha256sum', '--', str(path)]).split()[0].decode()
        hash_rows.append((f'differential-{i:03}-n{n}', raw.hex(), digest))
        path.unlink()
    (out / 'hash.tsv').write_text(''.join('\t'.join(r) + '\n' for r in hash_rows))
    million = b'a' * 1000000
    expected = 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
    if hashlib.sha256(million).hexdigest() != expected:
        raise AssertionError('million a control')
    counts = Counter(g for g, *_ in rows)
    print('case counts: ' + ' '.join(f'{k}={counts[k]}' for k in sorted(counts)))
    print(f'sha256sum differential={len(hash_rows)}; seed={SEED}; corpus ready: {out}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, AssertionError) as exc:
        print(f'setup: {exc}', file=sys.stderr)
        sys.exit(2)
