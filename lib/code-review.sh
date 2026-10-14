#!/usr/bin/env bash

# Opens a code review in a new, focused Herdr tab running nvim.
# Usage: herdr_open_review <worktree_root> <report.out> <mode>
# Modes: report (the report only), quickfix (the .qf list only), both (the
# report with the quickfix list open beneath it; report only if no findings).
herdr_open_review() {
  local worktree_root="$1" report="$2" mode="$3"
  local herdr="${HERDR_BIN_PATH:-herdr}"
  local workspace_id="${HERDR_WORKSPACE_ID:-}"
  local quickfix="${report%.out}.qf"
  local label nvim_cmd pane_context tab_result pane_id

  # Reviews without findings (or older ones with no .qf file) open as just the report.
  if [[ "$mode" == both && ! -s "$quickfix" ]]; then
    mode=report
  fi
  if [[ "$mode" == quickfix && ! -s "$quickfix" ]]; then
    printf 'No quickfix findings found at %s\n' "$quickfix" >&2
    return 1
  fi

  # Names are filename-safe and the tab starts in the worktree root, so relative
  # names avoid escaping inside nvim's -c commands.
  local report_name quickfix_name
  report_name="$(basename "$report")"
  quickfix_name="$(basename "$quickfix")"
  case "$mode" in
    report)
      label="Code Review - $report_name"
      printf -v nvim_cmd 'exec nvim -- %q' "$report"
      ;;
    quickfix)
      label="Quickfix - $quickfix_name"
      printf -v nvim_cmd 'exec nvim -c copen -q %q' "$quickfix"
      ;;
    both)
      label="Code Review - $report_name"
      printf -v nvim_cmd "exec nvim -c %q -c copen -c %q -- %q" \
        "cgetfile $quickfix_name" "wincmd p" "$report_name"
      ;;
    *)
      printf 'Error: unknown code review mode: %s\n' "$mode" >&2
      return 1
      ;;
  esac

  if [[ -z "$workspace_id" ]]; then
    if ! pane_context="$("$herdr" pane current --current)"; then
      printf 'Error: could not get the calling pane context from Herdr\n' >&2
      return 1
    fi
    workspace_id="$(jq -r '.result.pane.workspace_id // empty' <<<"$pane_context")"
    if [[ -z "$workspace_id" ]]; then
      printf 'Error: Herdr did not return a workspace for the calling pane\n' >&2
      return 1
    fi
  fi

  if ! tab_result="$("$herdr" tab create \
    --workspace "$workspace_id" \
    --cwd "$worktree_root" \
    --label "$label" \
    --focus)"; then
    printf 'Error: could not create a Herdr tab for the code review\n' >&2
    return 1
  fi

  pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_result")"
  if [[ -z "$pane_id" ]]; then
    printf 'Error: Herdr did not return the new tab pane ID\n' >&2
    return 1
  fi

  if ! "$herdr" pane run "$pane_id" "$nvim_cmd"; then
    printf 'Error: could not open the code review in the new Herdr tab\n' >&2
    return 1
  fi
}
