#!/bin/bash

#########################################################################
# Script Name:   download-assets.sh
# Description:   Easier Unreal Engine 5 asset downloading and sharing
# Author:        Denis Pylypenko <den.pylypen@protonmail.com>
# Created:       2026-06-06
# Last modified: 2026-08-31
# Version:       1.0.5
# License:       MIT License
# Repository:    https://github.com/denis1836/utils/tree/main/ue5_asset_downloader
#########################################################################

set -euo pipefail

# colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# get conf
CONFIG_FILE="${SCRIPT_DIR}/download-assets.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo -e "${RED}error:${NC} Configuration file was not found:${NC} $CONFIG_FILE" >&2
    exit 1
fi

# helpers
get_field() {
    python3 -c "
import json, sys
try:
    d = json.load(open('$1'))
    v = d.get('$2', '')
    print(str(v).strip() if not isinstance(v, list) else ', '.join(v))
except:
    print('')
" 2>/dev/null
}

has_command() {
    command -v "$1" > /dev/null 2>&1
}

print_info()  { echo -e "  ${BLUE}info${NC}    $1"; }
print_ok()    { echo -e "  ${GREEN}ok${NC}      $1"; }
print_warn()  { echo -e "  ${YELLOW}warn${NC}    $1"; }
print_error() { echo -e "  ${RED}error${NC}   $1"; }
print_fetch() { echo -e "  ${CYAN}fetch${NC}   $1"; }

# checking for dependepcies
if ! has_command python && ! has_command python3; then
    print_error "python is required but not installed"
    exit 1
fi

if has_command curl; then
    DOWNLOADER="curl"
elif has_command wget; then
    DOWNLOADER="wget"
else
    print_error "curl or wget is required but neither is installed"
    exit 1
fi

# google drive url extraction helper
gdrive_extract_id() {
    local URL="$1"
    local FILE_ID=""

    if echo "$URL" | grep -q '/file/d/'; then
        # https://drive.google.com/file/d/<FILE_ID>/view
        FILE_ID=$(echo "$URL" | grep -oP '(?<=/d/)[^/?]+')
    elif echo "$URL" | grep -q 'id='; then
        # https://drive.google.com/uc?export=download&id=<FILE_ID>
        # https://drive.google.com/open?id=<FILE_ID>
        FILE_ID=$(echo "$URL" | grep -oP '(?<=id=)[^&]+')
    fi

    echo "$FILE_ID"
}

# google drive download helper
gdrive_download() {
    local FILE_ID="$1"
    local OUT="$2"
    local EXIT_CODE=0

    local BASE_URL="https://drive.usercontent.google.com/download"
    local DIRECT_URL="${BASE_URL}?id=${FILE_ID}&export=download&authuser=0&confirm=t"
    local COOKIE_JAR="/tmp/gdrive_cookies_$$.txt"

    if [ "$DOWNLOADER" = "curl" ]; then
        curl -L --progress-bar \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
            -c "$COOKIE_JAR" \
            -b "$COOKIE_JAR" \
            -o "$OUT" \
            "$DIRECT_URL"
        EXIT_CODE=$?
    else
        wget --show-progress -q \
            --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
            --keep-session-cookies \
            --save-cookies "$COOKIE_JAR" \
            --load-cookies "$COOKIE_JAR" \
            -O "$OUT" \
            "$DIRECT_URL"
        EXIT_CODE=$?
    fi

    rm -f "$COOKIE_JAR"
    return $EXIT_CODE
}

# list aval asset packs
mapfile -t JSON_FILES < <(find "$REGISTRY_DIR" -maxdepth 1 -name "*.json" | sort)

if [ ${#JSON_FILES[@]} -eq 0 ]; then
    print_error "no pack definitions found in AssetRegistry/"
    exit 1
fi

echo ""
echo -e "${BOLD}asset-registry${NC} available packs"
echo ""

INDEX=1
declare -A PACK_MAP

for json in "${JSON_FILES[@]}"; do
    NAME=$(get_field "$json" "name")
    VERSION=$(get_field "$json" "version")
    DESCRIPTION=$(get_field "$json" "description")
    UE_VER=$(get_field "$json" "ue_version")
    printf "  ${CYAN}[%d]${NC} %-35s ${YELLOW}v%s${NC}  (UE %s)\n" "$INDEX" "$NAME" "$VERSION" "$UE_VER"
    echo -e "       ${DESCRIPTION}"
    PACK_MAP[$INDEX]="$json"
    INDEX=$((INDEX + 1))
done

echo ""
echo -e "  ${CYAN}[a]${NC} install all packs"
echo -e "  ${CYAN}[q]${NC} quit"
echo ""

# user prompt
read -rp "  select pack: " SELECTION
echo ""

if [ "$SELECTION" = "q" ]; then
    print_info "aborted"
    echo ""
    exit 0
fi

if [ "$SELECTION" = "a" ]; then
    SELECTED_FILES=("${JSON_FILES[@]}")
else
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ -z "${PACK_MAP[$SELECTION]}" ]; then
        print_error "invalid selection: '$SELECTION'"
        echo ""
        exit 1
    fi
    SELECTED_FILES=("${PACK_MAP[$SELECTION]}")
fi

# packs installing
mkdir -p "$DOWNLOAD_DIR"
TOTAL=0
FAILED=0

for json in "${SELECTED_FILES[@]}"; do

    NAME=$(get_field "$json" "name")
    VERSION=$(get_field "$json" "version")
    FILE=$(get_field "$json" "file")
    URL=$(get_field "$json" "download_url")
    SHA256=$(get_field "$json" "sha256")
    INSTALL_PATH=$(get_field "$json" "install_path")

    DEST_DIR="$PROJECT_DIR/$INSTALL_PATH"
    ZIP_PATH="$DOWNLOAD_DIR/$FILE"

    echo -e "${BOLD}pack${NC} ${NAME} v${VERSION}"

    # fields validation
    if [ -z "$URL" ] || echo "$URL" | grep -q '<'; then
        print_error "download_url is missing or a placeholder — skipping"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # checking if not empty
    if [ -z "$FILE" ]; then
        print_error "field 'file' is empty — skipping"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # google drive url validationg
    if ! echo "$URL" | grep -q 'drive.google.com\|drive.usercontent.google.com'; then
        print_error "download_url is not a Google Drive link"
        print_error "  expected: drive.google.com/<url>"
        print_error "  got:      $URL"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # extracting file id
    FILE_ID=$(gdrive_extract_id "$URL")

    if [ -z "$FILE_ID" ]; then
        print_error "could not extract file ID from: $URL"
        print_error "  supported formats:"
        print_error "    drive.google.com/file/d/FILE_ID/view"
        print_error "    drive.google.com/uc?export=download&id=FILE_ID"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    print_info "file id: $FILE_ID"
    print_fetch "drive.usercontent.google.com → $FILE"

    # downloading
    gdrive_download "$FILE_ID" "$ZIP_PATH"
    DOWNLOAD_EXIT=$?

    if [ $DOWNLOAD_EXIT -ne 0 ]; then
        print_error "download failed (exit $DOWNLOAD_EXIT)"
        rm -f "$ZIP_PATH"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # check for not an html 
    MIME=$(file --mime-type -b "$ZIP_PATH" 2>/dev/null)
    if echo "$MIME" | grep -q 'html\|text'; then
        print_error "downloaded file appears to be HTML, not a ZIP"
        print_error "  check if the Google Drive link is public (Anyone with link → Viewer)"
        rm -f "$ZIP_PATH"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # verift sha key
    if [ -n "$SHA256" ] && ! echo "$SHA256" | grep -q '<'; then
        ACTUAL_SHA=$(sha256sum "$ZIP_PATH" | awk '{print $1}')
        if [ "$ACTUAL_SHA" != "$SHA256" ]; then
            print_error "sha256 mismatch — file may be corrupted"
            print_error "  expected: $SHA256"
            print_error "  got:      $ACTUAL_SHA"
            rm -f "$ZIP_PATH"
            FAILED=$((FAILED + 1))
            echo ""
            continue
        fi
        print_ok "sha256 verified"
    else
        print_warn "sha256 not defined — skipping integrity check"
    fi

    # extracting
    mkdir -p "$DEST_DIR"
    print_info "extracting to $INSTALL_PATH"

    if ! unzip -q -o "$ZIP_PATH" -d "$PROJECT_DIR"; then
        print_error "extraction failed"
        rm -f "$ZIP_PATH"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    rm -f "$ZIP_PATH"

    print_ok "${NAME} v${VERSION} installed → ${INSTALL_PATH}"
    TOTAL=$((TOTAL + 1))
    echo ""

done

# cleanup for empty download dir
rmdir "$DOWNLOAD_DIR" 2>/dev/null

# summary
if [ $FAILED -gt 0 ] && [ $TOTAL -gt 0 ]; then
    echo -e "asset-registry ${GREEN}${TOTAL} installed${NC}, ${RED}${FAILED} failed${NC}"
elif [ $FAILED -gt 0 ]; then
    echo -e "asset-registry ${RED}${FAILED} failed${NC}"
else
    echo -e "asset-registry ${GREEN}${TOTAL} pack(s) installed${NC}"
fi

echo ""
