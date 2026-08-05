#!/usr/bin/env bash
set -euo pipefail

launch_dir="${LAUNCH_DIR:-${PWD}}"
cd "$launch_dir" 2>/dev/null || exit 1

dirs=()
while IFS= read -r d; do
  dirs+=("$d")
done < <(find . -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

if [[ ${#dirs[@]} -eq 0 ]]; then
  printf 'No subdirectories in %s\n' "$launch_dir"
  read -r -n 1 -s -p "Press any key to close"
  exit 0
fi

selection="$(printf '%s\n' "${dirs[@]}" |
  fzf --prompt="command > " --header="$launch_dir" --no-sort || true)"

if [[ -n "$selection" ]]; then
  printf '\nSelected: %s/%s\n' "$launch_dir" "$selection"
  read -r -n 1 -s -p "Press any key to close"
fi
