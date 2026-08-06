output_error_message ()
{
    printf '%s\n' "$(tput setaf 1)Error: $1$(tput sgr0)"
}
