#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '{"type":"run-script","label":"Fetch All Repos","payload":{"script":"~/dotfiles/bin/bin/fetch-all-repos.zsh"}}'
