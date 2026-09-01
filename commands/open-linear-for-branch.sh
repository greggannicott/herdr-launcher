#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '{"type":"run-script","label":"Open Linear for Current Branch","payload":{"script":"~/bin/open-linear-for-branch.zsh"}}'