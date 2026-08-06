output_heading ()
{
    echo
    tput bold ; echo "$(tput setaf 3)$1$(tput sgr0)"
    tput bold ; echo "$(tput setaf 3)-------------------------------------------------------------------------------------$(tput sgr0)"
    echo ""
}
