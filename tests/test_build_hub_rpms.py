import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class JenkinsBuildTestCase(unittest.TestCase):
    command_source = "build-hub-rpms"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.requests = self.root / "requests.jsonl"
        self.notifications = self.root / "notifications.jsonl"
        self.script("curl", """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
config = args[args.index("--config") + 1]
with open(config) as source:
    auth_config = source.read()
request = {
    "args": args,
    "auth_config": auth_config,
    "env_user": os.environ.get("JENKINS_USER"),
    "env_token": os.environ.get("JENKINS_API_TOKEN"),
}
with open(os.environ["JENKINS_TEST_REQUESTS"], "a") as log:
    log.write(json.dumps(request) + "\\n")
if args[-1].endswith("/crumbIssuer/api/json"):
    print(json.dumps({"crumbRequestField": "Jenkins-Crumb", "crumb": "crumb-value"}))
    print(os.environ.get("JENKINS_TEST_CRUMB_STATUS", "200"))
else:
    with open(args[args.index("-D") + 1], "w") as headers:
        headers.write("Location: https://jenkins.example/queue/item/42/\\r\\n")
    with open(args[args.index("-o") + 1], "w") as body:
        body.write("Build response")
    print(os.environ.get("JENKINS_TEST_BUILD_STATUS", "201"))
""")
        self.script("herdr", """#!/usr/bin/env python3
import json
import os
import sys

with open(os.environ["HERDR_TEST_NOTIFICATIONS"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(int(os.environ.get("HERDR_TEST_NOTIFICATION_STATUS", "0")))
""")
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            JENKINS_USER="jenkins-user",
            JENKINS_API_TOKEN="secret-token",
            JENKINS_TEST_REQUESTS=str(self.requests),
            HOME=str(self.root),
            XDG_CONFIG_HOME=str(self.root / "config"),
            LAUNCH_DIR=str(self.root),
            HERDR_BIN_PATH=str(self.bin / "herdr"),
            HERDR_TEST_NOTIFICATIONS=str(self.notifications),
        )
        self.command = json.loads(subprocess.check_output(
            ["bash", str(ROOT / f"commands/{self.command_source}.sh")], text=True))

    def script(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def launch(self, input_text):
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["bash", str(ROOT / f"handlers/{self.command_source}.sh"),
             json.dumps(self.command)],
            stdin=slave, stdout=slave, stderr=slave, env=self.env)
        os.close(slave)
        self.addCleanup(os.close, master)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        os.write(master, input_text.encode())
        return process, master

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

    def assert_notification(self, job_name):
        notifications = [
            json.loads(line) for line in self.notifications.read_text().splitlines()
        ]
        self.assertEqual(len(notifications), 1)
        self.assertEqual(notifications[0][:3], [
            "notification", "show", "Jenkins build triggered",
        ])
        self.assertEqual(notifications[0][3], "--body")
        self.assertIn(job_name, notifications[0][4])
        self.assertIn("https://jenkins.example/queue/item/42/", notifications[0][4])
        self.assertEqual(notifications[0][5:], ["--sound", "done"])


class BuildHubRpmsTests(JenkinsBuildTestCase):
    def test_command_source(self):
        self.assertEqual(self.command, {
            "type": "build-hub-rpms",
            "label": "Build - Generate Linux Build via Jenkins",
        })

    def test_hub_branch_defaults_to_launch_directory_branch(self):
        worktree = self.root / "worktree"
        subprocess.run(
            ["git", "init", "--quiet", str(worktree)], check=True)
        subprocess.run(
            ["git", "-C", str(worktree), "symbolic-ref",
             "HEAD", "refs/heads/feature/launched-here"], check=True)
        nested = worktree / "nested"
        nested.mkdir()
        self.env["LAUNCH_DIR"] = str(nested)
        process, master = self.launch("\n\n\n\n\n\n\n\ny\n")
        output = self.until(master, b"Jenkins accepted the build request")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertIn("Hub branch [feature/launched-here]", output)
        self.assertIn("Hub branch:             feature/launched-here", output)
        self.assertIn("Build the RPMs [y/N]", output)
        self.assertIn("Build RPMs:             false", output)
        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        self.assertIn("IHub_TargetBranch=feature/launched-here",
                      requests[-1]["args"])
        self.assertIn("Build_the_RPMs=false", requests[-1]["args"])

    def test_missing_launch_branch_warns_and_preserves_previous_default(self):
        process, master = self.launch("\n\n\n\n\n\n\n\nn\n")
        output = self.until(master, b"Build cancelled.")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertIn("could not determine the current Git branch", output)
        self.assertIn("Hub branch [iisMultiSource]", output)
        self.assertFalse(self.requests.exists())

    def test_prompts_confirms_and_posts_parameters_with_crumb(self):
        process, master = self.launch(
            "feature/test\nmain\n2.0.0-3\ny\nn\ny\ny\nn\ny\n")
        output = self.until(master, b"Jenkins accepted the build request")
        self.assertIn("Hub branch:             feature/test", output)
        self.assertIn("Install on uk-r9-ib-003: true", output)
        self.assertIn("Jenkins accepted the build request (HTTP 201)", output)
        self.assertEqual(process.wait(timeout=5), 0)
        self.assert_notification("Build_Hub_RPMs_FromGitHub")

        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        self.assertEqual(len(requests), 2)
        self.assertTrue(requests[0]["args"][-1].endswith(
            "/crumbIssuer/api/json"))
        post = requests[1]
        self.assertTrue(post["args"][-1].endswith(
            "/job/Build_Hub_RPMs_FromGitHub/buildWithParameters"))
        self.assertIn("--header", post["args"])
        self.assertEqual(post["args"][post["args"].index("--header") + 1],
                         "Jenkins-Crumb: crumb-value")
        data = [post["args"][i + 1] for i, arg in enumerate(post["args"])
                if arg == "--data-urlencode"]
        self.assertEqual(data, [
            "IHub_TargetBranch=feature/test",
            "HubUI_TargetBranch=main",
            "Hub_Version_Number=2.0.0-3",
            "Run_unit_tests=true",
            "Run_integration_tests=false",
            "Build_the_RPMs=true",
            "Install_the_built_version=true",
            "UI_Production_Mode=false",
        ])
        self.assertIn('user = "jenkins-user:secret-token"', post["auth_config"])
        self.assertNotIn("secret-token", " ".join(post["args"]))
        self.assertNotIn("secret-token", output)

    def test_install_defaults_off_and_cancel_skips_network(self):
        process, master = self.launch("\n\n\n\n\n\n\n\nn\n")
        output = self.until(master, b"Build cancelled.")
        self.assertIn("Install on uk-r9-ib-003: false", output)
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertFalse(self.requests.exists())

    def test_missing_credentials_fails_before_prompting_or_network(self):
        for missing in [
            ("JENKINS_USER",),
            ("JENKINS_API_TOKEN",),
            ("JENKINS_USER", "JENKINS_API_TOKEN"),
        ]:
            for value in (None, ""):
                with self.subTest(missing=missing, value=value):
                    env = self.env.copy()
                    for variable in missing:
                        if value is None:
                            env.pop(variable)
                        else:
                            env[variable] = value
                    result = subprocess.run(
                        ["bash", str(ROOT / "handlers/build-hub-rpms.sh"),
                         json.dumps(self.command)],
                        env=env, capture_output=True, text=True)
                    self.assert_credentials_instructions(result, missing)

    def assert_credentials_instructions(self, result, missing):
        self.assertNotEqual(result.returncode, 0)
        expected = "".join(f"  {variable}\n" for variable in missing)
        self.assertIn(
            f"Error: missing or empty Jenkins credentials:\n{expected}\n",
            result.stderr)
        path = Path(self.env["XDG_CONFIG_HOME"]) / "herdr-launcher/jenkins.env"
        self.assertIn(str(path), result.stderr)
        for instruction in (
            "mkdir -p", "umask 077", "chmod 600",
            "export JENKINS_USER='your-jenkins-user'",
            "export JENKINS_API_TOKEN='your-api-token'",
            "no Herdr restart is needed",
        ):
            self.assertIn(instruction, result.stderr)
        self.assertNotIn("secret-token", result.stderr)
        self.assertNotIn("Hub branch", result.stdout)
        self.assertFalse(self.requests.exists())

    def credentials_file(self, base):
        directory = base / "herdr-launcher"
        directory.mkdir(parents=True)
        path = directory / "jenkins.env"
        path.write_text(
            "export JENKINS_USER='file-user'\n"
            "export JENKINS_API_TOKEN='file-token'\n")
        path.chmod(0o600)
        return path

    def test_credentials_file_when_environment_is_missing(self):
        self.credentials_file(Path(self.env["XDG_CONFIG_HOME"]))
        self.env.pop("JENKINS_USER")
        self.env.pop("JENKINS_API_TOKEN")
        process, master = self.launch("\n\n\n\n\n\n\n\ny\n")
        output = self.until(master, b"Jenkins accepted the build request")
        self.assertEqual(process.wait(timeout=5), 0)
        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        self.assertIn('user = "file-user:file-token"', requests[-1]["auth_config"])
        self.assertNotIn("file-token", output)
        self.assertNotIn("file-token", " ".join(requests[-1]["args"]))

    def test_incomplete_credentials_file_shows_resolution_instructions(self):
        path = self.credentials_file(Path(self.env["XDG_CONFIG_HOME"]))
        path.write_text("export JENKINS_USER='file-user'\n")
        self.env.pop("JENKINS_USER")
        self.env.pop("JENKINS_API_TOKEN")
        result = subprocess.run(
            ["bash", str(ROOT / "handlers/build-hub-rpms.sh"),
             json.dumps(self.command)],
            env=self.env, capture_output=True, text=True)
        self.assert_credentials_instructions(result, ("JENKINS_API_TOKEN",))

    def test_credentials_file_defaults_to_home_config(self):
        self.credentials_file(self.root / ".config")
        self.env.pop("XDG_CONFIG_HOME")
        self.env.pop("JENKINS_USER")
        self.env.pop("JENKINS_API_TOKEN")
        process, master = self.launch("\n\n\n\n\n\n\n\nn\n")
        self.until(master, b"Build cancelled.")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertFalse(self.requests.exists())

    def test_existing_environment_does_not_load_credentials_file(self):
        path = self.credentials_file(Path(self.env["XDG_CONFIG_HOME"]))
        path.write_text("exit 99\n")
        process, master = self.launch("\n\n\n\n\n\n\n\nn\n")
        self.until(master, b"Build cancelled.")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertFalse(self.requests.exists())


class BuildHubWindowsTests(JenkinsBuildTestCase):
    command_source = "build-hub-windows"

    def test_command_source(self):
        self.assertEqual(self.command, {
            "type": "build-hub-windows",
            "label": "Build - Generate Windows Build via Jenkins",
        })
        self.assertTrue(os.access(
            ROOT / "handlers/build-hub-windows.sh", os.X_OK))

    def test_defaults_and_launch_branch_are_posted_to_windows_job(self):
        worktree = self.root / "windows-worktree"
        subprocess.run(["git", "init", "--quiet", str(worktree)], check=True)
        subprocess.run(
            ["git", "-C", str(worktree), "symbolic-ref", "HEAD",
             "refs/heads/feature/windows"], check=True)
        self.env["LAUNCH_DIR"] = str(worktree)
        process, master = self.launch("\n" * 9 + "y\n")
        output = self.until(master, b"Queue:")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertIn("Hub branch [feature/windows]", output)
        self.assertIn("FIPS mode:              false", output)
        self.assertIn("https://jenkins.example/queue/item/42/", output)
        self.assert_notification("Build_Hub_On_Windows_GitHUB")
        self.assertNotIn("Hub version number", output)
        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        self.assertEqual(len(requests), 2)
        post = requests[-1]
        self.assertTrue(post["args"][-1].endswith(
            "/job/Build_Hub_On_Windows_GitHUB/buildWithParameters"))
        data = [post["args"][i + 1] for i, arg in enumerate(post["args"])
                if arg == "--data-urlencode"]
        self.assertEqual(data, [
            "TargetBranch=feature/windows",
            "UI_Repository_Branch=main",
            "Run_Unit_tests=true",
            "Run_Integration_tests=true",
            "Build_the_installer=true",
            "Build_License_Generator=true",
            "Build_Diagnostic_Key_Generator=true",
            "UI_Production_Mode=true",
            "FIPS_Mode=false",
        ])
        self.assertIn("Jenkins-Crumb: crumb-value", post["args"])
        self.assertNotIn("secret-token", " ".join(post["args"]))
        self.assertNotIn("secret-token", output)

    def test_explicit_options_and_no_crumb(self):
        self.env["JENKINS_TEST_CRUMB_STATUS"] = "404"
        process, master = self.launch(
            "feature/other\nui/other\ninvalid\nn\nn\nn\nn\nn\nn\ny\ny\n")
        self.until(master, b"Queue:")
        self.assertEqual(process.wait(timeout=5), 0)
        requests = [json.loads(line) for line in self.requests.read_text().splitlines()]
        post = requests[-1]
        self.assertNotIn("--header", post["args"])
        data = [post["args"][i + 1] for i, arg in enumerate(post["args"])
                if arg == "--data-urlencode"]
        self.assertEqual(data, [
            "TargetBranch=feature/other",
            "UI_Repository_Branch=ui/other",
            "Run_Unit_tests=false",
            "Run_Integration_tests=false",
            "Build_the_installer=false",
            "Build_License_Generator=false",
            "Build_Diagnostic_Key_Generator=false",
            "UI_Production_Mode=false",
            "FIPS_Mode=true",
        ])

    def test_cancel_skips_network(self):
        process, master = self.launch("\n" * 9 + "n\n")
        self.until(master, b"Build cancelled.")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertFalse(self.requests.exists())

    def test_missing_credentials_shows_shared_instructions(self):
        self.env.pop("JENKINS_API_TOKEN")
        result = subprocess.run(
            ["bash", str(ROOT / "handlers/build-hub-windows.sh"),
             json.dumps(self.command)],
            env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("  JENKINS_API_TOKEN\n", result.stderr)
        self.assertIn("chmod 600", result.stderr)
        self.assertIn("jenkins.env", result.stderr)
        self.assertFalse(self.requests.exists())

    def test_rejected_build_is_reported(self):
        self.env["JENKINS_TEST_BUILD_STATUS"] = "403"
        process, master = self.launch("\n" * 9 + "y\n")
        self.until(master, b"Jenkins rejected the build request (HTTP 403)")
        self.assertNotEqual(process.wait(timeout=5), 0)
        self.assertFalse(self.notifications.exists())

    def test_notification_failure_does_not_change_accepted_build_status(self):
        self.env["HERDR_TEST_NOTIFICATION_STATUS"] = "1"
        process, master = self.launch("\n" * 9 + "y\n")
        output = self.until(master, b"could not be displayed")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertIn("Jenkins accepted the build request", output)

    def test_failed_crumb_does_not_submit_build(self):
        self.env["JENKINS_TEST_CRUMB_STATUS"] = "401"
        process, master = self.launch("\n" * 9 + "y\n")
        self.until(master, b"Jenkins CSRF crumb request failed with HTTP 401")
        self.assertNotEqual(process.wait(timeout=5), 0)
        requests = self.requests.read_text().splitlines()
        self.assertEqual(len(requests), 1)


if __name__ == "__main__":
    unittest.main()
