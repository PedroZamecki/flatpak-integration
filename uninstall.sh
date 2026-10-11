#!/bin/bash

# zamecki.flatpak-integration uninstaller
#
# Removes Flatpak menu entries, post-update hook, bar widget, and CLI shims.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
HOOK_FILE="$HOME/.config/omarchy/hooks/post-update.d/flatpak-update.hook"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
SHIMS=(omarchy-flatpak-menu omarchy-flatpak-install omarchy-flatpak-permissions omarchy-flatpak-update-available)
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

# --- 2. Remove Post-update Hook ---
if [[ -f $HOOK_FILE ]]; then
  rm -f "$HOOK_FILE"
  echo "hook: removed $HOOK_FILE"
fi

# --- 3. Remove Menu Entries ---
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

# --- 4. Remove Bar Widget from shell.json ---
if [[ -f $SHELL_CONFIG ]]; then
  python3 - <<PY
import json

path = "$SHELL_CONFIG"
try:
    with open(path, "r") as f:
        data = json.load(f)
    center = data.get("bar", {}).get("layout", {}).get("center", [])
    filtered = [x for x in center if not (isinstance(x, dict) and x.get("id") == "zamecki.flatpak-integration")]
    if len(filtered) != len(center):
        data["bar"]["layout"]["center"] = filtered
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        print("bar: removed zamecki.flatpak-integration from center section")
except Exception as e:
    print(f"bar: warning - {e}")
PY
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell reloadConfig 2>/dev/null || true
  fi
fi

echo "zamecki.flatpak-integration: uninstall completed."
