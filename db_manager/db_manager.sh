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
    case BANNER in
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

# check for root 
if (( UID != 0 )); then
    echo -e "${RED}[ERROR]${NC} You are not running as root ${NC}"
    echo -e "${NC}\"\$ sudo ./!db.sh\" or \"su - && ./!db.sh\"${NC}"
    exit 1
fi

# check for psql
if ! command -v psql > /dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} PostgreSQL is not installed.${NC}"
    echo -e "${NC}Run: \"sudo apt install postgresql\" to install it.${NC}"
    exit 1
fi

if [[ ${1:=} == "--help" ]]; then
    echo -e "${NC}Usage: sudo ./!db.sh [OPTIONS]${NC}"
    echo -e "${NC} [--start | --stop | --restart] -u <username> -p <password> --drop-existing-db${NC}"
    echo -e "${NC}\n${NC}"
    echo -e "${NC}Manage PostgreSQL service and database setup.${NC}"
    echo -e "${NC}Options:${NC}"
    echo -e "${YELLOW}  --start${NC}                     Start PostgreSQL service"
    echo -e "${YELLOW}  --stop${NC}                      Stop PostgreSQL service"
    echo -e "${YELLOW}  --restart${NC}                   Restart PostgreSQL service"
    echo -e "${YELLOW}  -u <username> -p <password>${NC} Create a new PostgreSQL user with the specified username and password"
    echo -e "${YELLOW}  --drop-existing-db${NC}          Drop the existing database if it exists before creating a new one"
    exit 0
fi

if [[ ${1:=} == "--status" ]]; then
    echo -e "${YELLOW}[NOTICE]${NC} Checking PostgreSQL daemon status...${NC}"
    systemctl is-active --quiet postgresql || {
        echo -e "${RED}[ERROR]${NC} PostgreSQL daemon is not running.${NC}"
        exit 1
    }
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL daemon is active.${NC}"

    echo -e "${YELLOW}[NOTICE]${NC} Checking ${DB_NAME} database state...${NC}"
    
    timeout 10 pg_isready -d ${DB_NAME} -q || {
        echo -e "${RED}[ERROR]${NC} Database '${DB_NAME}' is not responding or timed out.${NC}"
        exit 1
    }
    echo -e "${HIGHLIGHT}[OK]${NC} Database '${DB_NAME}' is ready.${NC}"

    exit 0
fi

# staring flag
if [[ ${1:=} == "--start" ]]; then
    echo -e "${YELLOW}[NOTICE]${NC} Starting PostgreSQL...${NC}"
    timeout 10 systemctl start postgresql || {
        echo -e "${RED}[ERROR]${NC} PostgreSQL start timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${RED}[ERROR] ${NC}PostgreSQL failed to start. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL started successfully.${NC}"
    exit_text
    exit 0
fi

# stop flag
if [[ ${1:=} == "--stop" ]]; then
    echo -e "${YELLOW}[NOTICE]${NC} Stopping PostgreSQL...${NC}"
    timeout 10 systemctl stop postgresql || {
        echo -e "${RED}[ERROR]${NC} PostgreSQL stop timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" == "active" ]]; then
        echo -e "${RED}[ERROR] ${NC}PostgreSQL failed to stop. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL stopped successfully.${NC}"
    exit 0
fi

# restart flag
if [[ ${1:=} == "--restart" ]]; then
    echo -e "${YELLOW}[NOTICE]${NC} Restarting PostgreSQL...${NC}"
    timeout 10 systemctl restart postgresql || {
        echo -e "${RED}[ERROR]${NC} PostgreSQL restart timed out.${NC}"
        exit 1
    }
    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${RED}[ERROR] ${NC}PostgreSQL failed to restart. ${NC}"
        exit 1
    fi
    echo -e "${HIGHLIGHT}[OK]${NC} PostgreSQL restarted successfully.${NC}"
    exit_text
    exit 0
fi

# check is psql active
if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
    echo -e "${YELLOW}[NOTICE]${NC} PostgreSQL is not running. Starting...${NC}"
    
    timeout 10 systemctl start postgresql || {
        echo "${RED}[ERROR]${NC} PostgreSQL start timed out.${NC}"
        exit 1
    }

    if [[ "$(systemctl is-active postgresql)" != "active" ]]; then
        echo -e "${RED}[ERROR] ${NC}PostgreSQL failed to start. ${NC}"
        exit 1
    fi
fi

# user adding
if [[ ${1:-} == "-u" && ${3:-} == "-p" ]]; then
    NEW_USER="$2"
    NEW_PASS="$4"

    ADD_USER=${NEW_USER};

    echo -e "${NC}Creating/Checking user \"${NEW_USER}\"...${NC}"
    
    sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 <<-EOF
        DO \$$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$NEW_USER') THEN
                CREATE ROLE "$NEW_USER" WITH LOGIN PASSWORD '$NEW_PASS';
                ALTER ROLE "$NEW_USER" WITH LOGIN;
            END IF;
        END
        \$$;
EOF

    echo -e "${NC}Added user: \"${NEW_USER}\".${NC}"
    echo -e "${YELLOW}[NOTICE]${NC}Remeber to keep your password private."
fi

# check for db user
if ! id -u "${DB_USER}" > /dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} PostgreSQL user \"${DB_USER}\" does not exist.${NC}"
    echo -e "${NC}Create the user with: \"sudo -u postgres createuser ${DB_USER}\"${NC}"
    exit 1
fi

# check for --drop-existing-db arg
if [[ ${1:-} == "--drop-existing-db" ]]; then
    if sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" | grep -q 1; then
        affirm "Do you want to drop existing database \"${DB_NAME}\"" || {
            echo -e "${NC}Script aborted by user.${NC}"
            exit 1
        }
        
        echo -e "\n${YELLOW}Terminating active connections to \"${DB_NAME}\"...${NC}"
        sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
        "

        echo -e "${YELLOW}Dropping existing database \"${DB_NAME}\"...${NC}"
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
if ! sudo -u "${DB_USER}" psql -v ON_ERROR_STOP=1 -tAc "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Cannot connect to PostgreSQL as user \"${DB_USER}\".${NC}"
    echo -e "${NC}Check PostgreSQL installation and user permissions.${NC}"
    exit 1
fi

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
            echo -e "${YELLOW}>[PSQL 0]${NC}Database already exists, skipping.${NC}"
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

print_bye
echo ""
exit 0
