#!/usr/bin/env bash
set -euo pipefail

job_name="Build_Hub_RPMs_FromGitHub"
parameter_names=(
  IHub_TargetBranch HubUI_TargetBranch Hub_Version_Number Run_unit_tests
  Run_integration_tests Build_the_RPMs Install_the_built_version UI_Production_Mode
)
prompts=(
  'Hub branch' 'Hub UI branch' 'Hub version number' 'Run unit tests'
  'Run integration tests' 'Build the RPMs'
  'Install the built version on uk-r9-ib-003' 'Build UI in production mode'
)
summary_labels=(
  'Hub branch' 'Hub UI branch' 'Hub version' 'Run unit tests'
  'Run integration tests' 'Build RPMs' 'Install on uk-r9-ib-003' 'UI production mode'
)
defaults=(iisMultiSource main 1.4.5-1 true true false false true)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/jenkins-build.sh"
