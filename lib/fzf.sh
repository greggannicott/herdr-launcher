#!/usr/bin/env bash

HERDR_FZF_COLOR="fg:#abb2bf,bg:#282c34,hl:#61afef,fg+:#abb2bf,bg+:#3e4451,hl+:#61afef,info:#56b6c2,prompt:#61afef,pointer:#e06c75,marker:#98c379,spinner:#c678dd,header:#e5c07b,border:#4b5263,label:#abb2bf,query:#abb2bf,scrollbar:#4b5263,gutter:#282c34"
HERDR_FZF_RESET=$'\033[0m'
HERDR_FZF_INFO=$'\033[38;2;86;182;194m'
HERDR_FZF_HEADER=$'\033[38;2;229;192;123m'
HERDR_FZF_MARKER=$'\033[38;2;152;195;121m'
HERDR_FZF_POINTER=$'\033[38;2;224;108;117m'
HERDR_FZF_FG=$'\033[38;2;171;178;191m'

herdr_fzf() {
  local prompt="$1"
  shift

  fzf --prompt="$prompt" --layout=reverse --ansi --no-sort \
    --color="$HERDR_FZF_COLOR" "$@"
}
