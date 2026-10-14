#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
if ! jq -e '
  (.payload.prompt | type == "string" and length > 0 and (contains("\u0000") | not))
  and ((.payload | if has("args") then .args else [] end) |
    type == "array" and all(.[]; type == "string" and (contains("\u0000") | not)))
  and ((.payload | if has("review_type") then .review_type else "" end) |
    type == "string" and test("^[A-Za-z0-9_-]*$"))
' >/dev/null <<<"$json"; then
  printf 'Error: command JSON requires a nonempty payload.prompt, optional string array payload.args, and optional filename-safe payload.review_type\n' >&2
  exit 1
fi

if ! command -v copilot >/dev/null 2>&1; then
  printf 'Error: copilot-report requires copilot on PATH\n' >&2
  exit 1
fi

cd "${LAUNCH_DIR:-$PWD}"

plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$plugin_root/lib/fzf.sh"
source "$plugin_root/lib/code-review.sh"

# Shows the findings summary for a finished review and offers to open it.
review_summary() {
  local report quickfix total severity count line="" choice
  local -a reports=("$worktree_root/code-review-${review_type}-${review_date}-${review_time}."*.out)
  report="${reports[0]}"
  if [[ ! -f "$report" ]] || ! command -v fzf >/dev/null 2>&1; then
    printf 'Review report not found or fzf unavailable; nothing to open.\n'
    read -r -n 1 -s -p "Press any key to close"
    return 0
  fi
  quickfix="${report%.out}.qf"
  total=0
  [[ -f "$quickfix" ]] && total="$(grep -c . "$quickfix" || true)"

  printf '%s%s%s\n' "$HERDR_FZF_HEADER" "Review complete: $(basename "$report")" "$HERDR_FZF_RESET"
  if (( total == 0 )); then
    printf '%sNo issues found.%s\n\n' "$HERDR_FZF_MARKER" "$HERDR_FZF_RESET"
  else
    for severity in Critical High Medium Low; do
      count="$(grep -c "\\[$severity\\]" "$quickfix" || true)"
      (( count > 0 )) && line+="${line:+, }$count $severity"
    done
    printf '%s%s issue(s) found%s%s%s\n\n' "$HERDR_FZF_POINTER" "$total" \
      "${line:+ ($line)}" "$HERDR_FZF_RESET" ""
  fi

  local open_label="View full report in Neovim" open_mode=report
  if (( total > 0 )); then
    open_label="View report and suggestions in Neovim (Quickfix List)"
    open_mode=both
  fi
  if ! choice="$(printf '%s\n' "$open_label" "Close" |
    herdr_fzf "Next> " --no-multi --height=~6)"; then
    return 0
  fi
  if [[ "$choice" == "$open_label" ]]; then
    herdr_open_review "$worktree_root" "$report" "$open_mode" || return 1
  fi
}

args=()
while IFS= read -r -d '' arg; do
  args+=("$arg")
done < <(jq -j '(.payload.args // [])[] | ., "\u0000"' <<<"$json")

prompt="$(jq -r '.payload.prompt' <<<"$json")"
review_type="$(jq -r '.payload.review_type // empty' <<<"$json")"
if [[ -n "$review_type" ]]; then
  if ! worktree_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf 'Error: code review reports must run inside a git worktree\n' >&2
    exit 1
  fi
  review_date="$(date +%F)"
  review_time="$(date +%H-%M)"
  review_base="$worktree_root/code-review-${review_type}-${review_date}-${review_time}.{status}"
  review_filename="${review_base}.out"
  quickfix_filename="${review_base}.qf"
  prompt+=$'\n\n'
  prompt+="Save the complete review report at ${review_filename}. Replace {status} with reject if there are actionable findings, or accept if there are none. Keep the type, date, and time in the filename unchanged."
  prompt+=$'\n\n'
  prompt+="Also save a Neovim quickfix file at ${quickfix_filename}, using the same {status} value as the report. Write one line per actionable finding, in exactly this format: path:line:1: type: [Severity] title. Use the repository-relative path and line from the finding, a single-line title, and type error for Critical or High, warning for Medium, or info for Low. Output only these lines with no headings, blank lines, or extra text. If there are no findings, create an empty file."
fi
label="$(jq -r '.label | select(type == "string" and length > 0)' <<<"$json")"
printf '%s\n' "${label:-$prompt}"
printf 'Directory: %s\nPrompt: %s\n\n' "$PWD" "$prompt"
printf 'Starting Copilot. Report output will appear below; this may take a few moments.\n\n'
args+=(-p "$prompt")
if copilot "${args[@]}"; then
  printf '\n'
  if [[ -n "$review_type" ]]; then
    review_summary || exit 1
  else
    read -r -n 1 -s -p "Press any key to close"
  fi
else
  status=$?
  printf '\nError: Copilot exited with status %s\n' "$status" >&2
  exit "$status"
fi
