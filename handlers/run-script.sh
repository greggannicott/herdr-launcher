#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
if [[ -z "$json" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

script="$(jq -r '.payload.script // empty' <<<"$json")"
if [[ -z "$script" ]]; then
  printf 'Error: command JSON has no payload.script\n' >&2
  exit 1
fi

args=()
if [[ "$(jq -r '.payload.args // empty' <<<"$json")" != "" ]]; then
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(jq -r '.payload.args[]' <<<"$json")
fi

if [[ "$script" == "~"* ]]; then
  script="${script/#\~/$HOME}"
fi

if [[ ! -f "$script" ]]; then
  printf 'Error: script not found: %s\n' "$script" >&2
  exit 1
fi

if [[ ! -x "$script" ]]; then
  printf 'Error: script is not executable: %s\n' "$script" >&2
  exit 1
fi

"$script" "${args[@]}"
