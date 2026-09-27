#!/usr/bin/env bash

set -uo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "  ${BLUE}info${NC}    $1"; }
print_ok()    { echo -e "  ${GREEN}ok${NC}      $1"; }
print_warn()  { echo -e "  ${YELLOW}warn${NC}    $1"; }
print_error() { echo -e "  ${RED}error${NC}   $1"; }
print_fetch() { echo -e "  ${CYAN}fetch${NC}   $1"; }

INPUT_FILE=""
OUTPUT_DIR="./downloads"
LOG_FILE=""
FAIL_FILE=""
QUIET=0

help() {
    cat <<EOF
Usage:
$(basename "$0") -i <input file> [options]

Options:
  -i, --input <file>     Input file
  -o, --output <dir>     Output directory (default: ./downloads)
  -l, --log <file>       Log the run current run
  -f, --fails <file>     Write unsuccessful downloads to a separate list
  -q, --quiet            Less talking from yt-dlp
  -h, --help             Displays this message

Example:
  $(basename "$0") -i links.txt -o videos/important/ -l run.log -f failed.txt
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)  INPUT_FILE="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -l|--log)    LOG_FILE="$2"; shift 2 ;;
        -f|--fails)  FAIL_FILE="$2"; shift 2 ;;
        -q|--quiet)  QUIET=1; shift ;;
        -h|--help)   help; exit 0 ;;
        *)
            print_error "unknown option: $1"
            help
            exit 1
            ;;
    esac
done

if [[ -n "$LOG_FILE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    print_info "logging to $LOG_FILE"
fi

if [[ -z "$INPUT_FILE" ]]; then
    print_error "no input file was given"
    help
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    print_error "file '$INPUT_FILE' already exists"
    exit 1
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
    print_error "yt-dlp is not installed. Install: pip install -U yt-dlp"
    exit 1
fi

mkdir -p "$OUTPUT_DIR" || { print_error "unable to open directory '$OUTPUT_DIR'."; exit 1; }

is_supported_link() {
    local url="$1"
    [[ "$url" =~ ^https?://([a-zA-Z0-9._-]+\.)?(tiktok\.com|vm\.tiktok\.com|vt\.tiktok\.com|instagram\.com)(/.*)?$ ]]
}

declare -a FAILED_LINKS=()
TOTAL=0
OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

YTDLP_OPTS=(--no-warnings --output "${OUTPUT_DIR}/%(extractor)s_%(id)s.%(ext)s")
[[ "$QUIET" -eq 1 ]] && YTDLP_OPTS+=(--quiet --no-progress)

print_info "fetching URLs from $INPUT_FILE"
print_info "downloading to $OUTPUT_DIR"
echo

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="${raw_line%%#*}"
    line="$(echo -n "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    [[ -z "$line" ]] && continue

    TOTAL=$((TOTAL + 1))

    if ! is_supported_link "$line"; then
        print_warn "unresolved URL, skipping: $line"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    print_fetch "$line"

    ytdlp_output="$(yt-dlp "${YTDLP_OPTS[@]}" "$line" 2>&1)"
    ytdlp_status=$?

    if [[ "$ytdlp_status" -eq 0 ]]; then
        print_ok "downloaded: $line"
        OK_COUNT=$((OK_COUNT + 1))
    else
        print_error "failed to download, skipping: $line"
        echo "$ytdlp_output" | grep -E '^ERROR' | tail -n 3 | sed 's/^/           /'
        if ! echo "$ytdlp_output" | grep -q '^ERROR'; then
            echo "$ytdlp_output" | tail -n 3 | sed 's/^/           /'
        fi
        FAILED_LINKS+=("$line")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$INPUT_FILE"

echo
print_info "summary: $TOTAL URLs, ${GREEN}$OK_COUNT ok${NC}, ${RED}$FAIL_COUNT errors${NC}, ${YELLOW}$SKIP_COUNT skipped${NC}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo
    print_warn "failed downloads: "
    for link in "${FAILED_LINKS[@]}"; do
        echo "    - $link"
    done

    if [[ -n "$FAIL_FILE" ]]; then
        printf '%s\n' "${FAILED_LINKS[@]}" > "$FAIL_FILE"
        print_info "saved failed downloads to $FAIL_FILE"
    fi
fi

exit 0