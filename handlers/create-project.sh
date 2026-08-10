#!/usr/bin/env bash
set -uo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for helper in output-heading check-exit-code output-general-message output-error-message create-worktree install-dependencies; do
  # shellcheck source=/dev/null
  source "$plugin_root/helpers/$helper.sh"
done

# Check BFF connectivity
if ! curl -s -o /dev/null --max-time 5 "http://localhost:8082/status"; then
    echo "$(tput setaf 1)Warning: Unable to connect to $(tput sgr0)$(tput bold)BFF$(tput sgr0)$(tput setaf 1). Check it is running.$(tput sgr0)"
	echo
fi

# Check VPN connectivity
ssh_output=$(ssh -T -o ConnectTimeout=5 -o StrictHostKeyChecking=no git@sourcefront.syncsort.com 2>&1)
ssh_exit_code=$?
if [ $ssh_exit_code -ne 0 ] && [ $ssh_exit_code -ne 1 ] && ! echo "$ssh_output" | grep -q "shell request failed"; then
    echo "$(tput setaf 1)Warning: Unable to connect to $(tput sgr0)$(tput bold)Bitbucket$(tput sgr0)$(tput setaf 1). Check you are connected to the VPN.$(tput sgr0)"
	echo
fi

output_heading "Create Project"

create_worktree_for_id ()
{
    id=$1
    branch=$2
    should_install=$3

    ## Obtain details regarding the repo

    repo_path=$(yq ".repos[] | select(.id == \"$id\") | .path // \"\"" ~/.workflow-config.yaml)
    origin_branch=$(yq ".repos[] | select(.id == \"$id\") | .defaultBranch // \"main\"" ~/.workflow-config.yaml)

    if [ -z "$repo_path" ]
    then
        output_error_message "No path found for $id in 'workflow-config.yaml'"
        read -r -n 1 -s -p "Press any key to exit..."
        exit 1
    fi

    create_worktree "$repo_path" "$origin_branch" "$branch"

    if [ "$should_install" = true ]; then
        output_general_message "Installing dependencies for $id"
        install_dependencies "$id"
    fi
}

# Setup possible options
UI_WORKTREE_OPTION="Create UI Worktree"
BACKEND_WORKTREE_OPTION="Create Backend Worktree"
OBSIDIAN_PROJECT_OPTION="Create Obsidian Project"
INSTALL_DEPENDENCIES_OPTION="Install Dependencies"
COPY_BRANCH_NAME_OPTION="Copy branch name to clipboard"
ALL_OPTIONS=("$UI_WORKTREE_OPTION" "$BACKEND_WORKTREE_OPTION" "$OBSIDIAN_PROJECT_OPTION" "$INSTALL_DEPENDENCIES_OPTION" "$COPY_BRANCH_NAME_OPTION")
DEFAULT_OPTIONS=("$OBSIDIAN_PROJECT_OPTION" "$INSTALL_DEPENDENCIES_OPTION" "$COPY_BRANCH_NAME_OPTION")

# Set default values
name=""
branch_name="IS-"

# Prompt user for values.
printf 'Project Name [%s]: ' "$name"
read -r input
check_exit_code $?
name="${input:-$name}"

printf 'Branch Name [%s]: ' "$branch_name"
read -r input
check_exit_code $?
branch_name="${input:-$branch_name}"

# Prompt user for options
printf 'Use default options (Obsidian, Install Dependencies, Copy branch name)? [Y/n]: '
read -r use_defaults
check_exit_code $?
case "${use_defaults:-y}" in
    [yY]*)
        selections="$(printf '%s\n' "${DEFAULT_OPTIONS[@]}")"
        ;;
    *)
        selections="$(printf '%s\n' "${ALL_OPTIONS[@]}" |
            fzf --multi --header 'Select options (Tab to toggle, Enter to confirm)')"
        check_exit_code $?
        ;;
esac

ui=false
backend=false
obsidian=false
install_dependencies=false
copy_branch=false

if grep -qF "$UI_WORKTREE_OPTION" <<<"$selections"; then
    ui=true
fi
if grep -qF "$BACKEND_WORKTREE_OPTION" <<<"$selections"; then
    backend=true
fi
if grep -qF "$OBSIDIAN_PROJECT_OPTION" <<<"$selections"; then
    obsidian=true
fi
if grep -qF "$INSTALL_DEPENDENCIES_OPTION" <<<"$selections"; then
    install_dependencies=true
fi
if grep -qF "$COPY_BRANCH_NAME_OPTION" <<<"$selections"; then
    copy_branch=true
fi

if [[ -z "$name" && "$obsidian" = true ]]; then
    output_error_message "Project Name is required when Obsidian project is being created."
    read -r -n 1 -s -p "Press any key to exit..."
    exit 1
fi

if [ -z "$branch_name" ]; then
    output_error_message "Branch is required."
    exit 1
fi

# Create worktree for UI
if [ "$ui" = true ]; then
    create_worktree_for_id "ironstream-hub-ui" "$branch_name" "$install_dependencies"
fi

# Create worktree for the Backend
if [ "$backend" = true ]; then
    create_worktree_for_id "ironstream-hub-backend" "$branch_name" "$install_dependencies"
fi

if [ "$obsidian" = true ]; then
    # Extract JIRA ID from branch name
    jira_id=""
    if [[ $branch_name =~ ^([A-Z]+-[0-9]+) ]]; then
        jira_id=${BASH_REMATCH[1]}
    fi
    output_heading "Creating Obsidian project for '$name'"

    payload=$(jq -n \
        --arg name "$name" \
        --arg jiraId "$jira_id" \
        --arg branch "$branch_name" \
        '{
            name: $name,
            jiraId: $jiraId,
            context: "Work",
            ongoing: false,
            projectStatus: "02 - In Progress",
            parents: [
                {
                    projectFile: "Projects/Work/Ironstream Hub Backend",
                    branch: $branch
                }
            ]
        }')

    curl -s "http://localhost:8082/projects/" \
        -H "Content-Type: application/json" \
        --data "$payload" | jq

fi

# Copy branch name to clipboard as it might be handy
if [ "$copy_branch" = true ]; then
    output_heading "Copying branch name to clipboard"
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$branch_name" | pbcopy
        output_general_message "Branch name copied to clipboard: $branch_name"
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$branch_name" | xclip -selection clipboard
        output_general_message "Branch name copied to clipboard: $branch_name"
    else
        output_error_message "No clipboard tool found (pbcopy/xclip). Skipping."
    fi
fi

output_heading "Finished!"
output_general_message "Press any key to exit..."
read -r -n 1 -s
