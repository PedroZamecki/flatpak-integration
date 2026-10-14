# zamecki.flatpak-integration

Native Flatpak integration and Flatseal-like permission manager for **Omarchy**.

## Features

- **Native Install Menu (`Install > Flatpak`):**
  Adds a Flatpak entry directly to Omarchy's `Install` menu, allowing fuzzy search and installation of Flathub applications using an interactive `fzf` TUI with live previews and multi-select.
- **Flatpak Management (`Setup > Flatpaks`):**
  Accessible directly from the root menu (`Setup > Flatpaks`) and searchable via `flatpak`, `flatpaks`, or `flatseal`. Mirrors the native `Setup > Plugins` design.
- **Flatseal-like Permission Manager:**
  Inspects and toggles Flatpak sandbox permissions (Network, Filesystem, Audio, Sockets, Devices, IPC) per application directly within Omarchy's native `omarchy-menu-select` interface, with zero extra window baggage.
- **Topbar Update Indicator & One-Click Updates:**
  Status bar widget that automatically detects pending Flatpak updates, shows the count, and launches update in a presentation window, automatically syncing and clearing the indicator upon completion.
- **Application Removal & Updates:**
  Clean uninstallation of Flatpak applications with confirmation, and one-click system-wide Flatpak updates.
- **Override Reset:**
  Instantly restore default permissions per application or globally.

## Installation

```bash
# Clone the repository
git clone file:///home/zamecki/Projects/zamecki.flatpak-integration ~/.config/omarchy/plugins/zamecki.flatpak-integration

# Rescan and enable plugin
omarchy-shell shell rescanPlugins
omarchy plugin enable zamecki.flatpak-integration
```

Or run the installer directly:

```bash
./install.sh
```

## Structure

```
├── manifest.json                  # Omarchy plugin contract (schemaVersion 1, service & bar-widget)
├── Service.qml                    # Headless Quickshell service
├── BarWidget.qml                  # Topbar Flatpak update indicator widget
├── install.sh                     # Idempotent menu, hook, & shim installer
├── uninstall.sh                   # Cleanup uninstaller
├── bin/
│   ├── omarchy-flatpak-menu       # Menu action dispatcher
│   ├── omarchy-flatpak-install    # Flathub search & install fuzzy-finder
│   ├── omarchy-flatpak-update     # Flatpak updater with shell status sync
│   ├── omarchy-flatpak-update-available # Update availability checker
│   └── omarchy-flatpak-permissions# Permission inspection & override engine
├── hooks/
│   └── flatpak-update.hook        # Omarchy post-update hook for system updates
└── extras/
    └── omarchy-menu.jsonc         # Standalone menu template
```
