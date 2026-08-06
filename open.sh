#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
plugin_id="${HERDR_PLUGIN_ID:-dev.herdr-launcher}"

launch_dir="${PWD}"
pane_json="$("$herdr" pane current 2>/dev/null || true)"
if [[ -n "$pane_json" ]]; then
  if command -v jq >/dev/null 2>&1; then
    launch_dir="$(printf '%s' "$pane_json" |
      jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null || true)"
  else
    launch_dir="$(printf '%s' "$pane_json" |
      sed -n 's/.*"foreground_cwd":"\([^"]*\)".*/\1/p' | head -n 1)"
  fi
fi
launch_dir="${launch_dir:-$PWD}"

"$herdr" plugin pane open \
  --plugin "$plugin_id" \
  --entrypoint launcher \
  --env "LAUNCH_DIR=$launch_dir"
