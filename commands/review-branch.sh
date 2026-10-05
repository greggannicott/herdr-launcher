#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  '{"type":"copilot-report","label":"Code Review - Review branch against origin/iisMultiSource","payload":{"prompt":"Review branch compared to origin/iisMultiSource","args":["--agent","code-reviewer","--allow-tool","shell(git:*)","--allow-tool","write"]}}'
