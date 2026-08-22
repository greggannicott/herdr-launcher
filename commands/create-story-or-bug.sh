#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  '{"type":"run-script","label":"Create Story or Bug","payload":{"script":"~/bin/create-story-or-bug.zsh"}}'
