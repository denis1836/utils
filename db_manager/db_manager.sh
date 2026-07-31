#!/bin/bash

# navigate to script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# default colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
ORANGE='\e[38;5;202m'
BLUE='\033[0;34m'
NC='\033[0m'

# color types
HIGHLIGHT=$GREEN
WARNING=$ORANGE
NOTICE=$YELLOW
ERROR=$RED

# configuration file
CONF_FILE="./db_manager.conf"
source "$CONF_FILE"


# filtering messages based on verbosity var
msg() {
    local level="$1"; shift
    case "$VERBOSITY" in
        full)    echo -e "$@" ;;
        minimal) [[ "$level" == "minimal" || "$level" == "quiet" ]] && echo -e "$@" ;;
        quiet)   [[ "$level" == "quiet" ]] && echo -e "$@" ;;
    esac
}

# affirmation func
affirm(){
comm=${1:-"Are you sure?"}
    while true; do 
        echo -e -n "${NC}${comm}?[y/n]${NC}" 
        read -r -n 1 ans
        echo -e -n "${NC}${NC}"
        case $ans in 
            [Yy] ) return 0;; 
            [Nn] ) return 1;; 
            * ) echo -e "${NC}\nInvalid argument provided.${NC}";; 
        esac
    done
}

# prints app banner
print_banner() {
    case "$BANNER" in
        yes)
            echo -e "${NC}${BANNER_TEXT}${NC}"
        ;;
        no) : ;;
    esac
}

# shows a welcome text
print_hello() {
    case $HELLO in
        full)
            echo -e "${NC}--------------------------------------------------------------------------${NC}"
            echo -e "${NC}Welcome to the ${HIGHLIGHT}${SERVICE_NAME}${NC} database managment script${NC}"
            echo -e "${NC}--------------------------------------------------------------------------${NC}"
            ;;
        minimal)
            echo -e "${HIGHLIGHT}${SERVICE_NAME}${NC} db manager" 
            ;;
        quiet) : ;;
    esac
}

print_bye() {
    case $BYE in
        full)
            echo -e ""
            echo -e "${HIGHLIGHT}[SUCCESS]${NC} Database setup completed!${NC}"
            echo -e "${NC}-------------------------------------------------------------${NC}"
            echo -e "${NC}You can now connect to the database using:${NC}"
            echo -e "${HIGHLIGHT}sudo -u ${DB_USER} psql -d ${DB_NAME}${NC}"
            echo -e "${NC}-------------------------------------------------------------${NC}"
            echo -e "${NC}Have a great day!${NC}"
            ;;
        minimal)
            echo -e "${NC}Bye!${NC}"
            ;;
        quiet) : ;;
    esac
}

# error msg
trap 'echo -e "\n${NC}${RED}[ERROR]${NC}\n===========================================================\n Installation failed - an unexpected error occurred.\n Check systemctl for possible errors. \n===========================================================\n${NC}"; exit 1' ERR
set -Eeuo pipefail

# log output
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
fi

CURRENT_LOG_NAME=$(date +"$LOG_FILE_NAME_PATTERN")
LOG_FILE="${LOG_DIR}/${CURRENT_LOG_NAME}"

if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE" 2>/dev/null
fi

if [[ ! -w "${LOG_FILE}" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} Cannot write to log file at \"${LOG_FILE}\".${NC}"
    affirm "Do you want to proceed without logging?" || {
        echo -e "${NC}Script aborted by user.${NC}"
        exit 1
    }
    echo -e "${NC}Proceeding without logging.${NC}"
    LOG_FILE=""
fi

exec > >(tee >(sed -r 's/\x1b\[[0-9;]*m//g' | awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0 }' >> $LOG_FILE))
exec 2>&1

print_banner
print_hello

# check os
if [[ "$(uname)" != "Linux" || $OSTYPE != linux* ]]; then
    echo -e "${YELLOW}[WARNING]${NC} This script is designed to run on Linux systems.${NC}"
    echo -e "${YELLOW}Proceeding may lead to unexpected behavior.${NC}"
    affirm "Do you want to proceed" || {
        echo -e "${NC}Script aborted by user.${NC}"
        exit 1
    }
fi

# check for psql
if ! command -v psql > /dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} PostgreSQL is not installed.${NC}"
    echo -e "${NC}Run: \"sudo apt install postgresql\" to install it.${NC}"
    exit 1
fi

ACTION=""
DB_ACTION=""
USER_ACTION=""
GRANT_LEVEL=""

PSQL_RUNNER=""
TARGET_USER=""
PROMPT_PASSWORD=false

QUERY_TEXT=""
QUERY_FILE=""
QUERY_SOURCE=""

RUN_FROM=0
RUN_TO=0
RUN_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --start) ACTION="start"; shift ;;
        --stop) ACTION="stop"; shift ;;
        --restart) ACTION="restart"; shift ;;
        --status) ACTION="status"; shift ;;
        --drop-existing-db) DB_ACTION="drop-db"; shift ;;
        --help) ACTION="help"; shift ;;
        
        --user)
            ACTION="user"
            USER_ACTION="${2:?--user requires: add, remove, grant, or passwd}"
            shift 2
        ;;

        -U)
            PSQL_RUNNER="${2:?-U requires a username}"
            shift 2
        ;;
       
        -u)
            TARGET_USER="${2:?-u requires a username}"
            shift 2
        ;;
        
        -p) PROMPT_PASSWORD=true; shift ;;
        
        --level)
            GRANT_LEVEL="${2:?--level requires: read, readwrite, or all}"
            shift 2
        ;;

        query)
            ACTION="query"
            shift
            if [[ "${1:-}" == "-f" ]]; then
                QUERY_FILE="${2:?-f requires a file path}"
                shift 2
            elif [[ "${1:-}" == "-" || $# -eq 0 ]]; then
                QUERY_SOURCE="stdin"
                [[ "${1:-}" == "-" ]] && shift
            else
                QUERY_TEXT="$1"
                shift
            fi
        ;;

        --run) ACTION="run"; shift ;;

        --from)
            RUN_FROM="${2:?--from requires a number}"
            shift 2
        ;;
        --to)
            RUN_TO="${2:?--to requires a number}"
            shift 2
        ;;

        --all) RUN_ALL=true; shift ;;

        --) shift; break ;;

        -*)
            echo -e "Error: unknowk option '$1'" >&2
            echo -e "Run with --help to see availble options" >&2
            exit 1
        ;;
        *)
            echo "Error: unexpected argument '$1'" >&2
            exit 1
        ;;
    esac
done

ACTION="${ACTION:-setup}"

# check for root for systemctl actions
if [[ "$ACTION" =~ ^(start|stop|restart)$ ]] && (( UID != 0 )); then
    echo -e "${RED}[ERROR]${NC} Managing the PostgreSQL service requires root or sudo.${NC}"
    exit 1
fi

case "$ACTION" in
    user)
        case "$USER_ACTION" in
            add|remove|grant|passwd) ;;
            *) 
                echo "Error: --user must be one of: add, remove, grant, passwd" >&2 
                exit 1 
            ;;
        esac

        [[ -z "$TARGET_USER" ]] && { 
            echo "Error: --user $USER_ACTION requires -u <name>" >&2
            exit 1
        }

        if [[ "$USER_ACTION" == "add" || "$USER_ACTION" == "passwd" ]] && [[ "$PROMPT_PASSWORD" != true ]]; then
            echo "Error: --user $USER_ACTION requires -p (password prompt)" >&2
            exit 1
        fi

        if [[ -n "$GRANT_LEVEL" && "$USER_ACTION" != "grant" ]]; then
            echo "Error: --level only applies to --user grant" >&2
            exit 1
        fi
    ;;
    
    query)
        if [[ -z "$QUERY_TEXT" && -z "$QUERY_FILE" && "$QUERY_SOURCE" != "stdin" ]]; then
            echo "Error: query requires SQL text, -f <file>, or stdin input" >&2
            exit 1
        fi
        if [[ "$PROMPT_PASSWORD" == true && "$QUERY_SOURCE" == "stdin" ]]; then
            echo "Error: -p (password prompt) can't be combined with stdin query input" >&2
            exit 1
        fi
    ;;
    
    run)
        if [[ "${RUN_ALL:-false}" == true && ( -n "${RUN_FROM:-}" || -n "${RUN_TO:-}" ) ]]; then
            echo "Error: --all cannot be combined with --from/--to" >&2
            exit 1
        fi
        if [[ "${RUN_ALL:-false}" != true && -z "${RUN_FROM:-}" && -z "${RUN_TO:-}" ]]; then
            echo "Error: --run requires --all, or --from/--to" >&2
            exit 1
        fi
    ;;
esac

determine_psql_runner() {
    if [[ "$(id -un)" == "${DB_USER}" ]]; then
        PSQL_RUNNER=""
        return 0
    fi

    if (( UID == 0 )); then
        PSQL_RUNNER="sudo -u ${DB_USER}"
        return 0
    fi

    if sudo -n -u "${DB_USER}" true 2>/dev/null; then
        PSQL_RUNNER="sudo -u ${DB_USER}"
        return 0
    fi

    if id -nG "$(id -un)" 2>/dev/null | tr ' ' '\n' | grep -qx "${DB_ADMIN_GROUP:-postgres}"; then
        if sudo -n -u "${DB_USER}" true 2>/dev/null; then
            PSQL_RUNNER="sudo -u ${DB_USER}"
            return 0
        fi
    fi

    echo -e "${ERROR}[ERROR]${NC} Cannot run as \"${DB_USER}\" without a password prompt.${NC}"
    echo -e "${NC}Options:${NC}"
    echo -e "${NC} - run this script as \"${DB_USER}\" directly${NC}"
    echo -e "${NC} - run with sudo${NC}"
    echo -e "${NC} - ask an admin to add a NOPASSWD sudo rule for user \"${DB_USER}\"${NC}"
    return 1
}

show_help() {
    echo -e "${NC}Usage: sudo ./!db.sh [OPTIONS]${NC}"
    echo -e "${NC} [--start | --stop | --restart] -u <username> -p <password> --drop-existing-db${NC}"
    echo -e "${NC}\n${NC}"
    echo -e "${NC}Manage PostgreSQL service and database setup.${NC}"
    echo -e "${NC}Options:${NC}"
    echo -e "${HIGHLIGHT}  --start${NC}                     Start PostgreSQL service"
    echo -e "${HIGHLIGHT}  --stop${NC}                      Stop PostgreSQL service"
    echo -e "${HIGHLIGHT}  --status${NC}                    Check PostgreSQL databse state"
    echo -e "${HIGHLIGHT}  --restart${NC}                   Restart PostgreSQL service"
    echo -e "${HIGHLIGHT}  -u <username> -p ${NC}           Create a new PostgreSQL user with the specified username and password"
    echo -e "${HIGHLIGHT}  --drop-existing-db${NC}          Drop the existing database if it exists before creating a new one"
    exit 0
    # TODO: add new commands in help text
}

run_status() {
    echo -e "${NOTICE}[NOTICE]${NC} Checking PostgreSQL daemon status...${NC}"
    systemctl is-active --quiet postgresql || {
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL daemon is not running.${NC}"
        exit 1
    }
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL daemon is active.${NC}"

    echo -e "${NOTICE}[NOTICE]${NC} Checking ${DB_NAME} database state...${NC}"
    
    timeout 10 pg_isready -d ${DB_NAME} -q || {
        echo -e "${ERROR}[ERROR]${NC} Database '${DB_NAME}' is not responding or timed out.${NC}"
        exit 1
    }
    echo -e "${HIGHLIGHT}[OK]${NC} Database '${DB_NAME}' is ready.${NC}"
    exit 0
}

# staring flag
run_start() {
    echo -e "${NOTICE}[NOTICE]${NC} Starting PostgreSQL...${NC}"
    timeout 10 systemctl start postgresql || {
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL start timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL failed to start. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL started successfully.${NC}"
    exit 0
}

# stop flag
run_stop() {
    echo -e "${NOTICE}[NOTICE]${NC} Stopping PostgreSQL...${NC}"
    timeout 10 systemctl stop postgresql || {
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL stop timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" == "active" ]]; then
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL failed to stop. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL stopped successfully.${NC}"
    exit 0
}

# restart flag
run_restart() {
    echo -e "${NOTICE}[NOTICE]${NC} Restarting PostgreSQL...${NC}"
    timeout 10 systemctl restart postgresql || {
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL restart timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${ERROR}[ERROR]${NC} PostgreSQL failed to restart. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL restarted successfully.${NC}"
    exit 0
}

# check is psql active
check_psql_daemon() {
    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${NOTICE}[NOTICE]${NC} PostgreSQL is not running. Starting...${NC}"

        timeout 10 systemctl start postgresql || {
            echo "${ERROR}[ERROR]${NC} PostgreSQL start timed out.${NC}"
            exit 1
        }

        if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
            echo -e "${ERROR}[ERROR]${NC} PostgreSQL failed to start. ${NC}"
            exit 1
        fi
    fi
}


# user adding
run_user_action() {
case "$USER_ACTION" in
    add)
        #TODO: get user login and password
        local user_login="$2"
        local user_pass=""
        
        if [[ $PROMPT_PASSWORD ]]; then
            while true; do 
                user_entry1=""
                user_entry2=""

                read -s -p "Enter user password: " user_entry1
                read -s -p "Confirm password: " user_entry2

                if [[ "$user_entry1" != "$user_entry2" ]]; then
                    echo -e "${ERROR}Error: ${NC}Passwords do not match.${NC}"
                    continue
                fi
                
                user_pass="$user_entry2"
                break
            done
        fi

        echo -e "${NC}Adding user \"${user_login}\"...${NC}"
    
        "${PSQL_RUNNER}" psql -v ON_ERROR_STOP=1 -c "
            DO \$$
            BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$user_login') THEN
                CREATE ROLE "$user_login" WITH LOGIN PASSWORD '$user_pass';
                ALTER ROLE "$user_login" WITH LOGIN;
            END IF;
            END
            \$$;
        "

    echo -e "${NC}Added user: \"${user_login}\".${NC}"
    echo -e "${NOTICE}[NOTICE]${NC}Remeber to keep your password private."

    ;;

    remove)
        
    ;;

    grant)

    ;;

    passwd)

    ;;
esac
}

# check for db user
if ! id -u "${DB_USER}" > /dev/null 2>&1; then
    echo -e "${ERROR}[ERROR]${NC} PostgreSQL user \"${DB_USER}\" does not exist.${NC}"
    echo -e "${NC}Create the user with: \"sudo -u postgres createuser ${DB_USER}\"${NC}"
    exit 1
fi

# check for --drop-existing-db arg
if [[ ${1:-} == "--drop-existing-db" ]]; then
    if ${PSQL_RUNNER} psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" | grep -q 1; then
        affirm "Do you want to drop existing database \"${DB_NAME}\"? This action will destroy ALL the data." || {
            echo -e "${NC}Script aborted by user.${NC}"
            exit 1
        }
        
        echo -e "\n${NOTICE}Terminating active connections to \"${DB_NAME}\"...${NC}"
        ${PSQL_RUNNER} psql -v ON_ERROR_STOP=1 -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
        "

        echo -e "${WARNING}Dropping existing database \"${DB_NAME}\"...${NC}"
        sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${DB_NAME};"
        echo -e "${HIGHLIGHT}Existing database dropped.${NC}"
        exit 0
    else
        echo -e "${HIGHLIGHT}Database \"${DB_NAME}\" does not exist. Nothing to drop.${NC}"
        exit 0
    fi
fi

# check for files
# TODO

#check psql connection
check_psql_conn() {
    if ! sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -tAc "SELECT 1;" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to PostgreSQL as user \"${DB_USER}\".${NC}"
        echo -e "${NC}Check PostgreSQL installation and user permissions.${NC}"
        exit 1
    fi
}

#check if db exists
if sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -tAc \
  "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" | grep -q 1; then
    echo -e "${YELLOW}[WARNING]${NC} Database \"${DB_NAME}\" already exists.${NC}"
    affirm "Do you want to proceed and possibly overwrite existing database" || {
        echo -e "${NC}Script aborted by user.${NC}"
        exit 1
    }
fi

#files amount found msg
echo -e "${HIGHLIGHT}${#SQL_FILES[@]}${NC} SQL files were found.${NC}"
echo -e "${NC}Proceeding to create the database...${NC}"

#execute psql commands
i=0
for SQL_command in "${SQL_FILES[@]}"; do
    echo -e "${NOTICE}>[PSQL ${i}]${NC}Executing $...${NC}"
    if [[ $i -eq 0 ]]; then
        if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';"  | grep -q 1; then
            sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -f 00_*.sql
        else
            echo -e "${WARNING}>[PSQL 0]${NC}Database already exists, skipping.${NC}"
        fi
    else
        sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -f "${SQL_command}"
    fi

    i=$((i + 1))
done
unset i

#end psql commands msg
echo -e "${HIGHLIGHT}[PSQL]${NC} All SQL files were executed.${NC}"
echo -e "${NC}Verifying database integrity...${NC}"

#verify db creation
if ! sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -tAc \
  "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" | grep -q 1; then
    echo -e "${RED}[ERROR]${NC} Database ${DB_NAME} was ${RED}NOT${NC} created successfully.${NC}"
    echo -e "${NC}Database setup incomplete. Check SQL files for possible errors or run the script again.${NC}"
    exit 1
fi

#verify tables
for table in "${required_tables[@]}"; do
    if ! sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -tAc \
    "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND lower(table_name)=lower('${table}');" | grep -q 1; then
        echo -e "${RED}[ERROR]${NC} Missing table \"${table}\"${NC}"
        echo -e "${NC}Database setup incomplete. Check SQL files for possible errors and run the script again.${NC}"
        exit 1
    fi
done

affirm "Do you want to grant all privileges on the database to user \"${ADD_USER}\"" && {
    sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${ADD_USER};"
    sudo -u "${DB_USER}" psql -d "${DB_NAME}" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${ADD_USER};" 
    sudo -u "${DB_USER}" psql -d "${DB_NAME}" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${ADD_USER};"
    sudo -u "${DB_USER}" psql -d "${DB_NAME}" -c "GRANT USAGE ON SCHEMA cron TO ${ADD_USER};"
    echo -e "${HIGHLIGHT}[OK]${NC}Privileges granted to user \"${ADD_USER}\".${NC}"
}

case "$ACTION" in
    help) show_help ;;
    status) run_status ;;
    start) run_start ;;
    stop) run_stop ;;
    restart) run_restart ;;
    user) run_user_action ;;
    query) run_query ;;
    setup) run_setup ;;
esac

print_bye
echo ""
exit 0
