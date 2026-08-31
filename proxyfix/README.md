# proxyfix

A simple Bash script for managing `proxychains` proxy lists and profiles.

## Prerequisites

- `proxychains` (or `proxychains-ng`)
- Root privileges (`sudo`)

## Configuration

Create a configuration file at `~/.config/proxyfix/proxyfix.conf`:

```bash
mkdir -p ~/.config/proxyfix
cat << 'EOF' > ~/.config/proxyfix/proxyfix.conf
PROXYCHAINS_CONF_FILE="/etc/proxychains4.conf"
DEFAULT_PROFILE_DIR="${HOME}/.config/proxyfix/profiles"
DEFAULT_PROFILE_EDITOR="nano"
DEFAULT_PROFILE_VIEWER="less"
EOF

```

## Usage

```bash
sudo ./proxyfix.sh <command>
```

### Proxy Management

| Command | Description |
| --- | --- |
| `list` | Display active proxy servers in a formatted table |
| `edit` | Open the full `proxychains` config file in your default editor |
| `edit-list --line "socks5 127.0.0.1 9050"` | Replace current proxy list with specified proxy |
| `edit-list-add --line "http 10.0.0.1 8080"` | Append proxy to current list |
| `clear` | Clear all proxy entries from the config file |

### Profiles

Profiles allow you to quickly switch between different proxy configurations.

```bash
# Save active proxies to a profile named 'work'
sudo ./proxyfix.sh profile save work

# List available profiles
sudo ./proxyfix.sh profile list

# Apply the 'work' profile to proxychains
sudo ./proxyfix.sh profile apply work

# View / Edit / Remove profiles
sudo ./proxyfix.sh profile view work
sudo ./proxyfix.sh profile edit work
sudo ./proxyfix.sh profile remove work

```

Available profile subcommands: `save`, `apply`, `edit`, `remove`, `list`, `view`.

## License

[MIT](https://github.com/denis1836/utils/blob/main/LICENSE.md)
