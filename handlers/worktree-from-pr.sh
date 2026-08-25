#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

"$herdr" plugin pane open \
  --plugin tdi.worktree-from-pr \
  --entrypoint picker \
  --env "HERDR_WFP_CWD=${LAUNCH_DIR:-$PWD}" \
  --placement overlay \
  --focus
