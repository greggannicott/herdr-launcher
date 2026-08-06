#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

json="${1:-}"
if [[ -z "$json" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

workspace_id="$(jq -r '.payload.workspace_id // empty' <<<"$json")"
if [[ -z "$workspace_id" ]]; then
  printf 'Error: command JSON has no payload.workspace_id\n' >&2
  exit 1
fi

"$herdr" workspace focus "$workspace_id"
