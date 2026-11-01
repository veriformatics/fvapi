#!/usr/bin/env python3
"""P6: pinned fva self-audit of controlled fvapi sources, never a delivered-package verdict."""

import argparse
import ctypes
import fcntl
import hashlib
import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Sum of process-tree RSS peaked at 3,077,292,032 B on all four domains (shared mappings count
# per process). 8 GiB = 2.79× headroom; Lake's virtual reservations make RLIMIT_AS unsuitable.
AGGREGATE_MEMORY_BYTES = 8 * 1024**3
WHOLE_TIMEOUT_SECONDS = 1800
AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
STATUSES = {"accept", "reject", "decline", "crash", "timeout"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unique(values, field):
    if not isinstance(values, list) or any(not isinstance(v, str) for v in values) or \
            len(set(values)) != len(values):
        raise ValueError(f"malformed {field}")
    return set(values)


def validate(envelope, rows, profile, capsule):
    """Bind a pinned-version report to the inventory and actual capsule canary inputs."""
    if not isinstance(envelope, dict) or envelope.get("verdict") not in ("pass", "fail"):
        raise ValueError("malformed success output: verdict/envelope")
    if not isinstance(envelope.get("attachments"), dict) or not isinstance(envelope.get("boundary"), list):
        raise ValueError("malformed success output: attachments/boundary")
    report = envelope.get("report")
    issues = envelope.get("issues")
    if not isinstance(report, dict) or not isinstance(issues, list) or \
            any(not isinstance(i, dict) or not isinstance(i.get("tag"), str) or
                not isinstance(i.get("detail"), str) for i in issues):
        raise ValueError("malformed success output: report/issues")
    tags = sorted({i["tag"] for i in issues})
    if envelope["verdict"] != "pass" or issues:
        raise ValueError("non_pass tags=" + ",".join(tags))
    if report.get("built") is not True or report.get("exportOk") is not True or \
            report.get("needsLink") is not False:
        raise ValueError("malformed success output: build/export/subject mode")
    if any(report.get(field) != [] for field in ("flags", "subjectSyntax", "prelude", "links")):
        raise ValueError("malformed success output: flags/syntax/prelude/links")
    claims = report.get("claims")
    if not isinstance(claims, list) or any(not isinstance(c, dict) for c in claims):
        raise ValueError("malformed success output: claims")
    by_name = {c.get("name"): c for c in claims}
    expected = {r["claim"]: r for r in rows}
    if len(by_name) != len(claims) or set(by_name) != set(expected):
        raise ValueError("claim set != inventory")
    declared = {s for r in rows for s in r["audit_subjects"]}
    observed = set()
    for name, claim in by_name.items():
        row = expected[name]
        proofs = claim.get("proofs")
        if claim.get("provenInSpec") is not False or not isinstance(proofs, list) or \
                len(proofs) != 1 or not isinstance(proofs[0], dict) or \
                proofs[0].get("name") != row["proof"]:
            raise ValueError(f"proof identities != inventory for {name}")
        if not unique(proofs[0].get("axioms"), f"{name}.axioms") <= AXIOMS:
            raise ValueError(f"axiom closure for {name}")
        subjects = unique(claim.get("subjects"), f"{name}.subjects")
        if not subjects or subjects != set(row["audit_subjects"]):
            raise ValueError(f"subject identities != inventory for {name}: {sorted(subjects)}")
        observed |= subjects
    if observed != declared:
        raise ValueError("subject identities != inventory domain union")
    budget = rows[0]["reviewed_surface_budget"]
    if report.get("budget") != budget or any(r["reviewed_surface_budget"] != budget for r in rows):
        raise ValueError("reviewed surface budget != inventory")
    modules = report.get("reviewModules")
    if not isinstance(modules, list) or not modules or any(
            not isinstance(m, dict) or not isinstance(m.get("module"), str) or
            m.get("found") is not True or m.get("syntaxExts") != [] or
            type(m.get("codeLines")) is not int or m["codeLines"] < 0 for m in modules):
        raise ValueError("malformed success output: review surface")
    if len({m["module"] for m in modules}) != len(modules):
        raise ValueError("malformed success output: duplicate review module")
    surface = sum(m["codeLines"] for m in modules)
    if surface > budget:
        raise ValueError(f"reviewed surface {surface} > budget {budget}")
    canary_root = capsule / "fva/trust/canaries"
    for field, filename, pin in (("canarySet", "set.tsv", "set_sha256"),
                                 ("known", "known.tsv", "known_sha256")):
        path = canary_root / filename
        if envelope.get(field) != str(path) or sha(path) != profile["canaries"][pin]:
            raise ValueError(f"canary identities: {field} != profile")
    bad = {line.split("\t")[0] for line in (canary_root / "set.tsv").read_text().splitlines()
           if line and not line.startswith("#") and line.split("\t")[2] == "bad"}
    if not bad or unique(report.get("canarySet"), "canarySet") != bad:
        raise ValueError("canary identities: report set != profile")
    known = {tuple(line.split("\t")[:2])
             for line in (canary_root / "known.tsv").read_text().splitlines()
             if line and not line.startswith("#")}
    kernels = {k["name"] for k in profile["kernels"]}
    replay = report.get("replay")
    if not isinstance(replay, list) or len(replay) != len(kernels) or \
            {k.get("kernel") for k in replay if isinstance(k, dict)} != kernels:
        raise ValueError("malformed success output: kernel run set")
    for k in replay:
        lineage = "lean" if k["kernel"] in ("leanchecker", "leanchecker-paranoid", "lean4lean") \
            else "nanoda" if k["kernel"] == "nanoda" else "con"
        if k.get("lineage") != lineage or k.get("status") not in ("accept", "decline"):
            raise ValueError("malformed success output: kernel statuses/lineages")
    if not any(k["lineage"] != "lean" and k["status"] == "accept" for k in replay):
        raise ValueError("malformed success output: no independent acceptance")
    runs = report.get("canaries")
    if not isinstance(runs, list) or len(runs) != len(kernels) * len(bad) or \
            any(not isinstance(c, dict) for c in runs):
        raise ValueError("malformed success output: canary run set")
    pairs = {(c.get("kernel"), c.get("canary")) for c in runs}
    if pairs != {(k, c) for k in kernels for c in bad}:
        raise ValueError("malformed success output: canary coverage")
    for c in runs:
        pair = (c["kernel"], c["canary"])
        if c.get("status") not in STATUSES - {"timeout"} or \
                c.get("knownAccept") is not (pair in known):
            raise ValueError("malformed success output: canary status/known identity")
        if c["status"] == "accept" and (pair not in known or not any(
                other["canary"] == c["canary"] and other["kernel"] != c["kernel"] and
                other["status"] == "reject" for other in runs)):
            raise ValueError("malformed success output: uncovered canary acceptance")
    return {"surface_lines": surface, "surface_budget": budget,
            "review_modules": [{"module": m["module"], "code_lines": m["codeLines"]}
                               for m in modules], "claims": sorted(by_name),
            "subjects": sorted(observed), "canary_runs": len(runs)}


def processes():
    out = {}
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            fields = path.read_text().rsplit(")", 1)[1].split()
            # stat fields after comm: state, ppid, pgrp, session, ... rss.
            out[int(path.parent.name)] = (int(fields[1]), int(fields[2]),
                                           int(fields[21]) * os.sysconf("SC_PAGE_SIZE"))
        except (OSError, ValueError, IndexError):
            continue
    return out


def descendants(table):
    owned = {os.getpid()}
    while True:
        children = {pid for pid, (parent, _, _) in table.items() if parent in owned}
        if children <= owned:
            return owned - {os.getpid()}
        owned |= children


def reap():
    # Subreaper adoption catches timeout/kernel grandchildren even after their leader exits.
    for _ in range(40):
        table = processes()
        owned = descendants(table)
        if not owned:
            return
        for pid in owned:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        while True:
            try:
                child, _ = os.waitpid(-1, os.WNOHANG)
                if child == 0:
                    break
            except ChildProcessError:
                break
        time.sleep(0.025)
    raise ValueError("process_cleanup: audit descendants remain")


def invoke(argv, out, err):
    if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
        raise ValueError("setup: cannot become child subreaper")
    start, peak, cause = time.monotonic(), 0, None
    proc = None

    def interrupted(signum, _frame):
        raise InterruptedError(f"signal_{signum}")

    handlers = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        with out.open("wb") as stdout, err.open("wb") as stderr:
            proc = subprocess.Popen(argv,
                                    cwd=ROOT, stdout=stdout, stderr=stderr,
                                    start_new_session=True)
            while proc.poll() is None:
                table = processes()
                rss = sum(table[p][2] for p in descendants(table))
                peak = max(peak, rss)
                if rss > AGGREGATE_MEMORY_BYTES:
                    cause = "aggregate_memory_exceeded"
                    break
                if time.monotonic() - start > WHOLE_TIMEOUT_SECONDS:
                    cause = "whole_invocation_timeout"
                    break
                time.sleep(0.05)
            if cause:
                proc.kill()
            rc = proc.wait()
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            reap()
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
    return {"rc": rc, "wall_ms": round((time.monotonic() - start) * 1000),
            "peak_aggregate_rss_bytes": peak, "aggregate_ceiling_bytes": AGGREGATE_MEMORY_BYTES,
            "whole_timeout_s": WHOLE_TIMEOUT_SECONDS,
            "cause": cause or ("process_crash" if rc < 0 else None)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capsule", type=Path, required=True)
    parser.add_argument("--domain", help="one inventory domain (default: all)")
    parser.add_argument("--validate-report", type=Path, help="validate a saved envelope only")
    parser.add_argument("--rc", type=int, default=0, help="recorded report process exit code")
    args = parser.parse_args()
    capsule = args.capsule.resolve()
    inventory_path, profile_path = ROOT / "verify/claims.json", ROOT / "verify/profile.json"
    inventory = json.loads(inventory_path.read_text())
    profile = json.loads(profile_path.read_text())
    groups = {}
    for row in inventory["claims"]:
        groups.setdefault(row["domain"], []).append(row)
    if not groups or (args.domain and args.domain not in groups):
        raise ValueError("inventory domain missing")
    if args.validate_report and not args.domain:
        raise ValueError("--validate-report requires --domain")
    cache = ROOT / ".cache/self-audit"
    cache.mkdir(parents=True, exist_ok=True)
    failed = False
    # One named writer for fva's writable canary cache; readers never mutate capsule sources.
    with (capsule.parent / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for domain, rows in groups.items():
            if args.domain and domain != args.domain:
                continue
            stdout, stderr = cache / f"{domain}.stdout", cache / f"{domain}.stderr"
            result = {"domain": domain, "inventory_sha256": sha(inventory_path),
                      "profile_id": profile["id"], "capsule_key": capsule.name,
                      "fva_sha256": sha(capsule / "fva/.lake/build/bin/fva")}
            if args.validate_report:
                stdout = args.validate_report
                result["rc"] = args.rc
                result["cause"] = None
            else:
                limit = math.ceil(max(k["timeout_ms"] for k in profile["kernels"]) / 1000)
                argv = ["lake", "env", str(capsule / "fva/.lake/build/bin/fva"), "trust", str(ROOT),
                        "--spec-module", rows[0]["claim_module"], "--root-module", rows[0]["proof_root"],
                        "--paranoid", "--surface-budget", str(rows[0]["reviewed_surface_budget"]),
                        "--kernel-limit", str(limit), "--canary-limit", str(limit),
                        "--canary-set", str(capsule / "fva/trust/canaries/set.tsv"),
                        "--known", str(capsule / "fva/trust/canaries/known.tsv"), "--json"]
                for subject in sorted({s for r in rows for s in r["audit_subjects"]}):
                    argv += ["--subject", subject]
                result["argv"] = argv
                result.update(invoke(argv, stdout, stderr))
            try:
                if result["cause"]:
                    raise ValueError(result["cause"])
                try:
                    envelope = json.loads(stdout.read_text())
                except (ValueError, OSError) as exc:
                    if result["rc"] != 0:
                        cause = "build_failed" if "[build]" in stdout.read_text() else \
                            f"process_exit_{result['rc']}"
                        raise ValueError(cause) from exc
                    raise ValueError(f"malformed success output: {exc}") from exc
                result.update(validate(envelope, rows, profile, capsule))
                if result["rc"] != 0:
                    raise ValueError(f"process_exit_{result['rc']}")
                result["verdict"] = "pass"
            except (ValueError, KeyError, TypeError) as exc:
                result["verdict"], result["cause"] = "fail", str(exc)
                print(f"self-audit: {domain}: {exc}; stderr={stderr}", file=sys.stderr)
                failed = True
            if not args.validate_report:
                result["stdout_sha256"], result["stderr_sha256"] = sha(stdout), sha(stderr)
                (cache / f"{domain}.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result, separators=(",", ":")))
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print(f"self-audit: {exc}", file=sys.stderr)
        sys.exit(1)
