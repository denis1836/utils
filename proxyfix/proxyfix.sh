#!/bin/bash

#########################################################
# NAME:          proxyfix.sh
# DESCRIPTION:   Better proxychains configuration and management
# AUTHOR:        Denis Pylypenko (denis1836) <den.pylypen@protonmail.com>
# CONTRIBUTORS:  None
# VERSION:       2.0.11
# CREATED:       2025-05-04
# LAST UPDATE:   2026-08-25
#                   
# SOURCE:        https://github.com/denis1836/utils/
# LICENSE:       MIT License
#########################################################

set -euo pipefail

TMP_CONF=""
cleanup() {
    if [[ -n "${TMP_CONF:-}" && -f "${TMP_CONF}" ]]; then
        rm -f "${TMP_CONF}"
    fi
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
    echo "You are not root (current user: $(id -un))"
    exit 1
fi

if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

CONFIG="${USER_HOME}/.config/proxyfix/proxyfix.conf"
if [[ ! -f "$CONFIG" ]]; then
    echo "error: the proxyfix config file (${CONFIG}) is missing"
    exit 1
fi

if [[ ! -s "$CONFIG" ]]; then
    echo -e "error: config file is empty"
    exit 1
fi

CONFIG_PERMS=$(stat -c '%a' "$CONFIG")
if (( (8#$CONFIG_PERMS) & 8#022 )); then
    echo "error: $CONFIG is writable by group or others"
    exit 1
fi

CONFIG_OWNER_UID=$(stat -c '%u' "$CONFIG")
EXPECTED_UID="${SUDO_UID:-0}"
if [[ "$CONFIG_OWNER_UID" -ne 0 && "$CONFIG_OWNER_UID" -ne "$EXPECTED_UID" ]]; then
    echo "error: $CONFIG is not owned by root or by the invoking user"
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG}"

if [[ ! -f "${PROXYCHAINS_CONF_FILE}" ]]; then
    echo "error: proxychains config file (${PROXYCHAINS_CONF_FILE}) is missing"
    exit 1
fi

PROXCONF="${PROXYCHAINS_CONF_FILE}"

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

ensure_profile_folder_exists()
{
    if [[ ! -d "$DEFAULT_PROFILE_DIR" ]]
    then
        mkdir -p "$DEFAULT_PROFILE_DIR"
        echo "No default profiles folder set. Created: $DEFAULT_PROFILE_DIR"
        echo "To change it, use: proxyfix --set-default-profiles-folder <path>"
    fi
}
ensure_profile_name_was_given()
{
    if [[ -z "${1:-}" ]]
    then
        echo "You must provide a profile name. Usage: proxyfix profile <action> <name>"
        exit 1
    fi
}
profile_not_found_404()
{
    if [[ ! -f "${1:-}" ]]
    then
        echo "Profile not found (404): $1"
        exit 255
    fi
}

cmd_profile()
{
    case "$1" in
        save)
            shift
            PROFILE_NAME="$1"

            ensure_profile_name_was_given "$PROFILE_NAME"

            ensure_profile_folder_exists

            PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

            grep -E '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$PROFILE_PATH"

            echo "Saved profile '$PROFILE_NAME' to: $PROFILE_PATH"
        ;;

        apply)
            shift
            PROFILE_NAME="$1"

            ensure_profile_name_was_given "$PROFILE_NAME"

            ensure_profile_folder_exists

            PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

            profile_not_found_404 "$PROFILE_PATH"

            if confirm "Are you sure you want to replace contents of $PROXCONF with profile '$PROFILE_NAME'? [y/n]: "; then
                echo "Replacing contents of $PROXCONF with profile '$PROFILE_NAME'..."
                TMP_CONF=$(mktemp)
                grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF"
                cat "$TMP_CONF" > "$PROXCONF"
                cat "$PROFILE_PATH" >> "$PROXCONF"
                rm "$TMP_CONF"
                echo "Profile '$PROFILE_NAME' applied to $PROXCONF"
            fi
        ;;

        edit)
            shift
            PROFILE_NAME="$1"

            ensure_profile_name_was_given "$PROFILE_NAME"

            ensure_profile_folder_exists

            PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

            profile_not_found_404 "$PROFILE_PATH"

            echo "Opening profile '$PROFILE_NAME' for editing..."
            ${DEFAULT_PROFILE_EDITOR:-nano} "$PROFILE_PATH"
        ;;

        remove)
            shift
            PROFILE_NAME="$1"

            ensure_profile_name_was_given "$PROFILE_NAME"

            ensure_profile_folder_exists

            PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

            profile_not_found_404 "$PROFILE_PATH"

            if confirm "Are you sure you want to remove profile '$PROFILE_NAME'? [y/n]: "; then
                rm "$PROFILE_PATH"
                echo "Profile '$PROFILE_NAME' was removed."
            fi
        ;;

        list)
            ensure_profile_folder_exists

            echo "Available profiles in $DEFAULT_PROFILE_DIR:"
            shopt -s nullglob
            profiles=("$DEFAULT_PROFILE_DIR"/*.conf)
            shopt -u nullglob

            if [[ ${#profiles[@]} -gt 0 ]]; then
                for file in "${profiles[@]}"; do
                    basename "$file" .conf
                done
            else
                echo "(No profiles found)"
            fi
        ;;

        view)
            shift
            PROFILE_NAME="$1"

            ensure_profile_name_was_given "$PROFILE_NAME"
            ensure_profile_folder_exists

            PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"
            profile_not_found_404 "$PROFILE_PATH"

            ${DEFAULT_PROFILE_VIEWER:-less} "$PROFILE_PATH"
        ;;
    esac
}

if ! command -v "proxychains" > /dev/null 2>&1; then
    echo -e "Error: proxychains is not installed"
    echo -e "Please install it to proceed"
    exit 1
fi

case "${1:-}" in
    edit)  
        echo "Opening proxychains config file: $PROXCONF"
        sudo "${DEFAULT_PROFILE_EDITOR:-nano}" "$PROXCONF"
    ;;

    list)
        echo "Listing proxies..."
        echo ""
        echo "Type     | IP           | Port"
        echo "---------|--------------|------"
        grep -E '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" | awk '{ printf "%-8s | %-12s | %s\n", $1, $2, $3 }' || true
    ;;

    edit-list|edit-list-add|edit-list-clear)
        CMD_NAME="$1"
        shift

        ADD_MODE=false
        CLEAR_MODE=false
        case "${CMD_NAME}" in 
            edit-list-add) ADD_MODE=true ;;
            edit-list-clear) CLEAR_MODE=true ;;
        esac

        PROXY_LINES=()

        while [[ $# -gt 0 && "$1" =~ ^- ]]
        do
            case "$1" in
                -a|--add)
                    ADD_MODE=true
                    shift
                ;;

                --line)
                    shift
                    if [[ $# -gt 0 ]]; then
                        PROXY_LINES+=("$1")
                        shift
                    fi
                ;;

                *)
                    echo "Unknown option: $1"
                    exit 1
                ;;
            esac
        done

        if [[ ${#PROXY_LINES[@]} -eq 0 ]]; then
            if confirm "No proxies provided. Do you want to manually edit the file? [y/n]:"; then
                sudo "${DEFAULT_PROFILE_EDITOR:-nano}" "${PROXCONF}"
            fi
        else
            echo "Updating proxy list..."
            TMP_CONF=$(mktemp)

            if [[ "$ADD_MODE" == true ]]; then
                cat "$PROXCONF" > "$TMP_CONF"
            else
                grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF" || true
                if [[ "$CLEAR_MODE" == true ]]; then
                    echo "# Cleared proxy list" >> "$PROXCONF"
                fi
            fi

            for line in "${PROXY_LINES[@]}"; do
                echo "$line" >> "$TMP_CONF"
            done

            mv "$TMP_CONF" "$PROXCONF" 
            echo "Proxy list updated in $PROXCONF"
        fi
    ;;

    clear)
        if confirm "Are you sure that you want to clear the proxy list? [y/n]"; then
            echo "Clearing proxy list in $PROXCONF..."
            TMP_CONF=$(mktemp)
            grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF" || true
            cat "$TMP_CONF" > "$PROXCONF"
            rm "$TMP_CONF"
            echo "Proxy list cleared."
        fi
    ;;

    profile|p)
        shift
        cmd_profile "$@"
    ;;

    help|--help|-h)
        echo ""
        echo " $(basename "$0") arguments:"
        echo "edit              Edit entire proxychains config file"
        echo "list              List active proxies"
        echo "edit-list         Replace proxy list"
        echo "edit-list-add     Add to current proxy list"
        echo "edit-list-clear   Clear proxy list before editing"
        echo "clear             Clear current proxy list"
        echo "profile [arg]     Manage profiles (see help-profiles)"
        echo "help              Show this help message"
        echo "help-profiles     Show help message about profiles"
    ;;

    help-profiles|--help-profiles|-hp)
        echo ""
        echo "Profile management options:"
        echo "save [name]      Save current proxy list as a named profile"
        echo "apply [name]     Replace proxy list with selected profile"
        echo "edit [name]      Edit the selected profile"
        echo "remove [name]    Remove the selected profile"
        echo "list             Show list of all avalible profiles"
        echo "view [name]      View profile content"
        echo ""
    ;;

    *)
        echo "Invalid argument"
        echo "Run with --help flag"
        exit 1
    ;;
esac
