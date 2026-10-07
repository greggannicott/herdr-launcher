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

### Jenkins Hub builds

`Build - Generate Linux Build via Jenkins` asks for the job's branch, version, test, RPM,
installation, and UI-mode parameters, then shows a summary for confirmation
before requesting the Jenkins build. The Hub branch defaults to the current
Git branch in the directory where the launcher was opened (`LAUNCH_DIR`, or the
current directory when run directly). If the branch cannot be determined, the
handler warns and falls back to `iisMultiSource`. Other text inputs retain their
displayed defaults when left blank. Building RPMs and installation on
`uk-r9-ib-003` default to off and must be explicitly enabled.

The command requires `curl`, `jq`, and `JENKINS_USER` plus `JENKINS_API_TOKEN`.
If either variable is missing from the launcher's environment, the handler
sources `${XDG_CONFIG_HOME:-$HOME/.config}/herdr-launcher/jenkins.env`.
This file is loaded only when this command runs; the launcher does not load
interactive shell startup files such as `.zshrc.local`. Create the credentials
file with permissions restricted to your user:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-launcher"
(umask 077; touch "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-launcher/jenkins.env")
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-launcher/jenkins.env"
```

Add these exports to that file, replacing the placeholders with your credentials:

```sh
export JENKINS_USER='your-jenkins-user'
export JENKINS_API_TOKEN='your-api-token'
```

If either credential is still missing or empty, the command names the missing
variables and prints the file path, setup commands, and example exports.
Save the credentials file and retry; no Herdr restart is needed.

`Build - Generate Windows Build via Jenkins` runs the
`Build_Hub_On_Windows_GitHUB` job. It prompts for Hub and UI branches, unit and
integration tests, installer creation, license generator, diagnostic key
generator, UI production mode, and FIPS mode. The Hub branch uses the same
launch-directory default as the Linux command. The UI branch defaults to
`main`; tests, installer, both generators, and production mode default to on,
while FIPS mode defaults to off, matching the Windows job's defaults.
There is no Windows version-number input.

Both commands share the prompts, confirmation, credentials-file loading, CSRF
handling, and build submission in `lib/jenkins-build.sh`. Job-specific parameter
names and defaults live in their handlers. The Windows command uses the same
credentials file and does not load interactive shell startup files.

`Build - List Build Results` fetches the latest 25 builds from each job and
combines them in a newest-first fzf table with Platform, Build, Date/Time (UTC),
Started, Result, and Hub Branch columns. Started shows the time since the build started
as `just now`, minutes, hours, or days ago, calculated when the list is fetched.
In-progress builds display `RUNNING`.
Horizontal scrolling is disabled to keep columns aligned while filtering;
matches beyond the visible width still filter results but may be off-screen.
Select a row to open that build's Jenkins page in your default browser;
Escape cancels. The command uses the same credentials file, requires account
read access to both jobs, and reports API failures rather than showing a
partial list. Browser opening uses `open` on macOS and `xdg-open` on Linux.
Credential loading and authentication are shared in `lib/jenkins-credentials.sh`.

Use a Jenkins API token for an account with
permission to build this job; the token is not stored in the plugin or passed
as a command-line argument. The handler requests a CSRF crumb when Jenkins
provides one and reports the queued build URL when available. A reachable job
API does not by itself establish that the configured account has build access.

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
