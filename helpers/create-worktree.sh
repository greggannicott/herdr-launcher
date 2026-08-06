create_worktree ()
{
    repo_path=$1
    origin_branch=$2
    new_branch=$3

    output_heading "Creating Worktree"
    output_general_message "Repo: $repo_path"
    output_general_message "Origin Branch: $origin_branch"
    output_general_message "New Branch: $new_branch"

    cd "$repo_path" || exit 1
    git worktree add "$new_branch"
    cd "$new_branch" || exit 1
    git fetch
    git merge "$origin_branch"

    output_general_message "Pushing branch to origin"
    git push -u
}
