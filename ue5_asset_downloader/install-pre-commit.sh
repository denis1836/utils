#!/bin/bash

confirm(){
    comm=${1:-"Are you sure?"}

    if [[ ${YES} == true ]]; then
        return 0
    fi

    while true; do 
        echo -e -n "${comm} [y/n] " 
        read -r -n 1 ans
        echo ""
        case $ans in 
            [Yy] ) return 0;; 
            [Nn] ) return 1;; 
            * ) echo -e "Invalid argument provided.";; 
        esac
    done
}

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)

if [ -z "$GIT_DIR" ]; then
    echo "Error: Installer must be run inside a git repository."
    exit 1
fi

HOOK_PATH="${GIT_DIR}/hooks/pre-commit"

echo "Warning: Running this installer will override existing pre-commit hook at: ${HOOK_PATH}"

if ! confirm "Do you want to proceed?"; then
    echo "Abort."
    exit 0
fi

cat << 'EOF' > "$HOOK_PATH"
#!/bin/bash
# pre-commit hook for ue5 asset downloader

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKED=0

STAGED_FILES=()
while IFS= read -r file; do
    [ -n "$file" ] && STAGED_FILES+=("$file")
done < <(git diff --cached --name-only --diff-filter=ACM | grep "^AssetRegistry/.*\.json$")

if [ ${#STAGED_FILES[@]} -eq 0 ]; then
    exit 0
fi

echo -e "\n${BOLD}asset-registry${NC} validating staged pack definitions...\n"

for file in "${STAGED_FILES[@]}"; do
    echo -e "  ${CYAN}check${NC}   $file"

    VALIDATION_OUTPUT=$(python3 - "$file" 2>&1 << 'PYEOF'
import json, sys, re, os

filepath = sys.argv[1]

try:
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"ERROR: invalid JSON syntax ({e})")
    sys.exit(0)

if not isinstance(data, dict):
    print("ERROR: JSON root must be an object ({})")
    sys.exit(0)

required = ["name", "version", "date", "author", "description", "file", "download_url", "sha256", "ue_version", "install_path", "contents", "changelog"]
for field in required:
    if field not in data or data[field] is None or (isinstance(data[field], (str, list)) and len(data[field]) == 0):
        print(f"ERROR: missing required field '{field}'")

sha = str(data.get('sha256', ''))
if sha.startswith('<') or not sha:
    print("ERROR: field 'sha256' is still a placeholder — run: sha256sum <file.zip>")

url = str(data.get('download_url', ''))
if '<' in url or not url:
    print("ERROR: field 'download_url' is still a placeholder")

version = str(data.get('version', ''))
if not re.match(r'^[0-9]+\.[0-9]+\.[0-9]+$', version):
    print(f"WARN: field 'version' is not semver — expected X.Y.Z, got '{version}'")

date_val = str(data.get('date', ''))
if not re.match(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$', date_val):
    print(f"WARN: field 'date' is not ISO 8601 — expected YYYY-MM-DD, got '{date_val}'")

file_field = str(data.get('file', ''))
if not file_field.endswith('.zip'):
    print(f"WARN: field 'file' does not end with .zip")

basename = os.path.splitext(os.path.basename(filepath))[0]
file_no_ext = os.path.splitext(file_field)[0]
if basename != file_no_ext:
    print(f"WARN: filename '{basename}.json' does not match 'file' field '{file_field}'")

PYEOF
    )

    file_has_error=0
    while IFS= read -r line; do
        if [[ "$line" == ERROR:* ]]; then
            echo -e "  ${RED}error${NC}   $file: ${line#ERROR: }"
            ERRORS=$((ERRORS + 1))
            file_has_error=1
        elif [[ "$line" == WARN:* ]]; then
            echo -e "  ${YELLOW}warn${NC}    $file: ${line#WARN: }"
            WARNINGS=$((WARNINGS + 1))
        fi
    done <<< "$VALIDATION_OUTPUT"

    CHECKED=$((CHECKED + 1))
    if [ $file_has_error -eq 0 ]; then
        echo -e "  ${GREEN}ok${NC}      $file"
    fi
done

echo ""
if [ $ERRORS -gt 0 ]; then
    echo -e "asset-registry ${RED}$ERRORS error(s)${NC}, ${YELLOW}$WARNINGS warning(s)${NC} — commit aborted"
    echo ""
    exit 1
else
    echo -e "asset-registry ${GREEN}$CHECKED pack(s) ok${NC}, ${YELLOW}$WARNINGS warning(s)${NC}"
    echo ""
    exit 0
fi
EOF

chmod +x "$HOOK_PATH"

echo "git pre-commit hook installed to ${HOOK_PATH}"
echo "You can remove this script."