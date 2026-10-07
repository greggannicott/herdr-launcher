import json
import os
import subprocess
import time
import unittest

from tests.test_build_hub_rpms import JenkinsBuildTestCase, ROOT


class ListBuildResultsTests(JenkinsBuildTestCase):
    command_source = "list-build-results"

    def setUp(self):
        super().setUp()
        self.env["TEST_ROOT"] = str(self.root)
        self.script("curl", """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
root = Path(os.environ["TEST_ROOT"])
platform = "Linux" if "RPMs" in args[-1] else "Windows"
with open(root / "requests.jsonl", "a") as log:
    log.write(json.dumps(args) + "\\n")
output = args[args.index("-o") + 1]
Path(output).write_text((root / (platform + ".json")).read_text())
print(os.environ.get("TEST_HTTP_STATUS", "200"))
""")
        self.script("fzf", """#!/usr/bin/env python3
import os, sys
from pathlib import Path
root = Path(os.environ["TEST_ROOT"])
data = sys.stdin.buffer.read()
(root / "picker").write_bytes(data)
(root / "picker_args").write_text("\\n".join(sys.argv[1:]))
status = int(os.environ.get("TEST_FZF_STATUS", "0"))
if status:
    sys.exit(status)
rows = data.split(b"\\0")
sys.stdout.buffer.write(rows[int(os.environ.get("TEST_SELECTION", "1"))] + b"\\0")
""")
        browser = """#!/usr/bin/env python3
import os, sys
from pathlib import Path
Path(os.environ["TEST_ROOT"], "opened").write_text(sys.argv[1])
sys.exit(int(os.environ.get("TEST_BROWSER_STATUS", "0")))
"""
        self.script("open", browser)
        self.script("xdg-open", browser)
        for platform, number, timestamp, building, result, key in [
            ("Linux", 12, 1700000000000, False, "FAILURE", "IHub_TargetBranch"),
            ("Windows", 34, 1700000060000, True, None, "TargetBranch"),
        ]:
            (self.root / f"{platform}.json").write_text(json.dumps({
                "builds": [{
                    "number": number, "timestamp": timestamp,
                    "building": building, "result": result,
                    "actions": [{"parameters": [{"name": key,
                                                  "value": f"feature/{platform}"}]}],
                }],
            }))

    def run_handler(self, input_text=""):
        return subprocess.run(
            ["bash", str(ROOT / "handlers/list-build-results.sh"),
             json.dumps(self.command)],
            env=self.env, input=input_text, capture_output=True, text=True)

    def test_source_and_handler(self):
        self.assertEqual(self.command, {
            "type": "list-build-results",
            "label": "Build - List Build Results",
        })
        self.assertTrue(os.access(ROOT / "handlers/list-build-results.sh", os.X_OK))

    def test_combined_sorted_columns_and_browser_selection(self):
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = (self.root / "picker").read_bytes().decode().split("\0")
        self.assertIn("Date/Time (UTC)", rows[0])
        self.assertIn("Started", rows[0])
        self.assertIn("Hub Branch", rows[0])
        self.assertTrue(rows[1].startswith("Windows"))
        self.assertIn("RUNNING", rows[1])
        self.assertIn("feature/Windows", rows[1])
        self.assertTrue(rows[2].startswith("Linux"))
        self.assertIn("FAILURE", rows[2])
        self.assertEqual(
            (self.root / "opened").read_text(),
            "https://v-jenkins.syncdi1.us.syncsort.com/job/Build_Hub_On_Windows_GitHUB/34/")
        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        self.assertEqual(len(requests), 2)
        self.assertTrue(all("{0,25}" in request[request.index("--data-urlencode") + 1]
                            for request in requests))
        self.assertNotIn("secret-token", json.dumps(requests))
        self.assertIn("--with-nth=1", (self.root / "picker_args").read_text())

    def test_linux_selection(self):
        self.env["TEST_SELECTION"] = "2"
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "opened").read_text().endswith(
            "/Build_Hub_RPMs_FromGitHub/12/"))

    def test_column_headers_align_with_results(self):
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        header, windows, linux, _ = (
            (self.root / "picker").read_bytes().decode().split("\0"))
        for row, number, status, branch in (
            (windows, "34", "RUNNING", "feature/Windows"),
            (linux, "12", "FAILURE", "feature/Linux"),
        ):
            for label, value in (
                ("Build", number),
                ("Date/Time (UTC)", "2023-"),
                ("Result", status),
                ("Hub Branch", branch),
            ):
                with self.subTest(platform=row[:7], column=label):
                    self.assertEqual(header.index(label), row.index(value))
            started = row[:row.index("ago")].rstrip().split()[-1] + " ago"
            self.assertEqual(header.index("Started"), row.index(started))

    def test_relative_age_column(self):
        now = time.time()
        builds = []
        for number, seconds in enumerate((0, 150, 7500, 176400, -3600), start=1):
            builds.append({
                "number": number,
                "timestamp": int((now - seconds) * 1000),
                "building": False,
                "result": "SUCCESS",
            })
        (self.root / "Linux.json").write_text(json.dumps({"builds": builds}))
        (self.root / "Windows.json").write_text('{"builds":[]}')
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = (self.root / "picker").read_bytes().decode().split("\0")
        for number, expected in enumerate(
                ("just now", "2m ago", "2h ago", "2d ago", "just now"), start=1):
            row = next(row for row in rows
                       if row.startswith(f"Linux     {number} "))
            self.assertIn(expected, row)

    def test_cancel_does_not_open_browser(self):
        self.env["TEST_FZF_STATUS"] = "130"
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "opened").exists())

    def test_http_failure_is_explicit(self):
        self.env["TEST_HTTP_STATUS"] = "403"
        result = self.run_handler()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Linux", result.stderr)
        self.assertIn("HTTP 403", result.stderr)
        self.assertFalse((self.root / "opened").exists())

    def test_invalid_response_is_explicit(self):
        (self.root / "Windows.json").write_text("{}")
        result = self.run_handler()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid Windows build results", result.stderr)
        self.assertFalse((self.root / "picker").exists())

    def test_empty_results(self):
        for platform in ("Linux", "Windows"):
            (self.root / f"{platform}.json").write_text('{"builds":[]}')
        result = self.run_handler("x")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No Linux or Windows builds found", result.stdout)
        self.assertFalse((self.root / "picker").exists())

    def test_picker_failure_is_explicit(self):
        self.env["TEST_FZF_STATUS"] = "2"
        result = self.run_handler()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("picker failed", result.stderr)

    def test_browser_failure_is_explicit(self):
        self.env["TEST_BROWSER_STATUS"] = "1"
        result = self.run_handler()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not open", result.stderr)

    def test_missing_credentials_show_setup_instructions(self):
        self.env.pop("JENKINS_API_TOKEN")
        result = self.run_handler()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("JENKINS_API_TOKEN", result.stderr)
        self.assertIn("chmod 600", result.stderr)
        self.assertFalse(self.requests.exists())


if __name__ == "__main__":
    unittest.main()
