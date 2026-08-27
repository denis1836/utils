#!/bin/bash

#########################################################
# NAME:          lazyass.sh
# DESCRIPTION:   Easier and quicker multiple app launching
# AUTHOR:        Denis Pylypenko (denis1836) <den.pylypen@protonmail.com>
# CONTRIBUTORS:  None
# VERSION:       2.0.0
# CREATED:       2025-05-10
# LAST UPDATE:   2026-08-26
#                   
# SOURCE:        https://github.com/denis1836/utils/
# LICENSE:       MIT License
#########################################################


if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

CONFIG_DIR="${USER_HOME}/.config/lazyass"
PROFILES_DIR="${CONFIG_DIR}/profiles"
DEFAULT="${CONFIG_DIR}/default"

[[ ! -d "$PROFILES_DIR" ]] && mkdir -p "${PROFILES_DIR}"
[[ ! -f "$DEFAULT_PROFILE" ]] && touch "$DEFAULT_PROFILE"

APPS=()

confirm() {
    local prompt="${1:-Are you sure? [y/n]: }"
    
    while true; do
        if ! read -r -p "${prompt}" ans; then
            echo "Abort."
            return 1
        fi
        case "${ans}" in
            [Yy]* ) 
                return 0 
            ;;
            [Nn]* ) 
                echo "Abort."
                return 1 
            ;;
            * ) 
                echo "Incorrect answer, please answer again with 'y' or 'n'." 
            ;;
        esac
    done
}

case "$1" in
    #TODO
    app)
        shift 
        case "$1" in
            add)
                
            ;;

            remove)
                
            ;;

            list)

            ;;

            edit)
                ${EDITOR:-nano} "$DEFAULT_PROFILE"
            ;;
        esac
    ;;

    #TODO
    profile)
        shift
        case "$1" in
            create)
                shift

            ;;

            delete)

            ;;

            list)
               
            ;;
        esac
    ;;

    #TODO
    -h|-?|--help)
        echo "lazyass - quick app launcher"
        echo "Usage:"

    ;;
    
    *)
        launchProfileApps "$1"
    ;;
esac