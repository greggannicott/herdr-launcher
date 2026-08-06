#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

list="$("$herdr" workspace list 2>/dev/null || true)"
if [[ -z "$list" ]]; then
  exit 0
fi

printf '%s' "$list" | jq -r '
  try (
    .result.workspaces[]
    | select(.focused == false)
    | {
        type: "herdr-workspace-switch",
        label: ("Switch to " + .label),
        payload: { workspace_id: .workspace_id }
      }
    | @json
  ) catch empty
'
