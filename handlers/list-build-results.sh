#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

for dependency in curl jq fzf; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Error: List Build Results requires %s on PATH\n' "$dependency" >&2
    exit 1
  fi
done
case "$(uname -s)" in
  Darwin) browser_command=open ;;
  *) browser_command=xdg-open ;;
esac
if ! command -v "$browser_command" >/dev/null 2>&1; then
  printf 'Error: install %s to open Jenkins build pages in your browser\n' "$browser_command" >&2
  exit 1
fi

plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$plugin_root/lib/fzf.sh"
source "$plugin_root/lib/jenkins-credentials.sh"

jenkins_url="https://v-jenkins.syncdi1.us.syncsort.com"
umask 077
temp_dir="$(mktemp -d)"
trap 'rm -f "$temp_dir/auth" "$temp_dir/Linux.json" "$temp_dir/Windows.json" "$temp_dir/rows"; rmdir "$temp_dir"' EXIT
jenkins_write_auth_config "$temp_dir/auth"
jobs=(Build_Hub_RPMs_FromGitHub Build_Hub_On_Windows_GitHUB)
platforms=(Linux Windows)
tree='builds[number,result,building,timestamp,url,actions[parameters[name,value]]]{0,25}'
for i in "${!jobs[@]}"; do
  platform="${platforms[$i]}"
  if ! status="$(curl --config "$temp_dir/auth" -sS --connect-timeout 10 --max-time 30 \
    --get --data-urlencode "tree=$tree" -o "$temp_dir/$platform.json" \
    -w '%{http_code}' "$jenkins_url/job/${jobs[$i]}/api/json")"; then
    printf 'Error: could not fetch %s Jenkins build results\n' "$platform" >&2
    exit 1
  fi
  if [[ "$status" != 200 ]]; then
    printf 'Error: %s Jenkins build results request failed with HTTP %s. Check Jenkins connectivity and account read permission.\n' "$platform" "$status" >&2
    exit 1
  fi
  if ! jq -e '
    (.builds | type == "array") and
    all(.builds[];
      (.number | type == "number") and (.timestamp | type == "number") and
      (.building | type == "boolean") and
      (.result == null or (.result | type == "string")))
  ' "$temp_dir/$platform.json" >/dev/null; then
    printf 'Error: Jenkins returned invalid %s build results\n' "$platform" >&2
    exit 1
  fi
done

if ! jq -j -s --arg base "$jenkins_url" '
  def pad($width): tostring | . + (" " * ([0, $width - length] | max));
  now as $now |
  def age:
    ([$now - (.timestamp / 1000), 0] | max | floor) as $seconds |
    if $seconds < 60 then "just now"
    elif $seconds < 3600 then "\($seconds / 60 | floor)m ago"
    elif $seconds < 86400 then "\($seconds / 3600 | floor)h ago"
    else "\($seconds / 86400 | floor)d ago"
    end;
  def row: (.platform | pad(8)) + "  " + (.number | pad(7)) + "  " +
    ((.timestamp / 1000 | floor | strftime("%Y-%m-%d %H:%M")) | pad(16)) +
    "  " + ((age) | pad(12)) +
    "  " + ((if .building then "RUNNING" else .result // "UNKNOWN" end) | pad(12)) +
    "  " + .branch + "\t" + .link + "\u0000";
  [to_entries[] |
    (if .key == 0 then {platform: "Linux", job: "Build_Hub_RPMs_FromGitHub", branch_key: "IHub_TargetBranch"}
     else {platform: "Windows", job: "Build_Hub_On_Windows_GitHUB", branch_key: "TargetBranch"} end) as $job |
    .value.builds[] | . + $job |
    .branch = ([.actions[]?.parameters[]? | select(.name == $job.branch_key) | .value][0] // "-"
      | tostring | gsub("[\u0000-\u001f\u007f]"; " ")) |
    .link = ($base + "/job/" + .job + "/" + (.number | tostring) + "/")
  ] | sort_by(.timestamp) | reverse |
  if length == 0 then empty else
    (("Platform" | pad(8)) + "  " + ("Build" | pad(7)) + "  " +
      ("Date/Time (UTC)" | pad(16)) + "  " + ("Started" | pad(12)) +
      "  " + ("Result" | pad(12)) +
      "  Hub Branch\u0000"),
    (.[] | row)
  end
' "$temp_dir/Linux.json" "$temp_dir/Windows.json" >"$temp_dir/rows"; then
  printf 'Error: could not format Jenkins build results\n' >&2
  exit 1
fi

if [[ ! -s "$temp_dir/rows" ]]; then
  printf 'No Linux or Windows builds found.\n'
  read -r -n 1 -s -p "Press any key to close"
  exit 0
fi
if selected="$(herdr_fzf "Build results> " --no-hscroll --read0 --print0 --delimiter=$'\t' \
  --with-nth=1 --header-lines=1 --header-lines-border=inline --style=full <"$temp_dir/rows" | tr -d '\000')"; then
  IFS=$'\t' read -r _ url <<<"$selected"
  if [[ "$url" != "$jenkins_url/job/"* ]]; then
    printf 'Error: invalid Jenkins build selection\n' >&2
    exit 1
  fi
  if ! "$browser_command" "$url"; then
    printf 'Error: could not open the selected Jenkins build in your browser\n' >&2
    exit 1
  fi
else
  status=$?
  case "$status" in
    1|130) exit 0 ;;
    *) printf 'Error: build results picker failed (exit %s)\n' "$status" >&2; exit "$status" ;;
  esac
fi
