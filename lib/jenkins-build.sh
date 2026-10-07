#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
if [[ -z "$json" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Error: Jenkins builds require %s on PATH\n' "$dependency" >&2
    exit 1
  fi
done

source "$(dirname "${BASH_SOURCE[0]}")/jenkins-credentials.sh"

jenkins_url="https://v-jenkins.syncdi1.us.syncsort.com"
job_url="$jenkins_url/job/$job_name"

prompt_value() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  printf '%s' "${value:-$default}"
}

prompt_boolean() {
  local prompt="$1"
  local default="$2"
  local choice
  local default_label="y/N"
  if [[ "$default" == true ]]; then
    default_label="Y/n"
  fi

  while true; do
    read -r -p "$prompt [$default_label]: " choice
    choice="${choice:-$default_label}"
    case "$choice" in
      [Yy]|[Yy][Ee][Ss]) printf 'true'; return ;;
      [Nn]|[Nn][Oo]) printf 'false'; return ;;
      "$default_label") [[ "$default" == true ]] && printf 'true' || printf 'false'; return ;;
      *) printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

hub_branch_default="${defaults[0]}"
launch_dir="${LAUNCH_DIR:-$PWD}"
if branch="$(git -C "$launch_dir" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  hub_branch_default="$branch"
else
  printf 'Warning: could not determine the current Git branch in %s (not a Git worktree, detached HEAD, or Git unavailable).\n' "$launch_dir" >&2
  printf 'Using %s as the Hub branch default; enter the desired branch at the prompt.\n' "$hub_branch_default" >&2
fi

defaults[0]="$hub_branch_default"
values=()
build_parameters=()
for i in "${!parameter_names[@]}"; do
  if [[ "${defaults[$i]}" == true || "${defaults[$i]}" == false ]]; then
    value="$(prompt_boolean "${prompts[$i]}" "${defaults[$i]}")"
  else
    value="$(prompt_value "${prompts[$i]}" "${defaults[$i]}")"
  fi
  values+=("$value")
  build_parameters+=("${parameter_names[$i]}=$value")
done

printf '\n%s\n' "$job_name"
for i in "${!values[@]}"; do
  printf '  %-23s %s\n' "${summary_labels[$i]}:" "${values[$i]}"
done
read -r -p $'\nStart this Jenkins build? [y/N]: ' confirmation
case "$confirmation" in
  [Yy]|[Yy][Ee][Ss]) ;;
  *) printf 'Build cancelled.\n'; exit 0 ;;
esac

umask 077
auth_config="$(mktemp)"
headers_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f "$auth_config" "$headers_file" "$response_file"' EXIT

jenkins_write_auth_config "$auth_config"

if ! crumb_response="$(curl --config "$auth_config" -sS \
  -w $'\n%{http_code}' "$jenkins_url/crumbIssuer/api/json")"; then
  printf 'Error: could not contact the Jenkins CSRF crumb endpoint\n' >&2
  exit 1
fi
crumb_status="${crumb_response##*$'\n'}"
crumb_body="${crumb_response%$'\n'*}"
crumb_field=""
crumb=""
case "$crumb_status" in
  200)
    if ! jq -e '
      (.crumbRequestField | type == "string" and length > 0)
      and (.crumb | type == "string" and length > 0)
    ' >/dev/null <<<"$crumb_body"; then
      printf 'Error: Jenkins returned an invalid CSRF crumb response\n' >&2
      exit 1
    fi
    crumb_field="$(jq -r '.crumbRequestField' <<<"$crumb_body")"
    crumb="$(jq -r '.crumb' <<<"$crumb_body")"
    ;;
  404)
    ;;
  *)
    printf 'Error: Jenkins CSRF crumb request failed with HTTP %s\n' "$crumb_status" >&2
    [[ -z "$crumb_body" ]] || printf '%s\n' "$crumb_body" >&2
    exit 1
    ;;
esac

curl_args=(
  --config "$auth_config"
  -sS
  -o "$response_file"
  -D "$headers_file"
  -w '%{http_code}'
  -X POST
)
for parameter in "${build_parameters[@]}"; do
  curl_args+=(--data-urlencode "$parameter")
done
if [[ -n "$crumb_field" ]]; then
  curl_args+=(--header "$crumb_field: $crumb")
fi

if ! build_status="$(curl "${curl_args[@]}" "$job_url/buildWithParameters")"; then
  printf 'Error: Jenkins build request failed before receiving an HTTP response\n' >&2
  exit 1
fi
case "$build_status" in
  200|201)
    printf 'Jenkins accepted the build request (HTTP %s).\n' "$build_status"
    queue_url="$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$headers_file" | tr -d '\r' | tail -n 1)"
    if [[ -n "$queue_url" ]]; then
      printf 'Queue: %s\n' "$queue_url"
    fi
    ;;
  *)
    printf 'Error: Jenkins rejected the build request (HTTP %s)\n' "$build_status" >&2
    if [[ -s "$response_file" ]]; then
      cat "$response_file" >&2
      printf '\n' >&2
    fi
    exit 1
    ;;
esac
