# db_manager

A single-file Bash script for managing a PostgreSQL database and its setup
SQL files, without hardcoding anything project-specific into the script
itself. One `db_manager.sh` + one `db_manager.conf` per project.

- Runs your numbered `*.sql` files in order (full setup, or a specific range)
- Manages PostgreSQL roles: create, remove, change password, grant privileges
- Runs ad-hoc queries (inline, from a file, or piped via stdin)
- Starts/stops/restarts the PostgreSQL service and reports its status
- Works without full root, as long as the current user can reach `DB_USER` _(see [Permissions model](#permissions-model))_

## Requirements

- Linux with Bash and systemd
- PostgreSQL client (`psql`)

## Installation

Clone the repo, or just grab the two files you need for this tool:

```bash
mkdir -p db_manager && cd $_
curl -fsSL https://raw.githubusercontent.com/denis1836/utils/master/db_manager/db_manager.sh -o db_manager.sh
curl -fsSL https://raw.githubusercontent.com/denis1836/utils/master/db_manager/db_manager.conf -o db_manager.conf
chmod +x db_manager.sh
```

Then edit `db_manager.conf` to match your project _(see [Configuration](#configuration))_, and drop your SQL files into `SQL_DIR`.

## Usage

```
./db_manager.sh [ACTION] [OPTIONS]
```

With no action, the script runs the full setup: every SQL file in `SQL_DIR`, in order.

### Service actions

| Command     | Description                                      |
| ----------- | ------------------------------------------------ |
| `--status`  | Check PostgreSQL daemon and database state       |
| `--start`   | Start the PostgreSQL service _(requires root)_   |
| `--stop`    | Stop the PostgreSQL service _(requires root)_    |
| `--restart` | Restart the PostgreSQL service _(requires root)_ |

### Database setup

| Command                   | Description                                                                                            |
| ------------------------- | ------------------------------------------------------------------------------------------------------ |
| _(no action)_             | Run every SQL file in `SQL_DIR`, followed by verification that the database and required tables exist. |
| `--drop-existing-db`      | Drop the existing database                                                                             |
| `--run --all`             | Execute all SQL files, same as the default action's execution step                                     |
| `--run --from N [--to M]` | Execute only files numbered `N` through `M`                                                            |
| `--run --to M`            | Execute files numbered `0` through `M`                                                                 |

SQL files must have a numeric prefix and match the [`SQL_PATTERN`](#configuration)
in the configuration file (e.g. `01_create_enums.sql`, `14_do_something.sql`). This is required for the script to run correctly.
\
File `00` is treated specially: it's run as the postgres superuser and skipped
automatically if the database already exists. It's reserved for the database creation file (e.g. `00_create_db.sql`).

### User management

| Command                                                 | Description                                           |
| ------------------------------------------------------- | ----------------------------------------------------- |
| `--user add -u <name> -p`                               | Create a role                                         |
| `--user remove -u <name>`                               | Drop a role                                           |
| `--user passwd -u <name> -p`                            | Change a role's password                              |
| `--user grant -u <name> --level <read\|readwrite\|all>` | Grant privileges on the configured database to a role |

### Ad-hoc queries

```bash
./db_manager.sh query "SELECT count(*) FROM users;"
./db_manager.sh query -f ./reports/monthly.sql
cat ./reports/monthly.sql | ./db_manager.sh query
```

Useful for wiring into cron jobs or other scripts _(see
[Automation & passwords](#automation--passwords))_.

### Common options

| Flag               | Description                                                             |
| ------------------ | ----------------------------------------------------------------------- |
| `-U <system-user>` | Run `psql` as this system user instead of `DB_USER` for this invocation |
| `-y`, `--yes`      | Assume "yes" for all confirmation prompts (non-interactive runs)        |
| `-h`, `--help`     | Show usage                                                              |

## Configuration

Everything project-specific is in `db_manager.conf`, sourced from the
same directory as the script. Copy it once per project and edit the values.
Do not edit `db_manager.sh` itself for project-specific needs (hardcoding is a bad habit).

| Variable                            | Description                                                               |
| ----------------------------------- | ------------------------------------------------------------------------- |
| `SERVICE_NAME`                      | Cosmetic name shown in banners/prompts                                    |
| `DB_NAME`                           | The database this script manages                                          |
| `DB_USER`                           | The default PostgreSQL/system user used to run queries                    |
| `DB_ADMIN_GROUP`                    | System group allowed to manage the database without full root             |
| `DB_HOST` / `DB_PORT`               | Used for password-authenticated connections (`--user passwd`)             |
| `SQL_DIR`                           | Directory containing your SQL files                                       |
| `SQL_PATTERN`                       | POSIX ERE regex matching SQL file names in `SQL_DIR`                      |
| `REQUIRED_TABLES`                   | Tables checked after setup to confirm it succeeded                        |
| `EXTRA_SCHEMAS`                     | Extra schemas (e.g. `cron`) granted `USAGE` on `--user grant --level all` |
| `LOG_DIR` / `LOG_FILE_NAME_PATTERN` | Where logs go and how each run's log file is named                        |
| `HELLO` / `BYE`                     | Startup/shutdown banner verbosity: `full` \| `minimal` \| `quiet`         |
| `VERBOSITY`                         | Execution log verbosity: `full` \| `minimal` \| `quiet`                   |
| `BANNER` / `BANNER_TEXT`            | Optional ASCII banner shown on startup                                    |

Colors (`HIGHLIGHT`, `WARNING`, `NOTICE`, `ERROR`) can be overridden at the
bottom of the config file if you want a different color scheme.

## Permissions model

The script never assumes you have full root. For any database action it
resolves how to reach `DB_USER` (or the user passed via `-U`), in this order:

1. You already **are** that user, runs `psql` directly.
2. You're **root**, uses `sudo -u <user>`.
3. You have a **passwordless `sudo` rule** for that specific user.
4. You're in **`DB_ADMIN_GROUP`** and have a passwordless `sudo` rule.

If none apply, it stops with an explanation instead of hanging on a password
prompt. `--start`/`--stop`/`--restart` still require actual root, since
managing a systemd service is a separate permission layer from the database
itself.

## Automation & passwords

`-p` always prompts interactively and never accepts a value inline, to avoid
passwords ending up in `ps aux` output or shell history.

For unattended runs (cron, CI, other scripts) that need to authenticate with
a password, use PostgreSQL's own [`~/.pgpass`](https://www.postgresql.org/docs/current/libpq-pgpass.html)
file instead. `psql` reads it automatically, so `query` piped through stdin
works fully non-interactively:

```bash
echo "SELECT 1;" | ./db_manager.sh -U report_bot query
```

## Logging

Every run writes a timestamped log file to `LOG_DIR` (name controlled by
`LOG_FILE_NAME_PATTERN`, using standard `date` format tokens) with ANSI
colors stripped. If the log file can't be created or written to, the script
asks whether to continue without logging.

## Troubleshooting

- **"PostgreSQL user does not exist"** - `DB_USER` in the config doesn't
  exist as a system user. Create it or point `DB_USER` at the right one.
- **"Cannot run as ... without a password prompt"** - see
  [Permissions model](#permissions-model); either run as that user directly,
  as root, or ask an admin for a `NOPASSWD` sudo rule.
- **A SQL file is silently skipped** - check if it matches `SQL_PATTERN`.

## License

[MIT](../LICENSE.md)
