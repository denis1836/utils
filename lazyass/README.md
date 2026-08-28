# lazyass

A minimal, zero-dependency CLI script to launch groups of applications at once

## Installation
```bash
curl -fsSL https://raw.githubusercontent.com/denis1836/utils/main/lazyass/lazyass.sh -o lazyass.sh
chmod +x lazyass.sh
./lazyass.sh --help
```

To make it globally executable for your user:

```bash
mkdir -p ~/.local/bin
mv ./lazyass.sh ~/.local/bin/lazyass
```
Or to make it executable globally for all users:

```bash
sudo mv ./lazyass.sh /usr/local/bin/lazyass
sudo chmod +x /usr/local/bin/lazyass
```

## Usage

### Launching
```bash
# launch default profile
lazyass

# launch a specific profile
lazyass <profile name>
```

### Defualt profile managment
```bash
# add one or more apps
lazyass app add firefox "dolphin ~" konsole "~/path/to/bin"

# remove an app
lazyass app remove konsole

# list default profile
lazyass app list

# edit defualt file 
lazyass app edit
```

### Profile Managment
```bash
# create a profile with optional initial apps
lazyass profile create work slack obsidian thunderbird

# add apps to an existing profile
lazyass profile add work docker-desktop

# list all saved profiles
lazyass profile list

# edit a profile file directly
lazyass profile edit work

# delete a profile
lazyass profile remove work
```

### Configuration layout
```
~/.config/lazyass/
├── default
└── profiles/
    ├── dev
    └── work
```

Profile files use simple newline-separated binary names or executable paths:
```bash
# ~/.config/lazyass/profiles/dev
# Supports comments too!
code
spotify
# firefox
~/path/to/my/bin
dolphin ~/my/dir
```

## License
[MIT](../LICENSE.md)