#!/usr/bin/env python3
"""Sequential exact-site regression plants; evidence only, never mutation credit/currency."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
UNIT = (".lake/build/bin/fvapi-tests",)
HOST = ("python3", "-I", "tests/verify/run.py", "host", "--prebuilt")
PROFILE = ("python3", "-I", "tests/verify/run.py", "profile", "--prebuilt")
USAGE = ("python3", "-I", "tests/verify/run.py", "usage", "--prebuilt")
PLANTS = []


def add(group, identity, file, declaration, old, new, command, needle):
    PLANTS.append({"group": group, "id": file + ":" + identity, "file": file,
                   "decl": declaration, "old": old, "new": new,
                   "command": command, "needle": needle})


def replay(*names):
    argv = ["python3", "-I", "tests/replay/ruled.py", "--prebuilt"]
    for name in names:
        argv.extend(["--case", name])
    return tuple(argv)


D = "Fvapi/Verify/Replay/Decision.lean"
for operator, old, new in [
    ("LCR:1", "timedOut || rc.isNone", "timedOut && rc.isNone"),
    ("LCR:2", "rc.isNone ||", "rc.isNone &&"),
    ("ROR:0", ") ≥ 128", ") > 128"), ("LIT:2", ") ≥ 128", ") ≥ 129"),
]:
    add("decision", "Fvapi.Verify.Replay.comparatorCause:" + operator, D, "comparatorCause",
        old, new, UNIT, "FAIL replay C1:")
add("decision", "Fvapi.Verify.Replay.complete:EQN:0", D, "complete",
    "rs.any (·.kernel == k)", "rs.any (·.kernel != k)", UNIT, "FAIL replay Tcoverage:")
for suffix, old, new in [
    ("0", 'causes ++ ["challenge_mismatch"]', '["challenge_mismatch"]'),
    ("4", 'causes ++ ["export_failed"]', '["export_failed"]'),
    ("8", "causes ++ [cause]", "[cause]"),
    ("16", 'causes ++ ["kernel_rejected"]', '["kernel_rejected"]'),
    ("24", 'causes ++ ["kernel_timeout"]', '["kernel_timeout"]'),
    ("28", 'causes ++ ["unnamed_unsupported"]', '["unnamed_unsupported"]'),
]:
    add("decision", "Fvapi.Verify.Replay.judge:LST:" + suffix, D, "judge", old, new,
        UNIT, "FAIL replay C2:")

P = "Fvapi/Verify/Profile.lean"
for identity, declaration, old, new, needle in [
    ("keys:EQN:0", "keys", "ms.any (·.1 == k)", "ms.any (·.1 != k)", "profile C2:"),
    ("nat:LIT:0", "nat", "0 ≤ n", "1 ≤ n", "profile C1:"),
    ("nat:ROR:0", "nat", "0 ≤ n", "0 < n", "profile C1:"),
    ("sha256:LCR:0", "sha256", "s.length == 64 &&", "s.length == 64 ||", "profile C2:"),
    ("sha256:LCR:2", "sha256", "'a' ≤ c && c ≤ 'f'", "'a' ≤ c || c ≤ 'f'", "profile C2:"),
    ("canaries:LCR:2", "canaries", "'a' ≤ c && c ≤ 'f'", "'a' ≤ c || c ≤ 'f'", "profile S9:"),
    ("mapped:GME:0", "mapped", '"reject" => pure .reject', '"reject" => pure .accept', "profile C4:"),
    ("mapped:GME:1", "mapped", '"decline" => pure .decline', '"decline" => pure .reject', "profile C4:"),
    ("templateHasExport:BOOL:0", "templateHasExport", "| _ => false", "| _ => true", "profile C3:"),
    ("templatesHaveExport:BOOL:0", "templatesHaveExport", "| [] => false", "| [] => true", "profile C3:"),
    ("templatesHaveExport:LCR:0", "templatesHaveExport", " || ", " && ", "profile C3:"),
    ("kernel:EQN:0", "kernel", 'key == "decline_pattern"', 'key != "decline_pattern"', "profile S19:"),
    ("kernel:ROR:0", "kernel", 'timeoutMs > 0', 'timeoutMs ≥ 0', "profile C1:"),
    ("statusMap:ROR:0", "statusMap", 'code ≤ 128', 'code < 128', "profile T128:"),
    ("statusMap:LIT:0", "statusMap", 'code ≤ 128', 'code ≤ 129', "profile T128:"),
    ("statusMap:LCR:0", "statusMap", 'code ≤ 128 &&', 'code ≤ 128 ||', "profile T128:"),
    ("positive:ROR:0", "positive", 'n > 0', 'n ≥ 0', "profile C1:"),
]:
    add("profile", "Fvapi.Verify.Read." + identity, P, declaration, old, new, UNIT, "FAIL " + needle)

H = "Fvapi/Verify/Host.lean"
for suffix, old, new in [
    ("GIB:0", 'if rel.isEmpty then e.fileName else rel ++ "/" ++ e.fileName',
     'if rel.isEmpty then rel ++ "/" ++ e.fileName else e.fileName'),
    ("LST:0", 'rel ++ "/"', '"/"'),
    ("LST:1", 'rel ++ "/"', '"/" ++ rel'),
    ("LST:2", 'rel ++ "/" ++ e.fileName', 'e.fileName'),
    ("LST:3", 'rel ++ "/" ++ e.fileName', 'e.fileName ++ rel ++ "/"'),
    ("LST:4", 'rel ++ "/"', 'rel'),
    ("LST:5", 'rel ++ "/" ++ e.fileName', 'rel ++ "/"'),
    ("GME:0", "| .file => acc := acc.push r", "| .file => acc ← walk r acc"),
    ("GME:1", "| _ => pure ()", "| _ => acc := acc.push r"),
]:
    add("host", "Fvapi.Verify.regularFiles:" + suffix, H, "regularFiles", old, new,
        HOST, "assertion: host: Ttree")
for suffix, old, new in [
    ("LIT:1", '(afterDef "primitiveTargets").drop 1', '(afterDef "primitiveTargets").drop 2'),
    ("LIT:3", '(l.splitOn "``").drop 1', '(l.splitOn "``").drop 0'),
]:
    add("host", "Fvapi.Verify.comparatorTargets:" + suffix, H, "comparatorTargets", old, new,
        HOST, "assertion: host: Ttargets")
for suffix, old, new, needle in [
    ("LST:2", 'problems ++ [⟨"toolchain", s!"{p.toolchain} != installed {installed}"⟩]',
     'problems', "Ttoolchain"),
    ("LST:3", '[⟨"toolchain", s!"{p.toolchain} != installed {installed}"⟩]', '[]', "Ttoolchain"),
    ("LST:13", 'problems ++ [⟨"comparator.source",', '[⟨"comparator.source",', "Hdiag missing source"),
    ("LST:17", 'problems ++\n        [⟨"comparator.source_sha256",',
     '[⟨"comparator.source_sha256",', "Hdiag source digest"),
    ("LST:21", 'problems ++\n        [⟨"comparator.targets",', '[⟨"comparator.targets",', "Hdiag target set"),
    ("EQN:2", "got != p.runtimeSha256", "got == p.runtimeSha256", "Tmanifest"),
    ("LST:25", 'problems ++ [⟨"runtime.sha256",', '[⟨"runtime.sha256",', "Hdiag runtime"),
    ("LST:27", 'problems ++ [⟨"runtime.sha256", s!"{got} != profile {p.runtimeSha256}"⟩]',
     'problems', "Tmanifest runtime mismatch"),
    ("LST:28", '[⟨"runtime.sha256", s!"{got} != profile {p.runtimeSha256}"⟩]',
     '[]', "Tmanifest runtime mismatch"),
]:
    add("host", "Fvapi.Verify.checkHost:" + suffix, H, "checkHost", old, new,
        HOST, "assertion: host: " + needle)

V = "Fvapi/Dev.lean"
for identity, declaration, old, new, driver, needle in [
    ("profile:BOOL:0", "profile", '("valid", .bool false)', '("valid", .bool true)', PROFILE, "truthful present valid"),
    ("profile:LST:3", "profile", '("profile invalid:\\n" ++ "\\n".intercalate (problems.map fun p => s!"  {p.field}: {p.detail}"))',
     '"profile invalid:\\n"', PROFILE, "diagnostic must name version"),
    ("profile:GME:3", "profile", '.service => "service"', '.service => "caller"', PROFILE, "truthful requested scope"),
    ("profile:GIB:0", "profile", 'if runtime then "checked" else "not_checked"',
     'if runtime then "not_checked" else "checked"', PROFILE, "truthful performed runtime check"),
    ("replayFlags:LCR:0", "replayFlags", '.contains key &&', '.contains key ||', USAGE, "usage ['replay', '--package'"),
    ("replayFlags:LCR:1", "replayFlags", '!value.startsWith "--" &&', '!value.startsWith "--" ||', USAGE, "usage ['replay', '--package'"),
    ("run:LIT:0", "run", '| none => IO.eprint usage; return 2', '| none => IO.eprint usage; return 3', USAGE, "usage ['replay']"),
    ("run:GME:5", "run", 'flags file scope true json more', 'flags file (some .service) runtime json more', PROFILE, "runtime"),
    ("run:BOOL:0", "run", 'flags file scope true json more', 'flags file scope false json more', PROFILE, "runtime"),
    ("run:BOOL:2", "run", 'flags none none false false rest', 'flags none none true false rest', PROFILE, "runtime"),
    ("run:LIT:1", "run", '| none => do IO.eprint usage; return 2', '| none => do IO.eprint usage; return 3', USAGE, "usage ['profile'"),
    ("run:LIT:2", "run", '| _ => do IO.eprint usage; return 2', '| _ => do IO.eprint usage; return 3', USAGE, "usage ['not-a-command']"),
]:
    add("dev", "Fvapi.Dev." + identity, V, declaration, old, new, driver, needle)
add("dev-relative", "Fvapi.Dev.run:GIB:0", V, "run", "if p.isAbsolute then p else cwd / p",
    "if p.isAbsolute then cwd / p else p", ("python3", "-I", "tests/replay/bindings.py", "relative", "--prebuilt"),
    "absolute and relative replay must both succeed")

R = "Fvapi/Verify/Regex.lean"
for identity, declaration, old, new, needle in [
    ("edge:LST:1", "edge", "· ++ [e]", "[e] ++ ·", "regex G1:"),
    ("escaped:GME:0", "escaped", r"'r' => '\r'", r"'r' => '\n'", "regex Rescape:"),
    ("escaped:GME:1", "escaped", r"'t' => '\t'", r"'t' => '\r'", "regex Rescape:"),
    ("classChars:BOOL:0", "classChars", "(escaped c, true)", "(escaped c, false)", "regex Rescape:"),
    ("ranges:ROR:0", "ranges", "if a > b", "if a ≥ b", "regex Rescape:"),
    ("quantifier:GME:0", "quantifier", "'+' :: rest => (edge g to (.epsilon source back), rest)",
     "'+' :: rest => (edge (edge g source (.epsilon to .plain)) to (.epsilon source back), rest)", "regex S6:"),
    ("compileLoop:AOR:0", "compileLoop", "tail.length + 1", "tail.length - 1", "regex S7/S10:"),
    ("compileLoop:AOR:1", "compileLoop", "cs.length + 1", "cs.length - 1", "regex S7/S10:"),
    ("closure:BOOL:2", "closure", "seen := seen.set! node true", "seen := seen.set! node false", "regex"),
    ("closure:BOOL:4", "closure", "seen := seen.set! target true", "seen := seen.set! target false", "regex"),
    ("matchLine:AOR:0", "matchLine", "chars.size + 1", "chars.size - 1", "regex S21/S22:"),
    ("matchLine:LIT:0", "matchLine", "chars.size + 1", "chars.size + 0", "regex S21/S22:"),
]:
    prefix = "Fvapi.Verify.Regex." if declaration == "matchLine" else "_private.0.Fvapi.Verify.Regex."
    argv = (("python3", "-I", "tests/verify/regex-oracle.py", "--prebuilt")
            if declaration == "closure" else UNIT)
    diagnostic = "assertion: regex-oracle:" if declaration == "closure" else "FAIL " + needle
    add("regex", prefix + identity, R, declaration, old, new, argv, diagnostic)


Q = "Fvapi/Verify/Replay.lean"
for group, identity, declaration, old, new, cases, needle in [
    ("outer", "run:LIT:0", "run", "return 1", "return 0", ["outer"], "one-shot stdout fault"),
    ("exports", "digestMatches:BOOL:0", "digestMatches", "return false", "return true",
     ["missing-export"], "missing-export"),
    ("exports", "runClaim:BOOL:1", "runClaim", 'facts := { exportsOk := false }, diagnostics := ["empty export"]',
     'facts := { exportsOk := true }, diagnostics := ["empty export"]', ["empty-challenge"], "empty-challenge"),
    ("exports", "runClaim:BOOL:2", "runClaim", 'exportsOk := false } }\n  if cause.isSome',
     'exportsOk := true } }\n  if cause.isSome', ["post-comparator"], "post-comparator"),
    ("exports", "runClaim:BOOL:3", "runClaim", 'exportsOk := false } }\n  progress.get',
     'exportsOk := true } }\n  progress.get', ["post-kernel"], "post-kernel"),
    ("exports", "runClaim:GIB:0", "runClaim", 'if comp.ok then "accept" else\n      if comp.timedOut then "timeout" else "error"',
     'if comp.ok then (if comp.timedOut then "timeout" else "error") else "accept"', ["valid"], "valid"),
    ("exports", "runClaim:GIB:1", "runClaim", 'if comp.timedOut then "timeout" else "error"',
     'if comp.timedOut then "error" else "timeout"', ["comparator-error"], "comparator-error"),
    ("exports", "runClaim:LCR:0", "runClaim", "c.ok && s.ok", "c.ok || s.ok",
     ["nonzero-challenge"], "nonzero-challenge"),
    ("exports", "runClaim:LCR:1", "runClaim", '(← c.stdoutPath.metadata).byteSize == 0 ||',
     '(← c.stdoutPath.metadata).byteSize == 0 &&', ["empty-challenge"], "empty-challenge"),
    ("exports", "runClaim:LCR:2", "runClaim", '(← digestMatches c.stdoutPath challengeHash) &&',
     '(← digestMatches c.stdoutPath challengeHash) ||', ["post-comparator"], "post-comparator"),
    ("exports", "runClaim:LCR:3", "runClaim", '(← digestMatches s.stdoutPath solutionHash) &&',
     '(← digestMatches s.stdoutPath solutionHash) ||', ["post-kernel"], "post-kernel"),
    ("exports", "runClaim:LIT:0", "runClaim", '(← c.stdoutPath.metadata).byteSize == 0',
     '(← c.stdoutPath.metadata).byteSize == 1', ["empty-challenge"], "empty-challenge"),
    ("exports", "runClaim:LIT:1", "runClaim", '(← s.stdoutPath.metadata).byteSize == 0',
     '(← s.stdoutPath.metadata).byteSize == 1', ["empty-solution"], "empty-solution"),
    ("exports", "runClaim:LST:4", "runClaim", '[claim.proof] ++ opts.axioms',
     'opts.axioms ++ [claim.proof]', ["valid"], "export argv"),
    ("exports", "runClaim:LST:6", "runClaim", '[claim.proof] ++ opts.axioms ++ p.comparatorTargets',
     'p.comparatorTargets ++ [claim.proof] ++ opts.axioms', ["valid"], "export argv"),
    ("late", "runClaim:LST:15", "runClaim", '["kernel_identity_mismatch"]', '[]', ["late-pin"], "late-pin"),
    ("late", "runClaim:LST:21", "runClaim", 'record.facts.setupCauses ++ result.cause.toList',
     'result.cause.toList', ["earlier-unnamed"], "earlier-unnamed"),
    ("late", "runKernel:LST:0", "runKernel", 'k.id.name ++ ".json"', '".json"',
     ["two-configs"], "two-configs"),
    ("freeze", "stillFrozen:BOOL:0", "stillFrozen", 'catch _ => pure false', 'catch _ => pure true',
     ["challenge-unreadable"], "challenge-unreadable"),
    ("freeze", "executeWith:BOOL:1", "executeWith", 'stillFrozen opts.expectedSource frozen true) &&\n      (← stillFrozen challenge',
     'stillFrozen opts.expectedSource frozen false) &&\n      (← stillFrozen challenge', ["build-source-add"], "build-source-add"),
    ("freeze", "executeWith:BOOL:4", "executeWith", 'let inputsOk := (← stillFrozen opts.expectedSource frozen true)',
     'let inputsOk := (← stillFrozen opts.expectedSource frozen false)', ["source-add"], "source-add"),
    ("freeze", "executeWith:LCR:2", "executeWith", 'stillFrozen opts.expectedSource frozen true) &&\n      (← stillFrozen challenge',
     'stillFrozen opts.expectedSource frozen true) ||\n      (← stillFrozen challenge', ["build-source-byte"], "build-source-byte"),
    ("freeze", "executeWith:LCR:3", "executeWith", 'stillFrozen opts.expectedSource frozen true) &&\n    (← stillFrozen challenge',
     'stillFrozen opts.expectedSource frozen true) ||\n    (← stillFrozen challenge', ["source-byte", "challenge-byte"], "source-byte"),
    ("exports", "executeWith:BOOL:3", "executeWith", 'record.facts with exportsOk := false',
     'record.facts with exportsOk := true', ["export-io"], "export-io"),
    ("runtime", "executeWith:BOOL:0", "executeWith", 'checkHost pre p false', 'checkHost pre p true',
     ["runtime-once"], "runtime-once"),
    ("caps", "executeWith:LCR:0", "executeWith", 'p.exportMs > 0 &&', 'p.exportMs > 0 ||',
     ["zero-export_ms"], "zero-export_ms"),
    ("caps", "executeWith:LCR:1", "executeWith", 'p.comparatorMs > 0 &&', 'p.comparatorMs > 0 ||',
     ["zero-comparator_ms"], "zero-comparator_ms"),
    ("caps", "executeWith:ROR:0", "executeWith", 'p.exportMs > 0', 'p.exportMs ≥ 0', ["zero-export_ms"], "zero-export_ms"),
    ("caps", "executeWith:ROR:1", "executeWith", 'p.comparatorMs > 0', 'p.comparatorMs ≥ 0', ["zero-comparator_ms"], "zero-comparator_ms"),
    ("caps", "executeWith:ROR:2", "executeWith", 'p.memoryBytes > 0', 'p.memoryBytes ≥ 0', ["zero-memory_bytes"], "zero-memory_bytes"),
    ("caps", "executeWith:LIT:0", "executeWith", 'p.exportMs > 0', 'p.exportMs > 1', ["one-export_ms"], "one-export_ms"),
    ("caps", "executeWith:LIT:1", "executeWith", 'p.comparatorMs > 0', 'p.comparatorMs > 1', ["one-comparator_ms"], "one-comparator_ms"),
    ("caps", "executeWith:LIT:2", "executeWith", 'p.memoryBytes > 0', 'p.memoryBytes > 1', ["one-memory_bytes"], "one-memory_bytes"),
]:
    namespace = "Fvapi.Verify.Replay." if declaration == "run" else "_private.0.Fvapi.Verify.Replay."
    add("replay-" + group, namespace + identity, Q, declaration, old, new, replay(*cases), needle)

I = "Fvapi/Verify/Replay/Input.lean"
for identity, declaration, old, new, cases, needle in [
    ("safeName:EQN:0", "safeName", "c == '_'", "c != '_'", ["name-underscore"], "name-underscore"),
    ("safeName:EQN:1", "safeName", r"c == '\''", r"c != '\''", ["name-prime"], "name-prime"),
    ("safeName:LCR:3", "safeName", r"c == '_' || c == '\''", r"c == '_' && c == '\''",
     ["name-underscore"], "name-underscore"),
    ("snapshot:LCR:0", "snapshot", 'rel.startsWith "FvapiProof/" ||', 'rel.startsWith "FvapiProof/" &&',
     ["proof-input"], "proof-input"),
    ("unchanged:BOOL:0", "unchanged", 'if exact && (← sourceFiles root) != frozen.files.map (·.1) then return false',
     'if exact && (← sourceFiles root) != frozen.files.map (·.1) then return true', ["freeze-set"], "added path never hides"),
]:
    add("replay-input", "Fvapi.Verify.Replay." + identity, I, declaration, old, new, replay(*cases), needle)

O = "Fvapi/Verify/Replay/Process.lean"
for identity, declaration, old, new, case, needle in [
    ("seconds:LIT:0", "seconds", 'ms / 1000', 'ms / 1001', "deadline", "deadline"),
    ("seconds:LIT:1", "seconds", '(3 -', '(4 -', "deadline", "deadline"),
    ("seconds:LIT:2", "seconds", '(toString (ms % 1000))', '(toString (ms % 1001))', "deadline", "deadline"),
    ("seconds:LIT:3", "seconds", 's!"{ms % 1000}s"', 's!"{ms % 1001}s"', "deadline", "deadline"),
    ("seconds:LST:0", "seconds", '''s!"{ms / 1000}.{String.ofList (List.replicate (3 - (toString (ms % 1000)).length) '0')}" ++
    s!"{ms % 1000}s"''', 's!"{ms % 1000}s"', "deadline", "deadline"),
    ("reapGroup:LIT:1", "reapGroup", 'pid > 1', 'pid > 2', "pgid2", "authentic pgid2"),
    ("signalGroup:BOOL:0", "signalGroup", 'then return true', 'then return false', "reap-wait", "reaper waits"),
]:
    argv = ("python3", "-I", "tests/replay/process-controls.py", case, "--prebuilt")
    add("replay-process", "_private.0.Fvapi.Verify.Replay." + identity, O, declaration, old, new, argv, needle)


def scoped(text, declaration):
    pattern = r"(?m)^(?:(?:private|partial) )*def " + re.escape(declaration) + r"\b"
    hits = list(re.finditer(pattern, text))
    if len(hits) != 1:
        raise RuntimeError(f"declaration anchor {declaration}: {len(hits)}")
    first = hits[0].start()
    tail = re.search(r"(?m)^(?:(?:private|partial) )*def |^end\b", text[hits[0].end():])
    last = hits[0].end() + tail.start() if tail else len(text)
    return first, last


def command(argv):
    return subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)


def build(targets):
    result = command(["lake", "build", *targets])
    if result.returncode:
        raise RuntimeError("plant build/setup (not an assertion): " + result.stdout + result.stderr)


def read_rulings(path):
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("rulings"), list):
        raise RuntimeError("plant ruling schema")
    result = {}
    known = {p["id"] for p in PLANTS}
    for row in value["rulings"]:
        if (not isinstance(row, dict) or row.get("id") not in known or row["id"] in result or
                not re.fullmatch(r"[0-9a-f]{64}", row.get("source_sha256", "")) or
                not row.get("reason") or not row.get("reviewer") or not row.get("contract")):
            raise RuntimeError("plant ruling identity/authority")
        result[row["id"]] = row
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("group", choices=sorted({p["group"] for p in PLANTS}))
    parser.add_argument("--id", action="append")
    parser.add_argument("--rulings", type=Path, default=ROOT / "tests/verify/plant-rulings.json")
    args = parser.parse_args()
    rulings = read_rulings(args.rulings)
    plants = [p for p in PLANTS if p["group"] == args.group and
              (not args.id or any(p["id"].endswith(identity) for identity in args.id))]
    if not plants:
        raise RuntimeError("empty exact-site selection")
    targets = ["fvapi-tests"] if args.group in {"decision", "profile", "regex"} else ["fvapi"]
    if args.group == "host":
        targets.append("fvapi-tests-host")
    if args.group == "regex":
        targets.append("fvapi-tests-regex")
    if args.group.startswith("replay-"):
        targets = ["fvapi-tests-replay"] if args.group == "replay-process" else ["fvapi", "fvapi-tests-replay"]
    commands = sorted({tuple(p["command"]) for p in plants})
    build(targets)
    for argv in commands:
        control = command(argv)
        if control.returncode:
            raise RuntimeError("unmutated control not green: " + control.stdout + control.stderr)
    failures = 0
    ruled = 0
    with tempfile.TemporaryDirectory(prefix="ruled-plants-", dir=ROOT / ".lake") as directory:
        for index, p in enumerate(plants):
            path = ROOT / p["file"]
            original = path.read_bytes()
            saved = Path(directory) / str(index)
            saved.write_bytes(original)
            text = original.decode()
            first, last = scoped(text, p["decl"])
            region = text[first:last]
            if region.count(p["old"]) != 1:
                raise RuntimeError("site anchor not unique: " + p["id"])
            changed = text[:first] + region.replace(p["old"], p["new"]) + text[last:]
            try:
                path.write_text(changed)
                build(targets)
                result = command(p["command"])
                output = result.stdout + result.stderr
                if tuple(p["command"]) == UNIT:
                    red = (0 < result.returncode < 128 and p["needle"] in output and
                           any(line.startswith("tests:") for line in output.splitlines()))
                else:
                    red = result.returncode == 1 and any(
                        line.startswith("assertion:") and p["needle"] in line
                        for line in output.splitlines())
                matches = [line for line in output.splitlines() if p["needle"] in line][:2]
                source_hash = hashlib.sha256(original).hexdigest()
                ruling = rulings.get(p["id"])
                accepted = (not red and result.returncode == 0 and ruling is not None and
                            ruling["source_sha256"] == source_hash)
                print(json.dumps({"kind": "plant evidence, no mutation credit", "id": p["id"],
                                  "baseline_sha256": source_hash,
                                  "old": p["old"], "new": p["new"], "command": p["command"],
                                  "rc": result.returncode, "assertion_red": red, "matches": matches,
                                  "ruling": ruling if accepted else None}), flush=True)
                if accepted and ruling is not None:
                    ruled += 1
                    print("PLANT RULED:", p["id"], ruling["reason"], flush=True)
                elif not red or ruling is not None:
                    failures += 1
                    print("PLANT UNDECIDED/RULING CONTRADICTION:", p["id"], output[-3000:], flush=True)
            finally:
                path.write_bytes(original)
                restored = command(["cmp", str(path), str(saved)])
                if restored.returncode:
                    raise RuntimeError("byte restoration failed: " + p["id"])
                print("RESTORED cmp=0", p["id"], flush=True)
    build(targets)
    for argv in commands:
        restored = command(argv)
        if restored.returncode:
            raise RuntimeError("restored control not green: " + restored.stdout + restored.stderr)
    print(f"ruled-plants {args.group}: control0/restored0, sites={len(plants)}, "
          f"ruled={ruled}, undecided={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, TypeError, ValueError, subprocess.SubprocessError) as error:
        print(f"setup: ruled-plants: {error}", file=sys.stderr)
        sys.exit(2)
