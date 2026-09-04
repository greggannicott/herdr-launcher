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

has_args=false
if [[ "$(jq -r '.payload.args // empty' <<<"$json")" != "" ]]; then
  has_args=true
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

if [[ "$has_args" == true ]]; then
  args=()
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(jq -r '.payload.args[]' <<<"$json")
  "$script" "${args[@]}"
else
  "$script"
fi
