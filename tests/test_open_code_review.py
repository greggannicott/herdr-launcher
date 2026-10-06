import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class OpenCodeReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.worktree = self.root / "worktree with spaces"
        self.worktree.mkdir()
        subprocess.run(["git", "init", "-q", str(self.worktree)], check=True)
        self.review = self.worktree / "review report.out"
        self.review.write_text("Review findings")
        self.log = self.root / "herdr.jsonl"
        self.fzf_args = self.root / "fzf-args.json"

        self.script("fzf", """#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ["FZF_ARGS"], "w") as log:
    json.dump(sys.argv[1:], log)
items = sys.stdin.buffer.read().split(b"\\0")
selected = os.environ.get("FAKE_FZF_SELECT", "").encode()
for item in items:
    if item.endswith(b"\\t" + selected):
        sys.stdout.buffer.write(item + b"\\0")
        break
""")
        self.script("nvim", "#!/usr/bin/env bash\nexit 0\n")
        self.script("herdr", """#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ["HERDR_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:3] == ["tab", "create"]:
    print(json.dumps({"result": {"root_pane": {"pane_id": "w1:p2"}}}))
elif sys.argv[1:3] == ["pane", "current"]:
    print(json.dumps({"result": {"pane": {"workspace_id": "w1"}}}))
""")
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            LAUNCH_DIR=str(self.worktree),
            HERDR_WORKSPACE_ID="w1",
            HERDR_BIN_PATH=str(self.bin / "herdr"),
            HERDR_LOG=str(self.log),
            FZF_ARGS=str(self.fzf_args),
            FAKE_FZF_SELECT=str(self.review.resolve()),
        )

    def script(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_handler(self):
        return subprocess.run(
            ["bash", str(ROOT / "handlers/open-code-review.sh"),
             json.dumps({"type": "open-code-review"})],
            env=self.env, capture_output=True, text=True)

    def test_selecting_review_creates_focused_tab_and_opens_file(self):
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        fzf_args = json.loads(self.fzf_args.read_text())
        self.assertIn("--layout=reverse", fzf_args)
        self.assertIn("--ansi", fzf_args)
        self.assertIn("--no-sort", fzf_args)
        self.assertIn(
            "--color=fg:#abb2bf,bg:#282c34,hl:#61afef,fg+:#abb2bf,bg+:#3e4451,"
            "hl+:#61afef,info:#56b6c2,prompt:#61afef,pointer:#e06c75,"
            "marker:#98c379,spinner:#c678dd,header:#e5c07b,border:#4b5263,"
            "label:#abb2bf,query:#abb2bf,scrollbar:#4b5263,gutter:#282c34",
            fzf_args,
        )
        self.assertIn("--read0", fzf_args)
        self.assertIn("--print0", fzf_args)
        self.assertIn("--with-nth=1", fzf_args)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls[0], [
            "tab", "create", "--workspace", "w1", "--cwd", str(self.worktree.resolve()),
            "--label", "Code Review - review report.out", "--focus",
        ])
        self.assertEqual(calls[1][:3], ["pane", "run", "w1:p2"])
        self.assertEqual(
            shlex.split(calls[1][3]),
            ["exec", "nvim", "--", str(self.review.resolve())])

    def test_no_reviews_does_not_create_tab(self):
        self.review.unlink()
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No code review files", result.stdout)
        self.assertFalse(self.log.exists())

    def test_missing_workspace_variable_uses_calling_pane_context(self):
        self.env.pop("HERDR_WORKSPACE_ID")
        result = self.run_handler()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls[0], ["pane", "current", "--current"])
        self.assertEqual(calls[1][0:4], [
            "tab", "create", "--workspace", "w1",
        ])


if __name__ == "__main__":
    unittest.main()
