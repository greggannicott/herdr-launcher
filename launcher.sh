#!/usr/bin/env bash
set -euo pipefail

one_dark_theme="fg:#abb2bf,bg:#282c34,hl:#61afef,fg+:#abb2bf,bg+:#3e4451,hl+:#61afef,info:#56b6c2,prompt:#61afef,pointer:#e06c75,marker:#98c379,spinner:#c678dd,header:#e5c07b,border:#4b5263,label:#abb2bf,query:#abb2bf,scrollbar:#4b5263,gutter:#282c34"

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
  fzf --prompt="> " --layout=reverse --ansi --delimiter=$'\t' --with-nth 1,2 --no-sort \
    --color="$one_dark_theme" || true)"

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
