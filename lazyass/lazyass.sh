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

[[ ! -d "$CONFIG_DIR" ]] && mkdir -p "${PROFILES_DIR}"
[[ ! -d "$PROFILES_DIR" ]] && mkdir -p "${PROFILES_DIR}"
[[ ! -f "$DEFAULT" ]] && touch "${DEFAULT}"

APPS=()

confirm() {
    local prompt="${1:-Are you sure? [y/n]: }"
    
    while true; do
        if ! IFS= read -r -p "${prompt}" ans; then
            echo "Abort."
            return 1
        fi
        case "${ans}" in
            [Yy]*|"") 
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

read_apps_from_file() {
    local target_file="$1"

    if [[ -z "$target_file" || ! -f "$target_file" ]]; then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]] && APPS+=("$line")
    done < "$target_file"

}

run_loaded_apps() {
    if [[ ${#APPS[@]} -eq 0 ]]; then
        echo "Nothing to launch."
        return 1
    fi

    for app in "${APPS[@]}"; do
        if command -v "$app" >/dev/null 2>&1; then
            echo "Launching $app..."
            "$app" &
        else
            echo "Error: '$app' not found on system."
        fi
    done
}

launch_profile() {
    local profile_name="$1"
    local profile_path="${PROFILES_DIR}/${profile_name}"

    if [[ ! -f "$profile_path" ]]; then
        echo "Error: Profile '$profile_name' does not exist."
        exit 1
    fi

    read_apps_from_file "$profile_path"
    run_loaded_apps
}

case "$1" in
    app)
        shift 
        case "$1" in
            add)
                shift
                if [[ -n "$1" ]]; then
                    echo "$1" >> "$DEFAULT"
                    echo "'$1' added to default profile."
                else
                    echo "No app name provided."
                fi
            ;;

            remove)
                shift
                if [[ -n "$1" ]]; then
                    app_name="$1"
                    if confirm "Delete '$app_name' from default profile?"; then
                        sed -i "/^\b$app_name\b$/d" "$DEFAULT"
                        echo "'$app_name' removed."
                    fi
                else
                    echo "No app name provided."
                fi
            ;;

            list)
                echo "Default profile apps:"
                read_apps_from_file "$DEFAULT"
                printf ' - %s\n' "${APPS[@]}"
            ;;

            edit)
                ${EDITOR:-nano} "$DEFAULT"
            ;;
        esac
    ;;

    profile)
        shift
        case "$1" in
            create)
                shift
                if [[ -n "$1" ]]; then
                    prof_name="$1"
                    prof_file="${PROFILES_DIR}/${prof_name}"
                    shift
                    if [[ -f "$prof_file" ]]; then
                        echo "Profile '$prof_name' already exists."
                    else
                        touch "$prof_file"
                        for app in "$@"; do
                            echo "$app" >> "$prof_file"
                        done
                        echo "Profile '$prof_name' created."
                    fi
                else
                    echo "Specify profile name."
                fi
            ;;

            delete)
                shift
                if [[ -n "$1" ]]; then
                    prof_name="$1"
                    prof_file="${PROFILES_DIR}/${prof_name}"
                    if [[ -f "$prof_file" ]]; then
                        if confirm "Delete profile '$prof_name'?"; then
                            rm "$prof_file"
                            echo "Profile '$prof_name' deleted."
                        fi
                    else
                        echo "Profile '$prof_name' not found."
                    fi
                else
                    echo "Specify profile name."
                fi
            ;;

            list)
                echo "Available profiles:"
                for p in "${PROFILES_DIR}"/*; do
                    [[ -f "$p" ]] && echo " - $(basename "$p")"
                done
            ;;

            edit)
                shift
                if [[ -n "$1" ]]; then
                    prof_name="$1"
                    prof_file="${PROFILES_DIR}/${prof_name}"
                    
                    ${EDITOR:-nano} "$prof_file"
                else
                    echo "Specify profile name."
                fi
            ;;
        esac
    ;;

    #TODO
    -h|-?|--help)
        echo "lazyass - quick app launcher"
        echo "Usage:"

    ;;
    
    "")
        read_apps_from_file "$DEFAULT"
        run_loaded_apps
    ;;

    *)
        launch_profile "$1"
    ;;
esac