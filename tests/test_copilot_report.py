import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CopilotReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.cwd = self.root / "repository with spaces"
        self.cwd.mkdir()
        subprocess.run(["git", "init", "-q", str(self.cwd)], check=True)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        LAUNCH_DIR=str(self.cwd))
        self.script("copilot", """#!/usr/bin/env python3
import json
import os
import sys
print(json.dumps({"args": sys.argv[1:], "cwd": os.getcwd()}), flush=True)
print("Review report", flush=True)
sys.exit(int(os.environ.get("COPILOT_STATUS", "0")))
""")
        self.script("date", """#!/usr/bin/env bash
case "$1" in
  +%F) echo 2026-10-06 ;;
  +%H-%M) echo 17-03 ;;
  *) exit 1 ;;
esac
""")
        self.command = json.loads(subprocess.check_output(
            ["bash", str(ROOT / "commands/review-branch.sh")], text=True))

    def script(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def launch(self, argv):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        process = subprocess.Popen(
            argv, stdin=slave, stdout=slave, stderr=slave, env=self.env)
        os.close(slave)
        self.addCleanup(self.stop, process)
        return process, master

    @staticmethod
    def stop(process):
        if process.poll() is None:
            process.kill()
        process.wait()

    def until(self, master, marker):
        output = b""
        deadline = time.monotonic() + 5
        while marker not in output:
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, output.decode())
            ready, _, _ = select.select([master], [], [], remaining)
            self.assertTrue(ready, output.decode())
            output += os.read(master, 65536)
        return output.decode()

    def handler(self, command=None):
        return self.launch([
            "bash", str(ROOT / "handlers/copilot-report.sh"),
            json.dumps(self.command if command is None else command)])

    def test_review_arguments_directory_and_key_wait(self):
        process, master = self.handler()
        output = self.until(master, b"Press any key to close")
        invocation = json.loads(next(line for line in output.splitlines()
                                     if line.startswith("{")))
        self.assertEqual(invocation, {
            "args": ["--agent", "code-reviewer", "--allow-tool", "shell(git:*)",
                     "--allow-tool", "write", "-p",
                     "Review branch compared to origin/iisMultiSource\n\n"
                     "Save the complete review report at "
                     f"{self.cwd}/code-review-iisMultiSource-2026-10-06-17-03.{{status}}.out. "
                     "Replace {status} with reject if there are actionable findings, or accept "
                     "if there are none. Keep the type, date, and time in the filename unchanged."],
            "cwd": str(self.cwd),
        })
        self.assertIn("Review report", output)
        self.assertIsNone(process.poll())
        os.write(master, b"x")
        self.assertEqual(process.wait(timeout=5), 0)

    def test_review_staged_changes_command(self):
        command = json.loads(subprocess.check_output(
            ["bash", str(ROOT / "commands/review-staged-changes.sh")], text=True))
        self.assertEqual(command, {
            "type": "copilot-report",
            "label": "Code Review - Review Staged Changes",
            "payload": {
                "prompt": "Review only the staged changes",
                "review_type": "staged",
                "args": ["--agent", "code-reviewer", "--allow-tool", "shell(git:*)",
                         "--allow-tool", "write"],
            },
        })

    def test_review_unstaged_changes_command(self):
        command = json.loads(subprocess.check_output(
            ["bash", str(ROOT / "commands/review-unstaged-changes.sh")], text=True))
        self.assertEqual(command, {
            "type": "copilot-report",
            "label": "Code Review - Review Unstaged Changes",
            "payload": {
                "prompt": "Review only the unstaged changes",
                "review_type": "unstaged",
                "args": ["--agent", "code-reviewer", "--allow-tool", "shell(git:*)",
                         "--allow-tool", "write"],
            },
        })

    def test_prompt_only_and_literal_arguments(self):
        for args in (None, [], ["value with spaces", "line one\nline two", "$(false)"]):
            with self.subTest(args=args):
                payload = {"prompt": "A report"}
                if args is not None:
                    payload["args"] = args
                process, master = self.handler({"payload": payload})
                output = self.until(master, b"Press any key to close")
                invocation = json.loads(next(line for line in output.splitlines()
                                             if line.startswith("{")))
                self.assertIn("A report", output)
                self.assertEqual(invocation["args"],
                                 (args or []) + ["-p", "A report"])
                os.write(master, b"x")
                self.assertEqual(process.wait(timeout=5), 0)

    def test_explanation_is_visible_before_copilot_produces_output(self):
        self.script("copilot", """#!/usr/bin/env python3
input()
print("Review report", flush=True)
""")
        process, master = self.handler()
        output = self.until(master, b"this may take a few moments.")
        self.assertIn(self.command["label"], output)
        self.assertIn(f"Directory: {self.cwd}", output)
        self.assertIn(f'Prompt: {self.command["payload"]["prompt"]}', output)
        self.assertNotIn("Review report", output)
        self.assertIsNone(process.poll())
        os.write(master, b"\n")
        output = self.until(master, b"Press any key to close")
        self.assertIn("Review report", output)
        os.write(master, b"x")
        self.assertEqual(process.wait(timeout=5), 0)

    def test_invalid_payloads(self):
        for payload in ({}, {"prompt": ""}, {"prompt": "ok", "args": "bad"},
                        {"prompt": "ok", "args": False},
                        {"prompt": "ok", "args": [123]},
                        {"prompt": "ok", "args": ["bad\0argument"]}):
            with self.subTest(payload=payload):
                result = subprocess.run(
                    ["bash", str(ROOT / "handlers/copilot-report.sh"),
                     json.dumps({"payload": payload})],
                    env=self.env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Error:", result.stderr)
                self.assertNotIn("Review report", result.stdout)

    def test_missing_copilot_is_an_error(self):
        (self.bin / "copilot").unlink()
        (self.bin / "jq").symlink_to(shutil.which("jq"))
        self.env["PATH"] = str(self.bin)
        result = subprocess.run(
            ["/bin/bash", str(ROOT / "handlers/copilot-report.sh"),
             json.dumps(self.command)],
            env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires copilot on PATH", result.stderr)

    def test_launcher_dispatch_and_failure_key_wait(self):
        plugin = self.root / "plugin"
        (plugin / "commands").mkdir(parents=True)
        (plugin / "handlers").mkdir()
        (plugin / "lib").mkdir()
        shutil.copy2(ROOT / "commands/review-branch.sh", plugin / "commands")
        shutil.copy2(ROOT / "handlers/copilot-report.sh", plugin / "handlers")
        shutil.copy2(ROOT / "lib/fzf.sh", plugin / "lib")
        self.script("fzf", "#!/usr/bin/env bash\nhead -n 1\n")
        self.env["HERDR_PLUGIN_ROOT"] = str(plugin)
        for status in (0, 7):
            with self.subTest(status=status):
                self.env["COPILOT_STATUS"] = str(status)
                process, master = self.launch(["bash", str(ROOT / "launcher.sh")])
                output = self.until(master, b"Press any key to close")
                self.assertIn("Review report", output)
                if status:
                    self.assertIn("Error: Copilot exited with status 7", output)
                self.assertIsNone(process.poll())
                os.write(master, b"x")
                self.assertEqual(process.wait(timeout=5), 1 if status else 0)

    def test_missing_launch_directory_is_an_error(self):
        self.env["LAUNCH_DIR"] = str(self.root / "missing")
        result = subprocess.run(
            ["bash", str(ROOT / "handlers/copilot-report.sh"), json.dumps(self.command)],
            env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing", result.stderr)
        self.assertNotIn("Review report", result.stdout)


if __name__ == "__main__":
    unittest.main()
