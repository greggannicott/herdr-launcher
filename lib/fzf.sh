#!/usr/bin/env bash

HERDR_FZF_COLOR="fg:#abb2bf,bg:#282c34,hl:#61afef,fg+:#abb2bf,bg+:#3e4451,hl+:#61afef,info:#56b6c2,prompt:#61afef,pointer:#e06c75,marker:#98c379,spinner:#c678dd,header:#e5c07b,border:#4b5263,label:#abb2bf,query:#abb2bf,scrollbar:#4b5263,gutter:#282c34"

herdr_fzf() {
  local prompt="$1"
  shift

  fzf --prompt="$prompt" --layout=reverse --ansi --no-sort \
    --color="$HERDR_FZF_COLOR" "$@"
}
