check_exit_code()
{
    if [ $1 -ne 0 ]; then
        echo "$(tput setaf 1)Exit code: $1$(tput sgr0)"
        echo "$(tput setaf 1)Script exited prematurely...$(tput sgr0)"
        read -r -n 1 -s -p "Press any key to exit..."
        exit 1
    fi
}
