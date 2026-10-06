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
  review_filename="$worktree_root/code-review-${review_type}-${review_date}-${review_time}.{status}.out"
  prompt+=$'\n\n'
  prompt+="Save the complete review report at ${review_filename}. Replace {status} with reject if there are actionable findings, or accept if there are none. Keep the type, date, and time in the filename unchanged."
fi
label="$(jq -r '.label | select(type == "string" and length > 0)' <<<"$json")"
printf '%s\n' "${label:-$prompt}"
printf 'Directory: %s\nPrompt: %s\n\n' "$PWD" "$prompt"
printf 'Starting Copilot. Report output will appear below; this may take a few moments.\n\n'
args+=(-p "$prompt")
if copilot "${args[@]}"; then
  printf '\n'
  read -r -n 1 -s -p "Press any key to close"
else
  status=$?
  printf '\nError: Copilot exited with status %s\n' "$status" >&2
  exit "$status"
fi
