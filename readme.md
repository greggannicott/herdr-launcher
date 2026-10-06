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
The fzf picker uses a One Dark-inspired color palette.

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

### Copilot reports

The `copilot-report` type runs Copilot non-interactively in the directory where
the launcher was opened. It requires `copilot` on `PATH`, shows the selected
command, directory, and prompt before starting, displays its output as it runs,
and keeps the popup open until a key is pressed. Failures display
an error and also wait for a key through the launcher's error handling.

`Review branch against origin/iisMultiSource` runs:

```sh
copilot --agent code-reviewer --allow-tool 'shell(git:*)' --allow-tool 'write' -p "Review branch compared to origin/iisMultiSource"
```

Additional report commands can reuse the same handler by supplying a nonempty
`prompt` and an optional array of Copilot arguments (each argument is passed
literally, without shell expansion):

```json
{"type":"copilot-report","label":"Review current changes","payload":{"prompt":"Review uncommitted changes","args":["--agent","code-reviewer","--allow-tool","shell(git:*)","--allow-tool","write"]}}
```
