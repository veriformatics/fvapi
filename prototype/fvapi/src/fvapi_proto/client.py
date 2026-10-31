"""Disposable v0 client. Replay executes our own delivered Lean code unsandboxed."""

import argparse
from contextlib import contextmanager
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


class ClientError(Exception):
    def __init__(self, detail, payload=None):
        super().__init__(detail)
        self.payload = payload or {"error": "client_error", "detail": detail}


def request(api, route, body=None, binary=False):
    data = None if body is None else json.dumps(body).encode()
    req = Request(api.rstrip("/") + route, data=data,
                  headers={"Content-Type": "application/json"} if data else {})
    try:
        with urlopen(req, timeout=60) as response:
            raw = response.read()
    except HTTPError as exc:
        raw = exc.read()
        try:
            payload = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            payload = {"error": f"http_{exc.code}", "detail": raw.decode(errors="replace")}
        raise ClientError(f"HTTP {exc.code}: {payload.get('detail', payload)}", payload) from exc
    except URLError as exc:
        raise ClientError(f"Cannot reach {api}. Check --api and the server. {exc.reason}") from exc
    return raw if binary else json.loads(raw)


def bundle_path(root, name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ClientError(f"Unsafe bundle path: {name}")
    result = root.joinpath(*path.parts)
    if not result.resolve().is_relative_to(root.resolve()):
        raise ClientError(f"Bundle path leaves the output directory: {name}")
    return result


def fetch(api, entry_id, target):
    target = Path(target).resolve()
    if target.exists() and any(target.iterdir()):
        raise ClientError(f"Output directory is not empty: {target}. Use a new directory.")
    raw = request(api, f"/v0/bundles/{quote(entry_id, safe='')}.tar.gz", binary=True)
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
        members = archive.getmembers()
        names = set()
        for member in members:
            bundle_path(target, member.name)
            if not (member.isfile() or member.isdir()) or member.name in names:
                raise ClientError(f"Unsupported or duplicate bundle member: {member.name}")
            names.add(member.name)
        target.mkdir(parents=True, exist_ok=True)
        archive.extractall(target, members=members, filter="data")
    if not (target / "manifest.json").is_file():
        raise ClientError("The bundle has no manifest.json.")
    return {"id": entry_id, "directory": str(target), "files": len(members)}


def run(command, root, env=None):
    return subprocess.run(command, cwd=root, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)


DEFAULT_IMAGE = "fvapi-recheck:lean-4.35.0"


@contextmanager
def execution(directory, image):
    if image is None:
        yield directory, run
        return
    with tempfile.TemporaryDirectory(prefix="fvapi-container-") as temp:
        root = Path(temp) / "bundle"
        shutil.copytree(directory, root, symlinks=True)

        def container_run(command, cwd, env=None):
            argv = ["podman", "run", "--rm", "--pull=never", "--network=none",
                    "--userns=keep-id", "--user", f"{os.getuid()}:{os.getgid()}",
                    "--cap-drop=all", "--security-opt=no-new-privileges",
                    "--volume", f"{root}:{root}:rw,Z", "--workdir", str(root)]
            if env is not None and "LEAN_PATH" in env:
                argv += ["--env", f"LEAN_PATH={env['LEAN_PATH']}"]
            try:
                result = run(argv + [image] + command, cwd)
            except FileNotFoundError as exc:
                raise ClientError("podman was not found. Install podman to use --container.") from exc
            if result.returncode == 125:
                raise ClientError(f"Cannot run container {image}. Build the image with recheck/build.sh or supply a local image.\n{result.stdout}")
            return result

        yield root, container_run


def inspect_bundle(root):
    root = Path(root).resolve()
    entry = json.loads((root / "manifest.json").read_text())
    checks = []
    for item in entry["closure"]:
        path = bundle_path(root, item["path"])
        ok = path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"]
        checks.append({"pass": ok, "check": "sha256", "detail": item["path"]})
    for statement in entry["statements"]:
        path = bundle_path(root, statement["file"])
        line = statement["line"]
        text = statement["text"]
        source = path.read_bytes() if path.is_file() else b""
        lines = source.splitlines(keepends=True)
        ok = isinstance(line, int) and line > 0 and b"".join(lines[line - 1:]).startswith(text.encode())
        checks.append({"pass": ok, "check": "statement", "detail": statement["name"],
                       "file": statement["file"], "line": line, "text": text})
    return root, entry, checks


def lean_version(root, toolchain, checks, execute=run):
    try:
        version = execute(["lean", "--version"], root)
    except FileNotFoundError:
        checks.append({"pass": False, "check": "toolchain", "detail": "lean was not found",
                       "fix": f"Install {toolchain} with elan and put its bin directory on PATH."})
        return False
    actual = version.stdout.strip()
    expected = toolchain.rsplit(":", 1)[-1].removeprefix("v")
    match = re.search(r"Lean \(version ([^,\s)]+)", actual)
    ok = version.returncode == 0 and match is not None and match[1] == expected
    checks.append({"pass": ok, "check": "toolchain", "detail": actual,
                   "expected": toolchain})
    if not ok:
        checks[-1]["fix"] = f"Install {toolchain} with elan and select it for this directory."
    return ok


DEFAULT_AXIOMS = ("propext", "Classical.choice", "Quot.sound")


def replay(directory, allowed_axioms=None, container=None):
    with execution(directory, container) as (root, execute):
        return replay_bundle(root, allowed_axioms, execute)


def replay_bundle(directory, allowed_axioms=None, execute=run):
    root, entry, checks = inspect_bundle(directory)
    allowed = set(DEFAULT_AXIOMS if allowed_axioms is None else allowed_axioms)
    report = {"id": entry["id"], "checks": checks, "status": "fail",
              "licence": entry.get("licence", {}), "bundle_declares": entry["replay"]["expect_axioms"],
              "allowed_axioms": sorted(allowed)}
    if not all(item["pass"] for item in checks):
        return report, 1
    replay_spec = entry["replay"]
    if replay_spec["status"] == "recorded":
        report.update(status="recorded", transcript=replay_spec.get("transcript"),
                      note="RECORDED (not re-run by fvapi)")
        return report, 3
    if replay_spec["status"] != "real":
        raise ClientError(f"Unknown replay status: {replay_spec['status']}")
    if not lean_version(root, entry["toolchain"], checks, execute):
        return report, 1
    result = execute(["sh", "-c", replay_spec["command"]], root)
    checks.append({"pass": result.returncode == 0, "check": "replay command",
                   "detail": f"exit {result.returncode}"})
    report["transcript"] = result.stdout
    axioms = {}
    for match in re.finditer(r"'([^']+)' (?:depends on axioms:\s*\[([^\]]*)\]|(does not depend on any axioms))", result.stdout):
        dependencies = [a.strip() for a in (match[2] or "").split(",") if a.strip()]
        axioms[match[1]] = sorted(set(axioms.get(match[1], [])) | set(dependencies))
    for name, dependencies in axioms.items():
        unexpected = sorted(set(dependencies) - allowed)
        checks.append({"pass": not unexpected, "check": "axioms",
                       "detail": name + (f"; outside client allowlist: {', '.join(unexpected)}" if unexpected else ""),
                       "axioms": dependencies})
    for statement in entry["statements"]:
        name = statement["name"]
        checks.append({"pass": name in axioms, "check": "axiom audit present", "detail": name})
    report["status"] = "pass" if all(item["pass"] for item in checks) else "fail"
    return report, 0 if report["status"] == "pass" else 1


def local_check(directory, input_value, container=None):
    with execution(directory, container) as (root, execute):
        return check_bundle(root, input_value, execute, container is not None)


def check_bundle(directory, input_value, execute=run, in_container=False):
    root, entry, checks = inspect_bundle(directory)
    if not all(item["pass"] for item in checks):
        raise ClientError("The downloaded bundle failed its hashes or statement checks.")
    if entry["replay"]["status"] != "real":
        raise ClientError("The bundle is recorded. It has no live local checker.")
    recheck = (entry.get("check") or {}).get("recheck")
    if not isinstance(recheck, dict):
        raise ClientError("The bundle has no check.recheck instructions. Request a bundle that supports local rechecking.")
    builds, command = recheck.get("build"), recheck.get("run")
    def valid_argv(argv):
        return isinstance(argv, list) and bool(argv) and all(isinstance(arg, str) and arg for arg in argv)
    if (not isinstance(builds, list) or not all(valid_argv(argv) for argv in builds)
            or not valid_argv(command) or "{input}" not in command):
        raise ClientError("Invalid check.recheck instructions. Supply build argument lists and a run argument list with an {input} token.")
    if not lean_version(root, entry["toolchain"], checks, execute):
        raise ClientError(f"Lean version mismatch. {checks[-1]['fix']}")
    lib = execute(["lean", "--print-libdir"], root)
    if lib.returncode:
        raise ClientError(f"Cannot find the Lean library:\n{lib.stdout}")
    env = os.environ | {"LEAN_PATH": os.pathsep.join([str(root), lib.stdout.strip()])}
    for argv in builds:
        build = execute(argv, root, env)
        if build.returncode:
            raise ClientError(f"The local checker build failed (exit {build.returncode}):\n{build.stdout}")
    # Keep the exact submitted JSON value; the temporary file is never supplied by the bundle.
    with tempfile.TemporaryDirectory(prefix="fvapi-input-", dir=root if in_container else None) as temp:
        input_path = Path(temp) / "input.json"
        input_path.write_text(json.dumps(input_value))
        result = execute([str(input_path) if arg == "{input}" else arg for arg in command], root, env)
    outputs = []
    for line in result.stdout.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and isinstance(value.get("accepted"), bool):
            outputs.append(value)
    if len(outputs) != 1 or result.returncode not in (0, 2):
        raise ClientError(f"The local checker did not return one verdict:\n{result.stdout}")
    verdict = "accept" if outputs[0]["accepted"] else "reject"
    if result.returncode != (0 if verdict == "accept" else 2):
        raise ClientError("The local checker exit code contradicts its JSON verdict.")
    return {"verdict": verdict, "output": outputs[0], "exit_code": result.returncode}


def render(value, command):
    if command == "catalog":
        rows = [["ID", "KIND", "REPLAY", "TITLE"]] + [
            [e["id"], e["kind"], e["replay_status"], e["title"]] for e in value["entries"]]
        widths = [max(len(str(row[i])) for row in rows) for i in range(3)]
        for row in rows:
            print("  ".join(str(cell).ljust(widths[i]) if i < 3 else str(cell)
                             for i, cell in enumerate(row)))
    elif command == "fetch":
        print(f"Downloaded {value['id']} to {value['directory']}")
    elif command == "replay":
        if value.get("licence", {}).get("terms"):
            print(f"Licence terms: {value['licence']['terms']}")
        print(f"bundle declares: {', '.join(value['bundle_declares']) or 'none'}")
        print(f"Client allows: {', '.join(value['allowed_axioms']) or 'none'}")
        for item in value["checks"]:
            print(f"{'PASS' if item['pass'] else 'FAIL'} {item['check']} {item['detail']}")
            if "text" in item:
                print(f"  {item['file']}:{item['line']}\n{item['text']}")
            if "axioms" in item:
                print(f"  Reported axioms: [{', '.join(item['axioms'])}]")
            if "fix" in item:
                print(f"  {item['fix']}")
        if value["status"] == "recorded":
            print(value["note"])
            print(value.get("transcript") or "No recorded transcript.")
        elif value["status"] == "fail" and value.get("transcript"):
            print(value["transcript"])
    elif command == "check":
        server = value.get("server", value)
        print(f"Server verdict: {server['verdict'].upper()}")
        print(json.dumps(server["output"], indent=2, ensure_ascii=False))
        if "local" in value:
            print(f"Local verdict: {value['local']['verdict'].upper()}")
            print("PASS local and server JSON verdicts agree" if value["agree"]
                  else "FAIL local and server JSON verdicts differ")
    else:
        entry = value.get("entry", value)
        if "id" in entry:
            print(f"{entry['id']}  {entry['title']}\n{entry['claim']}")
            print(f"Toolchain: {entry['toolchain']}")
            print(f"Replay: {entry['replay']['status']}")
            if entry.get("licence", {}).get("terms"):
                print(f"Licence terms: {entry['licence']['terms']}")
            for statement in entry["statements"]:
                print(f"\n{statement['name']} ({statement['file']}:{statement['line']})\n{statement['text']}")
        else:
            print(json.dumps(value, indent=2, ensure_ascii=False))


def parser():
    result = argparse.ArgumentParser(description="Find, download and recheck fvapi proof bundles.")
    result.add_argument("--api", default=os.environ.get("FVAPI_API", "http://192.168.40.241:8441"),
                        help="API URL (default: FVAPI_API or vflab)")
    result.add_argument("--json", action="store_true", help="Print JSON instead of a table.")
    commands = result.add_subparsers(dest="command", required=True)
    for name in ("catalog", "show", "lookup", "fetch", "replay", "check"):
        command = commands.add_parser(name)
        command.add_argument("--json", action="store_true", default=argparse.SUPPRESS,
                             help="Print JSON instead of a table.")
        if name in ("replay", "check"):
            command.add_argument("--container", nargs="?", const=DEFAULT_IMAGE, metavar="IMAGE",
                                 help="Run Lean in a local podman image (default: %(const)s).")
        if name in ("show", "fetch", "check"):
            command.add_argument("id", help="Entry ID")
        if name == "lookup":
            command.add_argument("--spec", dest="spec_id")
            command.add_argument("--sha256", dest="artifact_sha256")
            command.add_argument("--statement")
        elif name == "fetch":
            command.add_argument("-o", "--output", required=True, help="New or empty output directory")
        elif name == "replay":
            command.add_argument("directory", help="Directory with manifest.json")
            command.add_argument("--axioms", default=os.environ.get("FVAPI_AXIOMS"),
                                 help="Allowed axioms, comma-separated (default: FVAPI_AXIOMS or propext,Classical.choice,Quot.sound). An empty value allows none.")
        elif name == "check":
            command.add_argument("input", help="Input JSON file")
            command.add_argument("--recheck", action="store_true", help="Build and run the local checker.")
    return result


def main():
    args = parser().parse_args()
    code = 0
    try:
        if args.command == "catalog":
            value = request(args.api, "/v0/catalog")
        elif args.command == "show":
            value = request(args.api, "/v0/catalog/" + quote(args.id, safe=""))
        elif args.command == "lookup":
            query = {key: getattr(args, key) for key in ("spec_id", "artifact_sha256", "statement")
                     if getattr(args, key) is not None}
            if not query:
                raise ClientError("Supply --spec, --sha256 or --statement. Supplied keys must match the same entry.")
            value = request(args.api, "/v0/lookup", query)
        elif args.command == "fetch":
            value = fetch(args.api, args.id, args.output)
        elif args.command == "replay":
            allowed = None if args.axioms is None else [a.strip() for a in args.axioms.split(",") if a.strip()]
            value, code = replay(args.directory, allowed, args.container)
        else:
            if args.container is not None and not args.recheck:
                raise ClientError("Use --recheck with --container to run the local checker.")
            input_value = json.loads(Path(args.input).read_text())
            value = request(args.api, "/v0/checks/" + quote(args.id, safe=""), input_value)
            code = 0 if value["verdict"] == "accept" else 1
            if args.recheck:
                server = value
                with tempfile.TemporaryDirectory(prefix="fvapi-bundle-") as temp:
                    fetch(args.api, args.id, temp)
                    local = local_check(temp, input_value, args.container)
                agree = all(local[key] == server[key] for key in ("verdict", "output", "exit_code"))
                value = {"server": server, "local": local, "agree": agree}
                code = 0 if agree else 1
        if args.json:
            print(json.dumps(value, indent=2, ensure_ascii=False))
        else:
            render(value, args.command)
    except (ClientError, OSError, ValueError, KeyError, TypeError, tarfile.TarError,
            subprocess.SubprocessError) as exc:
        payload = exc.payload if isinstance(exc, ClientError) else {"error": "client_error", "detail": str(exc)}
        print(json.dumps(payload, indent=2) if args.json else f"FAIL {payload.get('detail', str(exc))}",
              file=sys.stderr)
        code = 1
    raise SystemExit(code)


if __name__ == "__main__":
    main()
