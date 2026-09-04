#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '{"type":"run-script","label":"Delete Stale Herdr Worktrees","payload":{"script":"~/bin/delete-stale-herdr-worktrees.zsh"}}'
