#!/usr/bin/env python3
"""Offline SSH identity contract; no network, sudo or remote state."""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import unittest

PROJECT = "FVAPI"
ROOT = Path(__file__).resolve().parents[1]
RUNNER = Path(os.environ.get("IDENTITY_TEST_RUNNER", str(ROOT / "tools/vflab-run")))

STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

log = Path(os.environ["IDENTITY_EVENTS"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def emit(kind, **fields):
    with log.open("a") as stream:
        stream.write(json.dumps({"kind": kind, **fields}) + "\n")
if name == "sudo":
    tokens = args
    emit("unit", tokens=tokens)
    ws = tokens[tokens.index("vflab-run") + 1]
    print(ws + "/result")
    print(ws + "/error", file=sys.stderr)
    sys.exit(7)
if name == "git":
    if "push" in args:
        emit("push", args=args)
        sys.exit(0)
    os.execv(os.environ["IDENTITY_REAL_GIT"], ["git", *args])
command = args[-1]
old = [json.loads(row) for row in log.read_text().splitlines()] if log.exists() else []
first = not any(row["kind"] == "ssh" for row in old)
emit("ssh", target=args[-2], command=command)
if first:
    mode = os.environ["IDENTITY_MODE"]
    if mode == "failed":
        sys.exit(255)
    print(os.environ["IDENTITY_RESPONSE"])
    sys.exit(0)
if "systemd-run" in command:
    sys.stdin.buffer.read()
    sys.exit(subprocess.run(["bash", "-c", command], stdin=subprocess.DEVNULL).returncode)
if "cat >" in command:
    emit("upload")
    sys.stdin.buffer.read()
sys.exit(0)
'''


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.scratch = ROOT / ".scratch"
        self.scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="identity-", dir=self.scratch)
        self.folder = Path(self.temp.name)
        self.bin = self.folder / "bin"
        self.bin.mkdir()
        for name in ("ssh", "git", "sudo"):
            tool = self.bin / name
            tool.write_text(STUB)
            tool.chmod(0o755)
        self.events = self.folder / "events.jsonl"
        real_git = shutil.which("git")
        assert real_git
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "IDENTITY_EVENTS": str(self.events),
            "IDENTITY_REAL_GIT": real_git,
            "IDENTITY_MODE": "valid",
            PROJECT + "_VFLAB": "independent-host",
        }

    def tearDown(self):
        self.temp.cleanup()
        try:
            self.scratch.rmdir()
        except OSError:
            pass

    def invoke(self, response, mode="valid"):
        self.events.unlink(missing_ok=True)
        env = {**self.env, "IDENTITY_RESPONSE": response, "IDENTITY_MODE": mode}
        result = subprocess.run(
            ["bash", str(RUNNER), "bash", "-c", "exit 7", "$HOME $$"],
            env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15,
        )
        events = [json.loads(row) for row in self.events.read_text().splitlines()]
        return result, events

    def test_remote_identity_and_literal_paths(self):
        # Different UID/GID + shell, regex and replacement metacharacters in HOME.
        generator = random.Random(0x535348)
        cases = [(24681, 24682, "/srv/team/work"),
                 (24681, 24682, "/srv/team/home ' #[]$&\\n")]
        alphabet = "abcXYZ019 ._-'#[]$&\\"
        cases += [(generator.randrange(1, 2**31), generator.randrange(1, 2**31),
                   "/srv/team/" + "".join(generator.choices(alphabet, k=24))) for _ in range(8)]
        for remote_uid, remote_gid, remote_home in cases:
            with self.subTest(remote_home=remote_home):
                result, events = self.invoke(f"{remote_uid}\n{remote_gid}\n{remote_home}")
                self.assertEqual(result.returncode, 7, result.stderr)
                probe = events[0]
                self.assertIn("id -u", probe["command"])
                self.assertIn("id -g", probe["command"])
                self.assertIn('"$HOME"', probe["command"])
                self.assertTrue(all(e.get("target", "independent-host") == "independent-host"
                                    for e in events))
                units = [e for e in events if e["kind"] == "unit"]
                self.assertEqual(len(units), 1)
                tokens = units[0]["tokens"]
                self.assertIn(f"--uid={remote_uid}", tokens)
                self.assertIn(f"--gid={remote_gid}", tokens)
                self.assertIn("--setenv=HOME=" + remote_home, tokens)
                self.assertIn("--slice=fvapi_gate.slice", tokens)
                self.assertIn("--property=Type=oneshot", tokens)
                self.assertIn("--property=IgnoreSIGPIPE=no", tokens)
                self.assertIn("--expand-environment=no", tokens)
                self.assertEqual(tokens[-1], "$HOME $$")
                self.assertEqual(result.stdout, str(ROOT) + "/result\n")
                self.assertEqual(result.stderr, str(ROOT) + "/error\n")

    def test_bad_probe_stops_before_upload_or_unit(self):
        cases = [
            "not-a-uid\n24682\n/srv/team", "24681\nbad-group\n/srv/team",
            "24681\n24682\nrelative", "24681\n24682\n", "24681\n24682",
            "24681\n24682\n/srv/team\nextra",
        ]
        for response in cases:
            with self.subTest(response=response):
                result, events = self.invoke(response)
                self.assertEqual(result.returncode, 125, result.stderr)
                self.assertEqual([e["kind"] for e in events], ["ssh"])

    def test_failed_probe_stops_before_upload_or_unit(self):
        result, events = self.invoke("24681\n24682\n/srv/team", mode="failed")
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertEqual([e["kind"] for e in events], ["ssh"])


if __name__ == "__main__":
    unittest.main()
