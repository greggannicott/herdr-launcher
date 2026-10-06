#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  '{"type":"copilot-report","label":"Code Review - Review Staged Changes","payload":{"prompt":"Review only the staged changes","args":["--agent","code-reviewer","--allow-tool","shell(git:*)","--allow-tool","write"]}}'
