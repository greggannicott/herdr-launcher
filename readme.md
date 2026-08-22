# herdr-launcher

A herdr plugin launcher. Open it, pick a command from a fuzzy list, and it runs.

## Install

Link the local plugin:

```
herdr plugin link /path/to/herdr-launcher
```

Requires herdr >= 0.7.5 and `jq`.

## Usage

Trigger the `dev.herdr-launcher.open-launcher` action (from herdr's action menu, or a bound key) to open the launcher popup. Type to filter, Enter to run, Escape to cancel. The popup closes when the selected command finishes.

## How it works

Command **sources** (`commands/*.sh`) emit NDJSON, one command object per line:

```json
{"type":"herdr-workspace-switch","label":"Switch to dotfiles","payload":{"workspace_id":"w1"}}
```

`launcher.sh` gathers every source's output, shows the labels in fzf, and on selection dispatches to `handlers/<type>.sh`, passing the JSON as the first argument. Adding a command type is two files: a source emitting the NDJSON above and a handler that consumes the JSON.

### Workspace switching

`commands/herdr-workspaces.sh` lists herdr workspaces (excluding the focused one) and `handlers/herdr-workspace-switch.sh` runs `herdr workspace focus <workspace_id>`.

### Script-backed commands

The `run-script` type executes an external script. A command source just points at the script:

```json
{"type":"run-script","label":"Create Story or Bug","payload":{"script":"~/bin/create-story-or-bug.zsh"}}
```

A leading `~` is expanded to `$HOME`. The script must exist and be executable (its own shebang picks the interpreter), and the popup stays open until it finishes.
