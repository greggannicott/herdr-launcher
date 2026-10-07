#!/usr/bin/env bash
set -euo pipefail

json="${1:-}"
if [[ -z "$json" ]]; then
  printf 'Error: no command JSON provided\n' >&2
  exit 1
fi

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Error: build-hub-rpms requires %s on PATH\n' "$dependency" >&2
    exit 1
  fi
done

credentials_file="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-launcher/jenkins.env"
if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_API_TOKEN:-}" ]]; then
  if [[ -f "$credentials_file" ]]; then
    source "$credentials_file"
  fi
fi

if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_API_TOKEN:-}" ]]; then
  printf 'Error: missing or empty Jenkins credentials:\n' >&2
  for variable in JENKINS_USER JENKINS_API_TOKEN; do
    if [[ -z "${!variable:-}" ]]; then
      printf '  %s\n' "$variable" >&2
    fi
  done
  printf '\nTo resolve this, create or edit this credentials file (outside the repository):\n  %s\n' "$credentials_file" >&2
  printf '\nRun these commands in your terminal:\n' >&2
  printf '  mkdir -p %q\n' "$(dirname "$credentials_file")" >&2
  printf '  (umask 077; touch %q)\n' "$credentials_file" >&2
  printf '  chmod 600 %q\n' "$credentials_file" >&2
  printf '\nAdd or update these lines in the file, replacing the placeholders with nonempty credentials:\n' >&2
  printf "  export JENKINS_USER='your-jenkins-user'\n  export JENKINS_API_TOKEN='your-api-token'\n" >&2
  printf '\nUse a Jenkins API token for an account allowed to build this job.\n' >&2
  printf 'Save the file and run the command again; no Herdr restart is needed.\n' >&2
  exit 1
fi

jenkins_url="https://v-jenkins.syncdi1.us.syncsort.com"
job_url="$jenkins_url/job/Build_Hub_RPMs_FromGitHub"

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

hub_branch_default="iisMultiSource"
launch_dir="${LAUNCH_DIR:-$PWD}"
if branch="$(git -C "$launch_dir" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  hub_branch_default="$branch"
else
  printf 'Warning: could not determine the current Git branch in %s (not a Git worktree, detached HEAD, or Git unavailable).\n' "$launch_dir" >&2
  printf 'Using %s as the Hub branch default; enter the desired branch at the prompt.\n' "$hub_branch_default" >&2
fi

hub_branch="$(prompt_value 'Hub branch' "$hub_branch_default")"
ui_branch="$(prompt_value 'Hub UI branch' 'main')"
version="$(prompt_value 'Hub version number' '1.4.5-1')"
run_unit_tests="$(prompt_boolean 'Run unit tests' true)"
run_integration_tests="$(prompt_boolean 'Run integration tests' true)"
build_rpms="$(prompt_boolean 'Build the RPMs' false)"
install_version="$(prompt_boolean 'Install the built version on uk-r9-ib-003' false)"
production_mode="$(prompt_boolean 'Build UI in production mode' true)"

printf '\nBuild_Hub_RPMs_FromGitHub\n'
printf '  Hub branch:             %s\n' "$hub_branch"
printf '  Hub UI branch:          %s\n' "$ui_branch"
printf '  Hub version:            %s\n' "$version"
printf '  Run unit tests:         %s\n' "$run_unit_tests"
printf '  Run integration tests:  %s\n' "$run_integration_tests"
printf '  Build RPMs:             %s\n' "$build_rpms"
printf '  Install on uk-r9-ib-003: %s\n' "$install_version"
printf '  UI production mode:     %s\n' "$production_mode"
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

if ! auth_line="$(jq -nr 'env.JENKINS_USER + ":" + env.JENKINS_API_TOKEN | @json')"; then
  printf 'Error: could not prepare Jenkins authentication\n' >&2
  exit 1
fi
printf 'user = %s\n' "$auth_line" >"$auth_config"

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
  --data-urlencode "IHub_TargetBranch=$hub_branch"
  --data-urlencode "HubUI_TargetBranch=$ui_branch"
  --data-urlencode "Hub_Version_Number=$version"
  --data-urlencode "Run_unit_tests=$run_unit_tests"
  --data-urlencode "Run_integration_tests=$run_integration_tests"
  --data-urlencode "Build_the_RPMs=$build_rpms"
  --data-urlencode "Install_the_built_version=$install_version"
  --data-urlencode "UI_Production_Mode=$production_mode"
)
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
