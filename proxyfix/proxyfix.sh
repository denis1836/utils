#!/bin/bash

#########################################################
# NAME:          proxyfix.sh
# DESCRIPTION:   Better proxychains configuration file management
# AUTHOR:        denis1836 <den.pylypen@protonmail.com>
# CONTRIBUTORS:  None
# VERSION:       1.0.1
# CREATED:       2025-05-04
#                   
# SOURCE:        https://github.com/denis1836/utils/
# LICENSE:       MIT License
#########################################################

if [ "$(id -u)" -eq 0 ]; then
    echo "You are not root (current user: $(id -un))"
    exit 1
fi

CONFIG="$HOME/.config/proxyfix/proxyfix.conf"
if [ ! -f "$CONFIG" ]; then
    echo "error: the proxyfix config file (${CONFIG}) is missing"
fi

if [[ ! -s $CONFIG ]]; then
    echo -e "error: config file is empty"
fi    

# shellcheck disable=SC1090
source "${CONFIG}"

if [[ ! -f "${PROXYCHAINS_CONF_FILE}" ]]; then
    echo "error: proxychains config file (${PROXYCHAINS_CONF_FILE}) is missing"
fi

PROXCONF="${PROXYCHAINS_CONF_FILE}"

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
    if [[ -z "$PROFILE_NAME" ]]
    then
        echo "You must provide a profile name. Usage: proxyfix --save-profile <name>"
        exit 1
    fi
}
profile_not_found_404()
{
    if [[ ! -f "$PROFILE_PATH" ]]
    then
        echo "Profile '$PROFILE_NAME' not found(404) in $DEFAULT_PROFILE_DIR"
        exit 255
    fi
}

if [[ -z "$PROXCONF" ]]
then
    DEFAULT_CONF="/etc/proxychains.conf"
    if [[ -f "$DEFAULT_CONF" ]]
    then
        PROXCONF="$DEFAULT_CONF"
    else
        echo "Error: Could not find proxychains config file."
        if [[ $(which proxychains) != /usr/bin/proxychains ]]
        then
            echo "Error: proxychains is not installed"
            echo "Do you want to install it?[y/n]"
            while true
            do
                read -r confirm0
                case "$confirm0" in
                    y)
                        sudo apt install proxychains
                        echo ""
                        echo "You've installed proxychains. Run 'proxyfix -h' for help" 
                        exit 0
                    ;;

                    n)
                        echo "Abort."
                        break
                    ;;

                    *)
                        echo -n "Incorrect answer, please answer again with 'y' or 'n': "
                    ;;
                esac
            done
        fi
        exit 1
    fi
fi

case $1 in
    -E|--edit)  
        echo "Opening proxychains config file: $PROXCONF"
        sudo nano "$PROXCONF"
    ;;

    -l|--list)
        echo "Listing proxies..."
        echo ""
        echo "Type     | IP           | Port"
        echo "---------|--------------|------"
        grep -E '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" | awk '{ printf "%-8s | %-12s | %s\n", $1, $2, $3 }'
    ;;

    -ela|--edit-list-add)
        ADD_MODE=true
        shift
        set -- -el "$@"
        ;&
    -elcl|--edit-list-clear)
        CLEAR_MODE=true
        shift
        set -- -el "$@"
        ;&
    -el|--edit-list)
        shift

        ADD_MODE=${ADD_MODE:-false}
        CLEAR_MODE=${CLEAR_MODE:-false}
        PROXY_LINES=()

        while [[ "$1" =~ ^- ]]
        do
            case "$1" in
                -a|--add)
                    ADD_MODE=true
                    shift
                ;;

                -1|-2|-3|-4|-5)
                    shift
                    if [[ -n "$1" ]]
                    then
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

        if [[ ${#PROXY_LINES[@]} -eq 0 ]]
        then
            echo -n "No proxies provided. Do you want to manually edit the file? [y/n]: "
            while true
            do
                read -r confirm1
                case "$confirm1" in
                    y)
                        sudo nano "$PROXCONF"
                        break
                    ;;

                    n)
                        echo "Abort."
                        break
                    ;;

                    *)
                        echo -n "Incorrect answer, please answer again with 'y' or 'n': "
                    ;;
                esac
            done
        else
            echo "Updating proxy list..."

            TMP_CONF=$(mktemp)
            grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF"

            cat "$TMP_CONF" > "$PROXCONF"

            if [[ "$CLEAR_MODE" == true ]]
            then
                echo "# Cleared proxy list" >> "$PROXCONF"
            fi

            for line in "${PROXY_LINES[@]}"
            do
                echo "$line" >> "$PROXCONF"
            done

            echo "Proxy list updated in $PROXCONF"
            rm "$TMP_CONF"
        fi
    ;;

    -cl|--clear)
        echo "Are you sure that you want to clear the proxy list? [y/n]"
        while true
        do
            read -r confirm2
            case "$confirm2" in
                y)
                    echo "Clearing proxy list in $PROXCONF..."
                    TMP_CONF=$(mktemp)
                    grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF"
                    cat "$TMP_CONF" > "$PROXCONF"
                    rm "$TMP_CONF"
                    echo "Proxy list cleared."
                    break
                ;;

                n)
                    echo "Abort."
                    break
                ;;

                *)
                    echo -n "Incorrect answer, please answer again with 'y' or 'n': "
                ;;
            esac
        done
    ;;

    -sp|--save-profile)
        PROFILE_NAME="$2"

        ensure_profile_name_was_given

        ensure_profile_folder_exists

        PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

        grep -E '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$PROFILE_PATH"

        echo "Saved profile '$PROFILE_NAME' to: $PROFILE_PATH"
    ;;

    -cp|--change-profile)
        PROFILE_NAME="$2"

        ensure_profile_name_was_given

        ensure_profile_folder_exists

        PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

        profile_not_found_404

        echo -n "Are you sure you want to replace contents of $PROXCONF with profile '$PROFILE_NAME'? [y/n]: "
        while true
        do
            read -r confirm_cp
            case "$confirm_cp" in
                y)
                    echo "Replacing contents of $PROXCONF with profile '$PROFILE_NAME'..."
                    TMP_CONF=$(mktemp)
                    grep -vE '^\s*(socks4|socks5|http|https)\s+' "$PROXCONF" > "$TMP_CONF"
                    cat "$TMP_CONF" > "$PROXCONF"
                    cat "$PROFILE_PATH" >> "$PROXCONF"
                    rm "$TMP_CONF"
                    echo "Profile '$PROFILE_NAME' applied to $PROXCONF"
                    break
                ;;

                n)
                    echo "Abort."
                    break
                ;;

                *)
                    echo -n "Incorrect answer, please answer again with 'y' or 'n': "
                ;;
            esac
        done
    ;;

    -ep|--edit-profile)
        PROFILE_NAME="$2"

        ensure_profile_name_was_given

        ensure_profile_folder_exists

        PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

        profile_not_found_404

        echo "Opening profile '$PROFILE_NAME' for editing..."
        ${DEFAULT_PROFILE_VIEWER:-nano} "$PROFILE_PATH"
    ;;

    -dp|--delete-profile)
        PROFILE_NAME="$2"

        ensure_profile_name_was_given

        ensure_profile_folder_exists

        PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"

        profile_not_found_404

        echo -n "Are you sure you want to delete profile '$PROFILE_NAME'? [y/n]: "
        while true
        do
            read -r confirm_del
            case "$confirm_del" in
                y)
                    rm "$PROFILE_PATH"
                    echo "Profile '$PROFILE_NAME' deleted."
                    break
                ;;

                n)
                    echo "Abort."
                    break
                ;;

                *)
                    echo -n "Incorrect answer, please answer again with 'y' or 'n': "
                ;;
            esac
        done
    ;;

    -lp|--list-profiles)
        ensure_profile_folder_exists

        echo "Available profiles in $DEFAULT_PROFILE_DIR:"
        if ls "$DEFAULT_PROFILE_DIR"/*.conf &>/dev/null
        then
            for file in "$DEFAULT_PROFILE_DIR"/*.conf
            do
                basename "$file" .conf
            done
        else
            echo "(No profiles found)"
        fi
    ;;

    -vp|--view-profile)
        PROFILE_NAME="$2"

        ensure_profile_name_was_given
        ensure_profile_folder_exists

        PROFILE_PATH="${DEFAULT_PROFILE_DIR}/${PROFILE_NAME}.conf"
        profile_not_found_404

        if [[ "$DEFAULT_PROFILE_VIEWER" != "cat" && "$DEFAULT_PROFILE_VIEWER" != "less" && "$DEFAULT_PROFILE_VIEWER" != "more" ]]
        then
            echo "Unknown default viewer '$DEFAULT_PROFILE_VIEWER'. Falling back to 'cat'."
            DEFAULT_PROFILE_VIEWER="cat"
        fi

        $DEFAULT_PROFILE_VIEWER "$PROFILE_PATH"
    ;;

    -h|-?|--help)
        echo ""
        echo "> $(basename "$0") arguments:"
        echo "> -E OR --edit                # Edit entire proxychains config file"
        echo "> -l OR --list                # List active proxies"
        echo "> -el OR --edit-list          # Replace proxy list"
        echo "> -ela OR --edit-list-add     # Add to current proxy list"
        echo "> -elcl OR --edit-list-clear  # Clear proxy list before editing"
        echo "> -cl OR --clear              # Just clear proxy list"
        echo "> -h OR any help flag         # Show this help message"
        echo "> -hp OR any help falg + p    # Show help message about profiles"
        echo "> -hD OR any help flag + D    # Show help message about defaults"
    ;;

    -hp|--help-profiles|-?p)
        echo ""
        echo "Profile management options:"
        echo "  -sp,  --save-profile <name>                     #Save current proxy list as a named profile"
        echo "  -cp,  --change-profile <name>                   #Replace proxychains.conf with selected profile"
        echo "  -ep,  --edit-profile <name>                     #Edit selected profile using the default editor"
        echo "  -dp,  --delete-profile <name>                   #Delete selected profile (with confirmation)"
        echo "  -lp,  --list-profiles                           #Show list of all saved profiles"
        echo "  -vp,  --view-profile <name>                     #View profile content using default or chosen viewer"
        echo ""
        echo "Note:"
        echo "  If no default profile folder is set, one will be created at ~/ProxyFixProfiles"
    ;;

    *)
        echo "Invalid argument. Use -h for help."
    ;;
esac
