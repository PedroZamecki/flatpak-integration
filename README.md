# flatpak-integration

Native Flatpak integration, Flathub setup, Flatseal-like permission management,
and a topbar update indicator for **Omarchy**.

## Features

- **Dependency-aware setup**
  Checks Flatpak, Bubblewrap, fzf, Python, jq, and the Omarchy menu helpers
  before enabling anything. Missing Arch packages can be installed from the
  setup screen.
- **Flathub first-run fix**
  A fresh Flatpak installation has no remote and no AppStream data, which makes
  application search return nothing. The setup flow adds/enables Flathub,
  refreshes metadata, and rebuilds the application catalog.
- **Per-user or system-wide**
  Works with whichever installation already has Flathub, and can be pinned to
  per-user (no administrator password) or system-wide in the settings screen.
- **Native Install Menu (`Install > Flatpak`)**
  Fuzzy search with live previews and multi-select. Already-installed
  applications are marked with `✓`.
- **Flatpak Management (`Setup > Flatpaks`)**
  Setup & Check, Settings, Refresh App Catalog, Manage Permissions, Install,
  Remove, Update, and Reset Permissions.
- **Flatseal-like Permission Manager**
  Inspects the application metadata plus user/system overrides, and toggles
  sandbox permissions (Network, Filesystem, Audio, Sockets, Devices, IPC)
  directly in Omarchy's native menu. Overrides are written per-user, so they
  work for system-wide apps without sudo.
- **Topbar Update Indicator**
  Shows the number of pending updates across per-user and system installations,
  launches updates in a presentation terminal, and refreshes when finished.
- **Omarchy update hook**
  Updates Flatpaks during `omarchy update` and keeps the indicator in sync.

## Dependencies

| Command | Arch package | Needed for |
| --- | --- | --- |
| `flatpak` | `flatpak` | everything |
| `bwrap` | `bubblewrap` | running sandboxed apps |
| `fzf` | `fzf` | install menu |
| `python3` | `python` | permission manager |
| `jq` | `jq` | bar widget / shell.json |
| `gum` | `gum` | setup prompts (optional) |

The Omarchy helpers (`omarchy-menu-select`, `omarchy-notification-send`,
`omarchy-launch-floating-terminal-with-presentation`) ship with Omarchy.

## Installation

```bash
# From the repository root
./install.sh

# Or through Omarchy
omarchy plugin add https://github.com/PedroZamecki/zamecki.flatpak-integration --enable
omarchy plugin enable flatpak-integration
```

Then open:

```text
Setup > Flatpaks > Setup & Check
```

or run:

```bash
omarchy-flatpak-setup setup
```

The installer is idempotent. It also migrates the old
`zamecki.flatpak-integration` menu entries, bar widget, and shims.

## Configuration

Settings live in:

```text
~/.config/omarchy/flatpak-integration/config
```

```bash
FP_SCOPE="auto"        # auto | user | system
FP_REMOTE="flathub"
FP_REMOTE_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FP_CACHE_MAX_AGE=86400 # seconds
```

`auto` keeps an existing setup working: it prefers a per-user remote, then a
system remote, and creates a per-user setup only when neither exists.

Change it interactively:

```bash
omarchy-flatpak-setup configure
```

Or non-interactively:

```bash
omarchy-flatpak-setup configure --scope=user
omarchy-flatpak-setup configure --scope=system
```

## Commands

```bash
omarchy-flatpak-setup check        # dependency/remote/catalog report
omarchy-flatpak-setup setup        # install deps + configure Flathub
omarchy-flatpak-setup configure    # choose scope
omarchy-flatpak-setup repair       # re-add/enable Flathub + refresh lists
omarchy-flatpak-setup status       # JSON status
omarchy-flatpak-install --refresh  # rebuild catalog and open the installer
omarchy-flatpak-update             # update both installations
omarchy-flatpak-update-available   # pending update count
omarchy-flatpak-menu <action>      # menu dispatcher
```

## Troubleshooting

**The install list is empty**

Run `omarchy-flatpak-setup check`. The most common cause on a fresh Flatpak
install is that the Flathub remote exists only in one installation while the
plugin was looking in the other. Version 2 detects the scope automatically.
`omarchy-flatpak-setup repair` re-adds/enables Flathub and rebuilds the list.

**`flatpak: command not found`**

Open `Setup > Flatpaks > Setup & Check`, or install the Arch package:

```bash
omarchy pkg add flatpak
```

**Permission toggles do not apply to a system app**

Overrides are intentionally written per-user (`flatpak override --user`). They
apply to system-wide applications too and do not require administrator access.

**The bar widget is missing**

Make sure `flatpak-integration` is present in `~/.config/omarchy/shell.json`
under `bar.layout.center`, then reload:

```bash
omarchy-shell shell reloadConfig
```

## Structure

```text
├── manifest.json                        # Omarchy plugin contract
├── Service.qml                          # Headless Quickshell service
├── BarWidget.qml                        # Topbar update indicator
├── install.sh                           # Idempotent, migration-aware installer
├── uninstall.sh                         # Cleanup uninstaller
├── bin/
│   ├── lib/flatpak-common.sh            # Shared dependency/scope/catalog logic
│   ├── omarchy-flatpak-setup            # Check, setup, configure, repair
│   ├── omarchy-flatpak-menu             # Menu action dispatcher
│   ├── omarchy-flatpak-install          # Flathub search & install fuzzy-finder
│   ├── omarchy-flatpak-update           # Updater for both installations
│   ├── omarchy-flatpak-update-available # Update availability checker
│   └── omarchy-flatpak-permissions      # Permission inspection & override engine
├── hooks/
│   └── flatpak-update.hook              # Omarchy post-update hook
└── extras/
    └── omarchy-menu.jsonc               # Standalone menu template
```
