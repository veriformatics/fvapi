#!/usr/bin/env -S python3 -I
"""Contract-owned fixture materializer; no fvapi implementation imports."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

KERNELS = ["leanchecker", "leanchecker-paranoid", "lean4lean", "nanoda", "con-leche", "con-ron"]
CLAIM: dict[str, Any] = {
    "id": "u2.tiny", "domain": "Tiny", "spec_module": "FvapiSpec.Tiny",
    "claim_module": "FvapiSelf.Tiny", "claim": "FvapiSelf.Tiny.Correct",
    "proof": "FvapiProof.Tiny.correct", "proof_module": "FvapiProof.Tiny",
    "proof_root": "FvapiProofs", "audit_subjects": ["Fvapi.Subject"],
    "reviewed_surface_budget": 100, "expected_snapshot": "",
    "shipped_call_paths": ["Fvapi.Subject.double"],
}
LAKEFILE = """import Lake
open Lake DSL
package u2Fixture
@[default_target] lean_lib Fvapi
lean_lib FvapiSpec
lean_lib FvapiSelf
lean_lib FvapiProof
lean_lib FvapiProofs
lean_exe fixture where
  root := `Main
"""
SOURCES = {
    "lakefile.lean": LAKEFILE,
    # F1: Lake's root manifest is an input, even when there are no dependencies.
    "lake-manifest.json": '{"fixedToolchain":false,"lakeDir":".lake","name":"u2Fixture","packages":[],"packagesDir":".lake/packages","version":"1.3.0"}\n',
    "Fvapi.lean": "import Fvapi.Subject\n",
    "Main.lean": "import Fvapi\ndef main : IO Unit := pure ()\n",
    "Fvapi/Subject.lean": "namespace Fvapi.Subject\ndef double (n : Nat) : Nat := n + n\nend Fvapi.Subject\n",
    "FvapiSpec/Tiny.lean": "import Fvapi.Subject\nnamespace FvapiSpec.Tiny\ndef law (n : Nat) : Prop := Fvapi.Subject.double n = n + n\nend FvapiSpec.Tiny\n",
    "FvapiSelf/Tiny.lean": "import FvapiSpec.Tiny\nnamespace FvapiSelf.Tiny\ndef Correct : Prop := ∀ n : Nat, FvapiSpec.Tiny.law n\nend FvapiSelf.Tiny\n",
    "FvapiProof/Tiny.lean": "import FvapiSelf.Tiny\nnamespace FvapiProof.Tiny\ntheorem correct : FvapiSelf.Tiny.Correct := by intro n; rfl\nend FvapiProof.Tiny\n",
    "FvapiProofs.lean": "import FvapiProof.Tiny\n",
}


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    write(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def canonical(path):
    result = subprocess.run(["jq", "-S", "-c", "del(.id)", str(path)], check=True, capture_output=True)
    assert result.stdout.endswith(b"\n")
    return result.stdout[:-1]


def profile_id(path, value):
    dump(path, value)
    value["id"] = "sha256:" + hashlib.sha256(canonical(path)).hexdigest()
    dump(path, value)


def snapshot(package, target):
    for name in ("lakefile.lean", "lake-manifest.json", "lean-toolchain", "Fvapi.lean", "Main.lean"):
        write(target / name, (package / name).read_text())
    files = {"lake-manifest.json": sha(target / "lake-manifest.json")}
    for tree in ("Fvapi", "FvapiSpec", "FvapiSelf"):
        for source in sorted((package / tree).rglob("*.lean")):
            relative = source.relative_to(package).as_posix()
            write(target / relative, source.read_text())
            files[relative] = sha(source)
    manifest = json.dumps({"version": 1, "files": files}, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    (target / "snapshot.json").write_bytes(manifest)
    return "sha256:" + hashlib.sha256(manifest).hexdigest()


def inventory(package, identity, rows=None):
    claims = copy.deepcopy(rows if rows is not None else [CLAIM])
    for row in claims:
        row["expected_snapshot"] = identity
    data = {"version": 1, "production_roots": ["Fvapi", "Main"], "audit_roots": ["FvapiProofs"], "claims": claims}
    dump(package / "verify/claims.json", data)
    matrix = "| promise | inventory claim | implementation + shipped call paths | proof / test | coverage | residual trust |\n|---|---|---|---|---|---|\n"
    for row in claims:
        matrix += f"| {row['id']} | {row['claim']} | Fvapi.Subject.double | {row['proof']} | proof + test | compiler + runtime |\n"
    write(package / "docs/obligations.md", matrix)
    return data


def prepare(args):
    root = Path(args.root).resolve()
    source = Path(__file__).resolve().parent
    base_path = Path(args.base).resolve()
    base_exists = base_path.is_file()
    # Missing baseline remains an explicit red precondition; fallback only exposes absent CLI handlers.
    base = json.loads((base_path if base_exists else source / "fixtures/profile-golden.json").read_text())
    toolchain = (Path(args.repo) / "lean-toolchain").read_text()
    cases = []

    def make(case_id, group, action="replay", modes=None, names=None, scope="caller", expected=None):
        case_root = root / case_id
        package = case_root / "package"
        expected_root = case_root / "expected-source"
        for name, content in SOURCES.items():
            write(package / name, content)
        write(package / "lean-toolchain", toolchain)
        identity = snapshot(package, expected_root)
        data = inventory(package, identity)
        profile = copy.deepcopy(base)
        profile["kernels"] = []
        profile["canaries"] = copy.deepcopy(profile.get("canaries", {}))
        profile["canaries"]["files"] = {}
        for name in names if names is not None else KERNELS:
            executable = case_root / "bin" / name
            executable.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / "fake-kernel.py", executable)
            executable.chmod(0o755)
            mode = (modes or {}).get(name, "accept")
            profile["kernels"].append({
                "name": name, "executable": str(executable), "sha256": sha(executable),
                "args": [mode, name, "{export}"], "timeout_ms": 400 if mode == "timeout" else 2000,
                "status_map": {"0": "accept", "3": "reject", "4": "decline"},
                "decline_pattern": "^UNSUPPORTED:(.*)$",
            })
        profile_path = case_root / "profile.json"
        profile_id(profile_path, profile)
        item = {"id": case_id, "group": group, "action": action, "scope": scope,
                "root": str(case_root), "package": str(package), "inventory": str(package / "verify/claims.json"),
                "profile": str(profile_path), "snapshot": str(expected_root), "snapshot_id": identity,
                "base_profile_available": base_exists,
                "expected": expected or {"rc": 0, "verdict": "pass", "causes": [], "ran": KERNELS, "exports": True}}
        cases.append(item)
        return item, package, expected_root, profile, data

    def failed(code, **extra):
        return {"rc": "nonzero", "verdict": "fail", "causes": [code], **extra}

    def save_profile(item, profile, rehash=True):
        if rehash:
            profile_id(Path(item["profile"]), profile)
        else:
            dump(Path(item["profile"]), profile)

    # P2: both profile scopes, every admitted independent lineage, omissions/duplicates/extras.
    p2 = [
        ("P2-P01-caller-nanoda", ["leanchecker", "nanoda"], "caller", True),
        ("P2-P02-service-six", KERNELS, "service", True),
        ("P2-P03-empty", [], "caller", False),
        ("P2-P04-default-only", ["leanchecker"], "caller", False),
        ("P2-P05-no-default", ["nanoda", "con-leche"], "caller", False),
        ("P2-P06-lean-lineage", KERNELS[:3], "caller", False),
        ("P2-P07-default-paranoid", KERNELS[:2], "caller", False),
        ("P2-P08-default-port", ["leanchecker", "lean4lean"], "caller", False),
        ("P2-P09-caller-leche", ["leanchecker", "con-leche"], "caller", True),
        ("P2-P10-caller-ron", ["leanchecker", "con-ron"], "caller", True),
        ("P2-P11-service-incomplete", ["leanchecker", "nanoda"], "service", False),
        ("P2-P12-duplicate", ["leanchecker", "nanoda", "nanoda"], "caller", False),
        ("P2-P13-extra", ["leanchecker", "nanoda", "unlisted"], "caller", False),
    ]
    for case_id, names, scope, ok in p2:
        make(case_id, "profile", "profile", names=names, scope=scope,
             expected={"rc": 0 if ok else "nonzero", "valid": ok})
    # Exhaust the closed run-set domain independently of the CLI's validator.
    for mask in range(64):
        names = [name for bit, name in enumerate(KERNELS) if mask & (1 << bit)]
        for scope in ("caller", "service"):
            ok = bool(mask & 1 and mask & 0b111000) if scope == "caller" else mask == 63
            make(f"P2-RS-{mask:02d}-{scope}", "profile", "profile", names=names, scope=scope,
                 expected={"rc": 0 if ok else "nonzero", "valid": ok})
    for suffix, mutate, field in [
        ("version", lambda p: p.update(version=2), "version"),
        ("runtime-missing", lambda p: p.pop("runtime", None), "runtime"),
        ("exporter-hash", lambda p: p["exporter"].update(sha256="0" * 64), "exporter"),
        ("comparator-hash", lambda p: p["comparator"].update(sha256="0" * 64), "comparator"),
        ("comparator-source", lambda p: p["comparator"].update(source_sha256="0" * 64), "source"),
        ("comparator-targets", lambda p: p["comparator"].update(targets=p["comparator"]["targets"] + ["Fixture.forbiddenTarget"]), "targets"),
        ("kernel-hash", lambda p: p["kernels"][0].update(sha256="0" * 64), "sha256"),
        ("caps-missing", lambda p: p.pop("caps", None), "caps"),
    ]:
        item, _, _, profile, _ = make("P2-P14-" + suffix, "profile", "profile", expected={"rc": "nonzero", "valid": False, "field": field})
        mutate(profile)
        save_profile(item, profile)
    item, _, _, profile, _ = make("P2-P15-id-tamper", "profile", "profile", expected={"rc": "nonzero", "valid": False, "field": "id"})
    profile["id"] = "sha256:" + "0" * 64
    save_profile(item, profile, False)
    item, _, _, profile, _ = make("P2-P16-id-reordered-input", "profile", "profile", expected={"rc": 0, "valid": True})
    Path(item["profile"]).write_text(json.dumps(dict(reversed(list(profile.items()))), ensure_ascii=False, indent=4) + "\n")
    item, _, _, profile, _ = make("P2-P17-target-set-order", "profile", "profile", expected={"rc": 0, "valid": True})
    profile["comparator"]["targets"].reverse()
    save_profile(item, profile)

    # P3: valid exports must reach the real comparator before negative binding/axiom verdicts.
    make("P3-R01-valid", "replay")
    mutations = [
        ("P3-R02-sorry", "sorry", "forbidden_axiom"),
        ("P3-R03-weakened", "weak", "challenge_mismatch"),
        ("P3-R05-substituted-dependency", "substitute", "challenge_mismatch"),
        ("P3-R06-custom-axiom", "axiom", "forbidden_axiom"),
    ]
    for case_id, kind, code in mutations:
        _, package, _, _, _ = make(case_id, "replay", expected=failed(code, exports=True, comparator_nonzero=True))
        if kind == "sorry":
            write(package / "FvapiProof/Tiny.lean", SOURCES["FvapiProof/Tiny.lean"].replace("by intro n; rfl", "by sorry"))
        elif kind == "weak":
            write(package / "FvapiSelf/Tiny.lean", SOURCES["FvapiSelf/Tiny.lean"].replace("∀ n : Nat, FvapiSpec.Tiny.law n", "True"))
            write(package / "FvapiProof/Tiny.lean", SOURCES["FvapiProof/Tiny.lean"].replace("by intro n; rfl", "by trivial"))
        elif kind == "substitute":
            write(package / "Fvapi/Subject.lean", SOURCES["Fvapi/Subject.lean"].replace("n + n", "n + n + 1"))
            write(package / "FvapiSpec/Tiny.lean", SOURCES["FvapiSpec/Tiny.lean"].replace("= n + n", "= n + n + 1"))
        else:
            write(package / "FvapiProof/Tiny.lean", "import FvapiSelf.Tiny\nnamespace FvapiProof.Tiny\naxiom backdoor : FvapiSelf.Tiny.Correct\ntheorem correct : FvapiSelf.Tiny.Correct := backdoor\nend FvapiProof.Tiny\n")
    mode_cases = [
        ("P3-R07-reject", "reject", "kernel_rejected", "reject"),
        ("P3-R08-timeout-tree", "timeout", "kernel_timeout", "timeout"),
        ("P3-R09-signal", "signal", "kernel_crashed", "crash"),
        ("P3-R10-unmapped-exit", "unmapped", "kernel_crashed", "crash"),
        ("P3-R13-decline-unmatched", "decline-unmatched", "unnamed_unsupported", None),
        ("P3-R14-decline-empty", "decline-empty", "unnamed_unsupported", None),
        ("P3-R15-decline-space", "decline-space", "unnamed_unsupported", None),
        ("P3-R17-reject-decline-line", "reject-with-decline", "kernel_rejected", "reject"),
    ]
    for case_id, mode, code, status in mode_cases:
        make(case_id, "replay", modes={"con-ron": mode}, expected=failed(code, exports=True, ran=KERNELS, statuses={"con-ron": status} if status else {}, reaped=mode == "timeout", kernel_controls=True))
    modes = {name: "decline-x" for name in KERNELS[3:]}
    make("P3-R11-no-independent", "replay", modes=modes,
         expected=failed("insufficient_independent_kernels", exports=True, ran=KERNELS, statuses={name: "decline" for name in KERNELS[3:]}, kernel_controls=True))
    modes = {name: "decline-x" for name in KERNELS if name not in {"leanchecker", "nanoda"}}
    make("P3-R12-named-declines", "replay", modes=modes,
         expected={"rc": 0, "verdict": "pass", "causes": [], "exports": True, "ran": KERNELS, "statuses": {name: "decline" for name in modes}})
    make("P3-R18-accept-decline-line", "replay", modes={"con-ron": "accept-with-decline"})
    item, _, _, profile, _ = make("P3-R19-missing-kernel", "replay", expected=failed("kernel_missing"))
    Path(profile["kernels"][0]["executable"]).unlink()
    item, _, _, profile, _ = make("P3-R20-kernel-tamper", "replay", expected=failed("kernel_identity_mismatch"))
    with Path(profile["kernels"][0]["executable"]).open("a") as target:
        target.write("\n# planted identity mismatch\n")
    item, _, _, profile, _ = make("P3-R21-profile-id", "replay", expected=failed("profile_mismatch"))
    profile["id"] = "sha256:" + "0" * 64
    save_profile(item, profile, False)
    for case_id, role, code in [("P3-R22-comparator-error", "comparator", "comparator_error"), ("P3-R23-export-error", "exporter", "export_failed")]:
        item, _, _, profile, _ = make(case_id, "replay", expected=failed(code, ran=[role], exports=role == "comparator", comparator_rc=2 if role == "comparator" else None))
        executable = Path(item["root"]) / "bin" / (role + "-fixture")
        shutil.copyfile(source / "fake-kernel.py", executable)
        executable.chmod(0o755)
        profile[role]["executable"] = str(executable)
        profile[role]["sha256"] = sha(executable)
        save_profile(item, profile)
    _, _, expected_root, _, _ = make("P3-R24-snapshot-tamper", "replay", expected=failed("challenge_mismatch", allow_snapshot_change=True))
    with (expected_root / "FvapiSelf/Tiny.lean").open("a") as target:
        target.write("\n-- planted frozen-snapshot byte change\n")
    item, package, expected_root, _, _ = make("P3-R25-build-mutates-snapshot", "replay", expected={"rc": "nonzero", "verdict": "fail", "any_causes": ["challenge_mismatch", "export_failed"], "allow_snapshot_change": True})
    destination = json.dumps(str(expected_root / "FvapiSelf/Tiny.lean"))
    payload = json.dumps(SOURCES["FvapiSelf/Tiny.lean"] + "\n-- solution build changed frozen input\n")
    write(package / "FvapiProof/Tiny.lean", f"import Lean\nimport FvapiSelf.Tiny\nrun_cmd do\n  let _ ← IO.FS.writeFile {destination} {payload}\n  pure ()\n" + SOURCES["FvapiProof/Tiny.lean"].split("\n", 1)[1])
    for case_id, sorried in [("P3-R26-two-one-fail", True), ("P3-R27-two-pass", False)]:
        item, package, expected_root, _, _ = make(case_id, "replay")
        with (package / "FvapiSelf/Tiny.lean").open("a") as target:
            target.write("namespace FvapiSelf.Tiny\ndef Correct2 : Prop := ∀ n : Nat, FvapiSpec.Tiny.law n\nend FvapiSelf.Tiny\n")
        with (package / "FvapiProof/Tiny.lean").open("a") as target:
            target.write("namespace FvapiProof.Tiny\ntheorem correct2 : FvapiSelf.Tiny.Correct2 := by " + ("sorry" if sorried else "intro n; rfl") + "\nend FvapiProof.Tiny\n")
        second = copy.deepcopy(CLAIM)
        second.update(id="u2.tiny.2", claim="FvapiSelf.Tiny.Correct2", proof="FvapiProof.Tiny.correct2")
        identity = snapshot(package, expected_root)
        item["snapshot_id"] = identity
        inventory(package, identity, [CLAIM, second])
        item["expected"] = {"rc": "nonzero" if sorried else 0, "verdict": "mixed" if sorried else "pass", "causes": ["forbidden_axiom"] if sorried else [], "records": 2, "exports": True, "ran": KERNELS}

    # P4: elaboration-sensitive failures; every fixture remains a compilable Lake package.
    variants = ["empty", "missing-row", "duplicate-id", "duplicate-claim", "wrong-proof-type", "def-proof", "inferred-prop", "aliased-prop", "open-claim", "universe-claim", "unresolved-call", "audit-call", "unresolved-subject", "missing-proof", "aggregate-omission", "production-spec-import", "production-proof-import", "transitive-self-import", "matrix-missing"]
    for number, kind in enumerate(variants, 1):
        item, package, expected_root, _, data = make(f"P4-I{number:02d}-{kind}", "inventory", expected={"rc": "nonzero", "structured_failure": True, "ran": []})
        rows = data["claims"]
        if kind == "empty":
            rows.clear()
        elif kind in {"missing-row", "duplicate-id"}:
            with (package / "FvapiSelf/Tiny.lean").open("a") as target:
                target.write("namespace FvapiSelf.Tiny\ndef Correct2 : Prop := ∀ n : Nat, FvapiSpec.Tiny.law n\nend FvapiSelf.Tiny\n")
            with (package / "FvapiProof/Tiny.lean").open("a") as target:
                target.write("namespace FvapiProof.Tiny\ntheorem correct2 : FvapiSelf.Tiny.Correct2 := by intro n; rfl\nend FvapiProof.Tiny\n")
            second = copy.deepcopy(CLAIM)
            second.update(id="u2.tiny.2" if kind == "missing-row" else CLAIM["id"], claim="FvapiSelf.Tiny.Correct2", proof="FvapiProof.Tiny.correct2")
            if kind == "missing-row":
                rows[:] = [second]
            else:
                rows.append(second)
        elif kind == "duplicate-claim":
            other = copy.deepcopy(rows[0]); other["id"] += ".duplicate"; rows.append(other)
        elif kind == "wrong-proof-type":
            write(package / "FvapiProof/Tiny.lean", SOURCES["FvapiProof/Tiny.lean"].replace("FvapiSelf.Tiny.Correct := by intro n; rfl", "True := by trivial"))
        elif kind == "def-proof":
            write(package / "FvapiProof/Tiny.lean", SOURCES["FvapiProof/Tiny.lean"].replace("theorem correct", "def correct"))
        elif kind in {"inferred-prop", "aliased-prop", "open-claim", "universe-claim"}:
            extra = {
                "inferred-prop": "def Inferred := (True : Prop)\n",
                "aliased-prop": "abbrev PropAlias := Prop\ndef Aliased : PropAlias := True\n",
                "open-claim": "def OpenClaim (n : Nat) : Prop := n = n\n",
                "universe-claim": "universe u\ndef UniverseClaim : Prop := ∀ (α : Type u) (x : α), x = x\n",
            }[kind]
            with (package / "FvapiSelf/Tiny.lean").open("a") as target:
                target.write("namespace FvapiSelf.Tiny\n" + extra + "end FvapiSelf.Tiny\n")
            if kind == "universe-claim":
                with (package / "FvapiProof/Tiny.lean").open("a") as target:
                    target.write("namespace FvapiProof.Tiny\ntheorem correctUniverse : FvapiSelf.Tiny.UniverseClaim := by intro α x; rfl\nend FvapiProof.Tiny\n")
                extra_row = copy.deepcopy(CLAIM)
                extra_row.update(id="u2.universe", claim="FvapiSelf.Tiny.UniverseClaim", proof="FvapiProof.Tiny.correctUniverse")
                rows.append(extra_row)
        elif kind == "unresolved-call":
            rows[0]["shipped_call_paths"] = ["Fvapi.Subject.missing"]
        elif kind == "audit-call":
            rows[0]["shipped_call_paths"] = ["FvapiProof.Tiny.correct"]
        elif kind == "unresolved-subject":
            rows[0]["audit_subjects"] = ["Fvapi.Missing"]
        elif kind == "missing-proof":
            write(package / "FvapiProof/Tiny.lean", "import FvapiSelf.Tiny\n")
        elif kind == "aggregate-omission":
            write(package / "FvapiProofs.lean", "import Std\n")
        elif kind == "production-spec-import":
            write(package / "FvapiSpec/Support.lean", "def fixtureAux : Nat := 0\n")
            write(package / "Fvapi/Subject.lean", "import FvapiSpec.Support\n" + SOURCES["Fvapi/Subject.lean"])
        elif kind == "production-proof-import":
            write(package / "Fvapi.lean", "import Fvapi.Subject\nimport FvapiProof.Tiny\n")
        elif kind == "transitive-self-import":
            write(package / "FvapiSelf/Other.lean", "namespace FvapiSelf.Other\ndef Correct : Prop := True\nend FvapiSelf.Other\n")
            write(package / "FvapiSpec/Bridge.lean", "import FvapiSelf.Other\n")
            write(package / "FvapiSelf/Tiny.lean", "import FvapiSpec.Bridge\n" + SOURCES["FvapiSelf/Tiny.lean"])
            write(package / "FvapiProof/Other.lean", "import FvapiSelf.Other\nnamespace FvapiProof.Other\ntheorem correct : FvapiSelf.Other.Correct := by trivial\nend FvapiProof.Other\n")
            write(package / "FvapiProofs.lean", "import FvapiProof.Tiny\nimport FvapiProof.Other\n")
            other = copy.deepcopy(CLAIM)
            other.update(id="u2.other", domain="Other", spec_module="FvapiSpec.Other", claim_module="FvapiSelf.Other", claim="FvapiSelf.Other.Correct", proof="FvapiProof.Other.correct", proof_module="FvapiProof.Other")
            write(package / "FvapiSpec/Other.lean", "def otherHelper : Nat := 0\n")
            rows.append(other)
        identity = snapshot(package, expected_root)
        item["snapshot_id"] = identity
        inventory(package, identity, rows)
        if kind == "matrix-missing":
            write(package / "docs/obligations.md", "| promise | inventory claim |\n|---|---|\n")
    dump(root / "cases.json", cases)
    print(json.dumps({"cases": len(cases), "base_profile_available": base_exists, "manifest": str(root / "cases.json")}))


def main():
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest="command", required=True)
    p = subs.add_parser("prepare")
    for field in ("root", "repo", "base"):
        p.add_argument("--" + field, required=True)
    p = subs.add_parser("list")
    p.add_argument("manifest"); p.add_argument("group")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args)
    else:
        for item in json.loads(Path(args.manifest).read_text()):
            if args.group in {"all", item["group"]}:
                print("\t".join([item["id"], item["action"], item["root"], item["scope"]]))


if __name__ == "__main__":
    main()
