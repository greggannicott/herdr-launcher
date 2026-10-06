#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
launch_dir="${LAUNCH_DIR:-$PWD}"
plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$plugin_root/lib/fzf.sh"

if [[ -z "$json" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  printf 'Error: open-code-review requires fzf on PATH\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: open-code-review requires jq on PATH\n' >&2
  exit 1
fi

if ! command -v nvim >/dev/null 2>&1; then
  printf 'Error: open-code-review requires nvim on PATH\n' >&2
  exit 1
fi

workspace_id="${HERDR_WORKSPACE_ID:-}"
herdr="${HERDR_BIN_PATH:-herdr}"
if [[ -z "$workspace_id" ]]; then
  if ! pane_context="$("$herdr" pane current --current)"; then
    printf 'Error: could not get the calling pane context from Herdr\n' >&2
    exit 1
  fi
  workspace_id="$(jq -r '.result.pane.workspace_id // empty' <<<"$pane_context")"
  if [[ -z "$workspace_id" ]]; then
    printf 'Error: Herdr did not return a workspace for the calling pane\n' >&2
    exit 1
  fi
fi

if ! worktree_root="$(git -C "$launch_dir" rev-parse --show-toplevel 2>/dev/null)"; then
  printf 'Error: could not find the worktree root from %s\n' "$launch_dir" >&2
  exit 1
fi

reviews=()
review_timestamps=()
while IFS= read -r -d '' review; do
  filename="$(basename "$review")"
  if [[ "$filename" =~ ^code-review-([A-Za-z0-9_-]+)-([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})-([0-9]{2})\.([^.]+)\.out$ ]]; then
    review_type="${BASH_REMATCH[1]}"
    date="${BASH_REMATCH[2]}"
    hour="${BASH_REMATCH[3]}"
    minute="${BASH_REMATCH[4]}"
    status="${BASH_REMATCH[5]}"
  elif [[ "$filename" =~ ^code-review-([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})-([0-9]{2})\.([^.]+)\.out$ ]]; then
    review_type="legacy"
    date="${BASH_REMATCH[1]}"
    hour="${BASH_REMATCH[2]}"
    minute="${BASH_REMATCH[3]}"
    status="${BASH_REMATCH[4]}"
  else
    printf 'Error: code review filename does not match the expected format: %s\n' "$filename" >&2
    exit 1
  fi
  time="$hour:$minute"
  timestamp="${date//-/}${hour}${minute}"
  case "$status" in
    accept|accepted|approve|approved) status_color="$HERDR_FZF_MARKER" ;;
    reject|rejected) status_color="$HERDR_FZF_POINTER" ;;
    *) status_color="$HERDR_FZF_FG" ;;
  esac
  printf -v row '%s%-14s%s  %s%-10s%s  %s%-5s%s  %s%s%s' \
    "$HERDR_FZF_FG" "$review_type" "$HERDR_FZF_RESET" \
    "$HERDR_FZF_INFO" "$date" "$HERDR_FZF_RESET" \
    "$HERDR_FZF_HEADER" "$time" "$HERDR_FZF_RESET" \
    "$status_color" "$status" "$HERDR_FZF_RESET"
  insert_at=0
  while (( insert_at < ${#review_timestamps[@]} )) &&
    [[ ! "$timestamp" > "${review_timestamps[$insert_at]}" ]]; do
    ((insert_at += 1))
  done
  review_timestamps=(
    "${review_timestamps[@]:0:insert_at}"
    "$timestamp"
    "${review_timestamps[@]:insert_at}"
  )
  reviews=(
    "${reviews[@]:0:insert_at}"
    "$row"$'\t'"$review"
    "${reviews[@]:insert_at}"
  )
done < <(find "$worktree_root" -maxdepth 1 -type f -name '*.out' -print0)

if [[ ${#reviews[@]} -eq 0 ]]; then
  printf 'No code review files (*.out) found in %s\n' "$worktree_root"
  read -r -n 1 -s -p "Press any key to close"
  exit 0
fi

printf -v header '%s%-14s%s  %s%-10s%s  %s%-5s%s  %s%s%s' \
  "$HERDR_FZF_HEADER" "Type" "$HERDR_FZF_RESET" \
  "$HERDR_FZF_INFO" "Date" "$HERDR_FZF_RESET" \
  "$HERDR_FZF_HEADER" "Time" "$HERDR_FZF_RESET" \
  "$HERDR_FZF_HEADER" "Status" "$HERDR_FZF_RESET"

printf -v selected ''
if ! IFS= read -r -d '' selected < <(
  printf '%s\0' "$header" "${reviews[@]}" |
    herdr_fzf "Code review> " --read0 --print0 --delimiter=$'\t' \
      --with-nth=1 --header-lines=1 --header-lines-border=inline --style=full
); then
  exit 0
fi

IFS=$'\t' read -r _ selected <<<"$selected"
if [[ ! -f "$selected" ]]; then
  printf 'Error: selected code review no longer exists: %s\n' "$selected" >&2
  exit 1
fi

label="Code Review - $(basename "$selected")"
if ! tab_result="$("$herdr" tab create \
  --workspace "$workspace_id" \
  --cwd "$worktree_root" \
  --label "$label" \
  --focus)"; then
  printf 'Error: could not create a Herdr tab for the code review\n' >&2
  exit 1
fi

pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_result")"
if [[ -z "$pane_id" ]]; then
  printf 'Error: Herdr did not return the new tab pane ID\n' >&2
  exit 1
fi

printf -v quoted_review '%q' "$selected"
if ! "$herdr" pane run "$pane_id" "exec nvim -- $quoted_review"; then
  printf 'Error: could not open the code review in the new Herdr tab\n' >&2
  exit 1
fi
