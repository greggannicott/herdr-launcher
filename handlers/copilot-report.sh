#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
if ! jq -e '
  (.payload.prompt | type == "string" and length > 0 and (contains("\u0000") | not))
  and ((.payload | if has("args") then .args else [] end) |
    type == "array" and all(.[]; type == "string" and (contains("\u0000") | not)))
' >/dev/null <<<"$json"; then
  printf 'Error: command JSON requires a nonempty payload.prompt and optional string array payload.args\n' >&2
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
