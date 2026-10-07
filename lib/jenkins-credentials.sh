#!/usr/bin/env bash

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
  printf '\nUse a Jenkins API token for an account allowed to access this job.\n' >&2
  printf 'Save the file and run the command again; no Herdr restart is needed.\n' >&2
  exit 1
fi

jenkins_write_auth_config() {
  local auth_line
  if ! auth_line="$(jq -nr 'env.JENKINS_USER + ":" + env.JENKINS_API_TOKEN | @json')"; then
    printf 'Error: could not prepare Jenkins authentication\n' >&2
    return 1
  fi
  printf 'user = %s\n' "$auth_line" >"$1"
}
