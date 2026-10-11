#!/bin/bash

# zamecki.flatpak-integration uninstaller
#
# Removes Flatpak menu entries and CLI shims.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
SHIMS=(omarchy-flatpak-menu omarchy-flatpak-install omarchy-flatpak-permissions)
TAG_START='// >>> zamecki.flatpak-integration:start'
TAG_END='// <<< zamecki.flatpak-integration:end'

# --- 1. Remove Shims ---
for name in "${SHIMS[@]}"; do
  dst="$BIN_DIR/$name"
  if [[ -f $dst ]] && head -n 5 "$dst" | grep -q "zamecki.flatpak-integration"; then
    rm -f "$dst"
    echo "shim: removed $dst"
  fi
done

# --- 2. Remove Menu Entries ---
if [[ -f $MENU_FILE ]]; then
  tmp=$(mktemp "$MENU_FILE.XXXXXX")
  awk -v start="$TAG_START" -v end="$TAG_END" '
    $0 ~ start { in_block = 1; next }
    $0 ~ end { in_block = 0; next }
    in_block { next }
    { print }
  ' "$MENU_FILE" >"$tmp"
  chmod --reference="$MENU_FILE" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  mv -f "$tmp" "$MENU_FILE"
  echo "menu: removed Flatpak entries from $MENU_FILE"
fi

echo "zamecki.flatpak-integration: uninstall completed."
