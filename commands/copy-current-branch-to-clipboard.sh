#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '{"type":"run-script","label":"Copy Current Branch to Clipboard","payload":{"script":"~/bin/copy-current-branch-to-clipboard.zsh"}}'
