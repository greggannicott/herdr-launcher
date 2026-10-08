#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  '{"type":"copilot-report","label":"Code Review - Review Unstaged Changes","payload":{"prompt":"Review only the unstaged changes","review_type":"unstaged","args":["--agent","code-reviewer","--allow-tool","shell(git:*)","--allow-tool","write"]}}'
