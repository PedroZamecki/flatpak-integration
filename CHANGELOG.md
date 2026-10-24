# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-10-24

### Added

- Automatic Apps-menu integration: installed Flatpaks are linked into
  `~/.local/share/applications` and `~/.local/share/icons/flatpak`, so they
  appear in the Omarchy Apps menu with icons. Links are created on install,
  refreshed by the shell service every 30 seconds, and pruned on removal.
- `omarchy-flatpak-setup desktop` and `Setup > Flatpaks > Refresh App Menu`.
- Dependency checks for Flatpak, Bubblewrap, fzf, Python, jq, and the Omarchy
  helpers, with an `install-deps` command and `--no-install` escape hatch.
- Flathub remote setup and repair, including AppStream refresh and a cached
  application catalog for the installer.
- Installation scope detection (`auto`, `user`, `system`) and configuration.
- Flatseal-like permission manager writing per-user overrides.
- Topbar update indicator and `omarchy update` hook.

### Changed

- The plugin id is now `flatpak-integration` (previously
  `zamecki.flatpak-integration`). The installer migrates old menu entries, bar
  widgets, and command shims automatically.
- Permissions and updates cover both per-user and system-wide installations.

### Fixed

- A fresh Flatpak installation no longer shows an empty application list.
- Manually installed Flatpaks appear in the Apps menu without logging out, even
  when the shell started before Flatpak was installed.

## [1.1.0] - 2026-10-14

### Added

- Topbar update indicator for pending Flatpak updates.
- `omarchy update` hook that updates Flatpaks and refreshes the indicator.

### Fixed

- Duplicate close prompt in the update flow.

## [1.0.0] - 2026-10-11

### Added

- Initial release: Flathub search and install menu.
