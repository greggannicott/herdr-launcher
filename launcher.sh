#!/usr/bin/env bash
set -euo pipefail

plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: herdr-launcher requires jq\n'
  read -r -n 1 -s -p "Press any key to close"
  exit 1
fi

commands_dir="$plugin_root/commands"
handlers_dir="$plugin_root/handlers"

entries=()
while IFS= read -r json; do
  label="$(jq -r '.label // empty' <<<"$json" 2>/dev/null || true)"
  if [[ -n "$label" ]]; then
    entries+=("$label"$'\t'"$json")
  fi
done < <(
  for source in "$commands_dir"/*.sh; do
    if [[ -f "$source" ]]; then
      bash "$source"
    fi
  done 2>/dev/null
)

if [[ ${#entries[@]} -eq 0 ]]; then
  printf 'No commands available (is herdr running?)\n'
  read -r -n 1 -s -p "Press any key to close"
  exit 0
fi

selection="$(printf '%s\n' "${entries[@]}" |
  fzf --prompt="command > " --delimiter=$'\t' --with-nth 1 --no-sort || true)"

if [[ -z "$selection" ]]; then
  exit 0
fi

json="${selection#*$'\t'}"

type="$(jq -r '.type // empty' <<<"$json")"
handler="$handlers_dir/$type.sh"
if [[ ! -x "$handler" ]]; then
  printf 'No handler for command type: %s\n' "$type"
  read -r -n 1 -s -p "Press any key to close"
  exit 1
fi

if ! "$handler" "$json"; then
  read -r -n 1 -s -p "Press any key to close"
  exit 1
fi
