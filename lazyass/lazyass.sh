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

CONFIG="${USER_HOME}/.config/lazyass/lazyass.conf"
if [[ ! -f "$CONFIG" ]]; then
    echo "Could not locate the config file at ${CONFIG}"
    echo "Creating config file..."
    touch "${CONFIG}"
fi

appsAR=($(grep '^Apps:' "$CONFIG" | sed 's/^Apps: *//'))
AmountOfApps=$(grep "Apps-Amount:" "$CONFIG" | awk -F': ' '{print $2}')

for app in "${appsAR[@]}"
do
    pathToApp=$(which "$app" 2>/dev/null)
    if [[ -z $pathToApp ]]
    then
        echo "$app is missing. Please check if the app is installed."
    fi
    unset pathToApp
done


launchProfileApps() {
    profile_name="$1"
    if ! grep -q "^\[profile:$profile_name\]" "$CONFIG"
    then
        echo "Profile '$profile_name' not found in config."
        exit 1
    fi

    appsLine=$(awk "/\\[profile:$profile_name\\]/ {found=1} found && /^Apps:/ {print; exit}" "$CONFIG")
    apps=$(echo "$appsLine" | sed 's/^Apps:[[:space:]]*//')

    if [[ -z $apps ]]
    then
        echo "No applications defined for profile '$profile_name'."
        exit 1
    fi

    for app in $apps
    do
        if command -v "$app" >/dev/null 2>&1
        then
            "$app" &
        else
            echo "$app not found on system."
        fi
    done
}

case "$1" in
    app)
        shift 
        case "$1" in
            add)
                shift
                if [[ -n $1 ]]
                then
                    appName="$1"
                    sed -i "/^Apps:/ s|$| $appName|" "$CONFIG"
                    newCount=$((AmountOfApps + 1))
                    sed -i "s/^Apps-Amount:.*/Apps-Amount: $newCount/" "$CONFIG"
                    echo "App '$appName' added to config."
                else
                    echo "No app name provided."
                fi
            ;;

            remove)
                shift
                if [[ -n $1 ]]
                then
                    appName="$1"
                    if grep -qE "^Apps:.*\b$appName\b" "$CONFIG"
                    then
                        echo "Do you really want to delete '$appName' from the app list? [y/n]"
                        read -r conf
                        while true
                        do
                            case "$conf" in
                                y)
                                    sed -i "s/\b$appName\b//g" "$CONFIG"
                                    sed -i 's/  */ /g' "$CONFIG"
                                    sed -i 's/Apps: /Apps:/g' "$CONFIG"
                                    newCount=$((AmountOfApps - 1))
                                    sed -i "s/^Apps-Amount:.*/Apps-Amount: $newCount/" "$CONFIG"
                                    echo "App '$appName' was deleted from the list."
                                    break
                                ;;
                                n)
                                    echo "Abort."
                                    break
                                ;;
                                *)
                                    echo "Invalid argument provided. Please answer with 'y' or 'n': "
                                    read -r conf
                                ;;
                            esac
                        done
                    else
                        echo "App '$appName' is not in the config list."
                    fi
                else
                    echo "No app name was provided."
                fi
            ;;

            list)
                echo "Total apps: $AmountOfApps"
                echo "Listing..."
                grep "^Apps:" "$CONFIG" | sed 's/^Apps: *//'
            ;;

            edit)
                echo "Opening config file '$CONFIG' for editing..."
                if [[ -z "$EDITOR" ]]; then
                    nano "$CONFIG"
                else
                    "$EDITOR" "$CONFIG"
                fi
            ;;
        esac
    ;;

    profile)
        shift
        case "$1" in
            create)
                shift
                if [[ -n "$1" ]]
                then
                    profile_name="$1"
                    if grep -q "^\[profile:$profile_name\]" "$CONFIG"
                    then
                        echo "Profile '$profile_name' already exists."
                    else
                        echo "Creating profile '$profile_name'..."

                        
                        cat >> "$CONFIG" <<EOF

[profile:$profile_name]
Apps:
Apps-Amount: 0
EOF

                        echo "Profile '$profile_name' created."

                    
                        if [[ -n "$2" ]]
                        then
                            shift
                            app="$1"
                            sed -i "/^\[profile:$profile_name\]/,/\[profile:/s/Apps:/Apps: $app /" "$CONFIG"
                            echo "App '$app' added to profile '$profile_name'."
                        fi
                    fi
                else
                    echo "Please specify a profile name."
                fi
            ;;

            delete)
                shift
                if [[ -n "$1" ]]
                then
                    profile_name="$1"
                    if grep -q "^\[profile:$profile_name\]" "$CONFIG"
                    then
                        while true
                        do
                            echo "Are you sure you want to delete the profile '$profile_name'? (y/n)"
                            read -r confirm
                            case "$confirm" in
                                y|Y)
                                    echo "Deleting profile '$profile_name'..."
                                    sed -i "/^\[profile:$profile_name\]/,/^\[profile:/ { /^\[profile:/!d }" "$CONFIG"
                                    echo "Profile '$profile_name' deleted."
                                    break
                                ;;
                                n|N)
                                    echo "Aborted. Profile '$profile_name' not deleted."
                                    break
                                ;;
                                *)
                                    echo "Invalid input. Please answer with 'y' or 'n'."
                                ;;
                            esac
                        done
                    else
                        echo "Profile '$profile_name' not found."
                    fi
                else
                    echo "Please specify a profile name."
                fi
            ;;

            list)
                echo "Listing all profiles..."
                profiles=$(grep -oP "^\[profile:\K[^\]]+" "$CONFIG")
                if [[ -n "$profiles" ]]
                then
                    echo "Profiles found:"
                    echo "$profiles"
                else
                    echo "No profiles found."
                fi
            ;;
        esac
    ;;

    -Atp|--add-app-to-profile)
        shift
        if [[ -n "$1" && -n "$2" ]]
        then
            profile_name="$1"
            app_name="$2"

            if grep -q "^\[profile:$profile_name\]" "$CONFIG"
            then
                echo "Adding app '$app_name' to profile '$profile_name'..."
                sed -i "/^\[profile:$profile_name\]/,/^\[profile:/s/Apps: .*/Apps: & $app_name/" "$CONFIG"

                sed -i "/^\[profile:$profile_name\]/,/^\[profile:/s/Apps-Amount: [0-9]\+/Apps-Amount: $(( $(grep "Apps-Amount:" "$CONFIG" | awk '{print $2}') + 1 ))/" "$CONFIG"

                echo "App '$app_name' added to profile '$profile_name'."
            else
                echo "Profile '$profile_name' not found."
            fi
        else
            echo "Please specify both a profile name and an app name."
        fi
    ;;

    -laP|--list-apps-profile)
        shift
        if [[ -n "$1" ]]
        then
            profile_name="$1"

            if grep -q "^\[profile:$profile_name\]" "$CONFIG"
            then
                echo "Listing apps for profile '$profile_name'..."

                apps=$(sed -n "/^\[profile:$profile_name\]/,/^\[profile:/p" "$CONFIG" | grep -A 100 "Apps:" | tail -n +2)
                if [[ -n "$apps" ]]
                then
                    echo "Apps in profile '$profile_name':"
                    echo "$apps"
                else
                    echo "No apps assigned to profile '$profile_name'."
                fi
            else
                echo "Profile '$profile_name' not found."
            fi
        else
            echo "Please specify a profile name."
        fi
    ;;

    #misc and help
    -h|-?|--help)
        echo "lazyass - launches the provided apps because you are lazy and don't want to open them all one by one"
        echo "-ap/--add-app                    - adds app to the default list"
        echo "-rma/--remove-app                - removes an app from the default list"
        echo "-la/--list-apps                  - lists apps in the default list"
        echo "-E/--edit                        - opens the config file for manual editing"
        echo "-cP/--create-profile <name>      - creates a new profile"
        echo "-dP/--delete-profile <name>      - deletes the specified profile"
        echo "-Atp/--add-app-to-profile <p> <a>- adds app to profile"
        echo "-lP/--list-profiles              - lists all profiles"
        echo "-laP/--list-apps-profile <name>  - lists apps from a specific profile"
        echo "<profile>                        - launches all apps from the given profile"
    ;;

    -*)
        echo "Invalid argument provided."
        exit 1
    ;;

    *)
        launchProfileApps "$1"
    ;;
esac