#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  '{"type":"run-script","label":"Add Music To Buy","payload":{"script":"~/bin/add-music-to-buy.zsh"}}'