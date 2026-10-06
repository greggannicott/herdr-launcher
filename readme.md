# herdr-launcher

A herdr plugin launcher. Open it, pick a command from a fuzzy list, and it runs.

## Install

Link the local plugin:

```
herdr plugin link /path/to/herdr-launcher
```

Requires herdr >= 0.7.5, `jq`, and fzf >= 0.72.

## Usage

Trigger the `dev.herdr-launcher.open-launcher` action (from herdr's action menu, or a bound key) to open the launcher popup. Type to filter, Enter to run, Escape to cancel. The popup closes when the selected command finishes.
The fzf picker uses a One Dark-inspired color palette.
All launcher pickers use the shared `herdr_fzf` helper in `lib/fzf.sh` for
consistent layout and colors; selector-specific fzf options are passed through
to that helper.

## How it works

Command **sources** (`commands/*.sh`) emit NDJSON, one command object per line:

```json
{"type":"herdr-workspace-switch","label":"Open Session - Switch to dotfiles","payload":{"workspace_id":"w1"}}
```

A label is `"<group> - <command>"`. The launcher splits it on the first `" - "` and shows the two parts as aligned columns, the group dimmed and the command in normal text, with the input at the top of the list. Only the first separator splits, so a command may contain `" - "` itself. A label with no separator is shown twice, once per column, so every source should include one.

Entries are sorted case-insensitively by group, then command.

`launcher.sh` gathers every source's output and, on selection, dispatches to `handlers/<type>.sh`, passing the JSON as the first argument. Adding a command type is two files: a source emitting the NDJSON above and a handler that consumes the JSON.

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

`Review Staged Changes` uses the same Copilot reviewer to review the staged changes.
The staged review saves as type `staged`; the branch review against
`origin/iisMultiSource` saves as type `iisMultiSource`. Review commands save
their complete report in the worktree root using a filename that identifies
the review type, timestamp, and outcome—for example,
`code-review-staged-2026-10-06-17-03.reject.out`.

`Open Code Review for this Worktree` lists `*.out` files in the worktree root.
Files use the format `code-review-{type}-{yyyy-mm-dd}-{hh-mm}.{status}.out`.
Older files without a type remain listed as `legacy`. The picker shows Type,
Date, Time, and Status columns with an inline header. Selecting a review creates
and focuses a Herdr tab in that worktree and opens the file in `nvim`.

Additional report commands can reuse the same handler by supplying a nonempty
`prompt` and an optional array of Copilot arguments (each argument is passed
literally, without shell expansion):

```json
{"type":"copilot-report","label":"Review current changes","payload":{"prompt":"Review uncommitted changes","args":["--agent","code-reviewer","--allow-tool","shell(git:*)","--allow-tool","write"]}}
```
