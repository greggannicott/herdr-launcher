install_dependencies ()
{
    id=$1
    output_heading "Installing dependencies for $id"
    if [ -e ~/.workflow-config.yaml ]; then
        init_command="$(yq ".repos[] | select(.id == \"$id\") | .init" ~/.workflow-config.yaml)"
        if [[ -z "$init_command" || "$init_command" = "null" ]]; then
            echo "No init command found. Skipping..."
        else
            echo "Running init command: '$init_command'"
            eval "$init_command"

            if [ $? -ne 0 ]; then
                echo "$(tput setaf 1)Error running init command...$(tput sgr0)"
            fi
        fi
    else
        echo "Not attempting to initialise repo. 'workflow-config.yaml' not found..."
    fi
}
