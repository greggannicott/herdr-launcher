#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '{"type":"run-script","label":"Open Linear ID from Clipboard","payload":{"script":"~/bin/open-linear-id.zsh","args":["cb"]}}'
