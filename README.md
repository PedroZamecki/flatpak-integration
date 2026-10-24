# flatpak-integration

[![CI](https://github.com/PedroZamecki/flatpak-integration/actions/workflows/ci.yml/badge.svg)](https://github.com/PedroZamecki/flatpak-integration/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

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
  Setup & Check, Settings, Refresh App Catalog, Refresh App Menu, Manage
  Permissions, Install, Remove, Update, and Reset Permissions.
- **Automatic Apps-menu integration**
  Flatpak exports its desktop entries outside the directories a running Omarchy
  shell scans, so apps installed with `flatpak install` would otherwise stay
  invisible until you log out. The plugin links them (and their icons) into
  `~/.local/share/applications` and `~/.local/share/icons/flatpak`, and re-checks
  every 30 seconds, so manually installed apps appear on their own.
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
omarchy plugin add https://github.com/PedroZamecki/flatpak-integration --enable
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

## Uninstall

```bash
./uninstall.sh
# or
omarchy plugin remove flatpak-integration
```

The uninstaller removes the command shims, menu entries, post-update hook, bar
widget, and the Apps-menu links it created. Your Flatpak applications, their
permissions, and the plugin config are kept.

## Privileges and side effects

Omarchy plugins run unsandboxed inside the long-running shell process with your
user permissions. This plugin keeps privilege use to a minimum:

- **Writes only inside your home directory**
  - `~/.local/bin/omarchy-flatpak-*` command shims
  - `~/.config/omarchy/extensions/omarchy-menu.jsonc`
  - `~/.config/omarchy/hooks/post-update.d/flatpak-update.hook`
  - `~/.config/omarchy/shell.json` (bar layout entry)
  - `~/.config/omarchy/flatpak-integration/config`
  - `~/.cache/omarchy/flatpak-integration-apps.cache`
  - `~/.cache/omarchy/flatpak-integration-desktop-bridge.stamp`
  - `~/.local/share/applications/*.desktop` symlinks and
    `~/.local/share/icons/flatpak/` symlinks for the Apps menu (removed by the
    uninstaller; files that are not Flatpak exports are never touched)
- **No administrator access by default.** The default `auto` scope prefers the
  per-user Flatpak installation, and permission overrides are written per-user
  (`flatpak override --user`), so normal use never asks for sudo.
- **Optional package installation.** `omarchy-flatpak-setup setup` and
  `install-deps` install missing Arch packages (`flatpak`, `bubblewrap`, `fzf`,
  `python`, `jq`) through `omarchy-pkg-add`/`pacman`, which prompts for sudo.
  Pass `--no-install` to skip this.
- **Optional system-wide operations.** Choosing `--scope=system`, or having
  Flathub only in the system installation, makes `flatpak remote-add`,
  `flatpak update --appstream`, and `flatpak update --system` request
  administrator access.
- **Network access.** Setup and refresh contact the configured remote
  (`dl.flathub.org` by default) to download AppStream metadata and the
  application catalog.
- **No second shell process.** The plugin is a Quickshell service and bar
  widget inside the existing Omarchy shell; external commands run only when you
  trigger an action.

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
omarchy-flatpak-setup desktop      # link Flatpak apps into the Apps menu
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
plugin was looking in the other. The plugin detects the scope automatically.
`omarchy-flatpak-setup repair` re-adds/enables Flathub and rebuilds the list.

**A Flatpak app does not appear in the Apps menu**

The plugin links new apps automatically within 30 seconds. To force it, run
`omarchy-flatpak-setup desktop` or use `Setup > Flatpaks > Refresh App Menu`.
If the app is still missing, check that it exports a desktop entry:

```bash
ls ~/.local/share/flatpak/exports/share/applications/
```

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
│   ├── lib/flatpak-common.sh            # Shared dependency/scope/catalog/bridge logic
│   ├── omarchy-flatpak-setup            # Check, setup, configure, repair, desktop
│   ├── omarchy-flatpak-menu             # Menu action dispatcher
│   ├── omarchy-flatpak-install          # Flathub search & install fuzzy-finder
│   ├── omarchy-flatpak-update           # Updater for both installations
│   ├── omarchy-flatpak-update-available # Update availability checker
│   └── omarchy-flatpak-permissions      # Permission inspection & override engine
├── hooks/
│   └── flatpak-update.hook              # Omarchy post-update hook
├── extras/
│   └── omarchy-menu.jsonc               # Standalone menu template
└── .github/workflows/ci.yml             # Syntax, manifest, and ShellCheck CI
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © Pedro Zamecki Andrade
