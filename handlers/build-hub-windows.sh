#!/usr/bin/env bash
set -euo pipefail

job_name="Build_Hub_On_Windows_GitHUB"
parameter_names=(
  TargetBranch UI_Repository_Branch Run_Unit_tests Run_Integration_tests
  Build_the_installer Build_License_Generator Build_Diagnostic_Key_Generator
  UI_Production_Mode FIPS_Mode
)
prompts=(
  'Hub branch' 'Hub UI branch' 'Run unit tests' 'Run integration tests'
  'Build the installer' 'Build the license generator'
  'Build the diagnostic key generator' 'Build UI in production mode'
  'Build in FIPS mode'
)
summary_labels=(
  'Hub branch' 'Hub UI branch' 'Run unit tests' 'Run integration tests'
  'Build installer' 'Build license generator' 'Build diagnostic key generator'
  'UI production mode' 'FIPS mode'
)
defaults=(iisMultiSource main true true true true true true false)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/jenkins-build.sh"
