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

groups=()
commands=()
payloads=()
max_group_width=0
while IFS= read -r json; do
  label="$(jq -r '.label // empty' <<<"$json" 2>/dev/null || true)"
  if [[ -n "$label" ]]; then
    group="${label%% - *}"
    command="${label#* - }"
    groups+=("$group")
    commands+=("$command")
    payloads+=("$json")
    if (( ${#group} > max_group_width )); then
      max_group_width=${#group}
    fi
  fi
done < <(
  for source in "$commands_dir"/*.sh; do
    if [[ -f "$source" ]]; then
      bash "$source"
    fi
  done 2>/dev/null
)

entries=()
for i in "${!groups[@]}"; do
  printf -v group_column "%-*s" "$max_group_width" "${groups[$i]}"
  entries+=($'\e[2m'"$group_column"$'\e[0m'$'\t'"${commands[$i]}"$'\t'"${payloads[$i]}")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  printf 'No commands available (is herdr running?)\n'
  read -r -n 1 -s -p "Press any key to close"
  exit 0
fi

selection="$(printf '%s\n' "${entries[@]}" |
  LC_ALL=C sort -t $'\t' -k1,1 -k2,2 |
  fzf --prompt="command > " --layout=reverse --ansi --delimiter=$'\t' --with-nth 1,2 --no-sort || true)"

if [[ -z "$selection" ]]; then
  exit 0
fi

IFS=$'\t' read -r _ _ json <<<"$selection"

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
