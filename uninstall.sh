#!/bin/bash

# flatpak-integration uninstaller
#
# Removes shims, the post-update hook, menu entries, and the bar widget.
# User settings in ~/.config/omarchy/flatpak-integration are kept.

set -uo pipefail

PLUGIN_ID="flatpak-integration"
OLD_PLUGIN_ID="zamecki.flatpak-integration"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
HOOK_FILE="$HOME/.config/omarchy/hooks/post-update.d/flatpak-update.hook"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
SHIMS=(omarchy-flatpak-menu omarchy-flatpak-install omarchy-flatpak-permissions omarchy-flatpak-update omarchy-flatpak-update-available omarchy-flatpak-setup)
TAG_START="// >>> $PLUGIN_ID:start"
TAG_END="// <<< $PLUGIN_ID:end"
OLD_TAG_START="// >>> $OLD_PLUGIN_ID:start"
OLD_TAG_END="// <<< $OLD_PLUGIN_ID:end"

have() { command -v "$1" >/dev/null 2>&1; }

# shellcheck source=bin/lib/flatpak-common.sh
if [[ -f $PLUGIN_DIR/bin/lib/flatpak-common.sh ]]; then
  source "$PLUGIN_DIR/bin/lib/flatpak-common.sh"
fi

# --- 1. Remove shims -------------------------------------------------------
for name in "${SHIMS[@]}"; do
  dst="$BIN_DIR/$name"
  if [[ -f $dst ]] && head -n 5 "$dst" | grep -Eq "(zamecki\.)?flatpak-integration shim"; then
    rm -f "$dst"
    echo "shim: removed $dst"
  fi
done

# --- 2. Remove post-update hook -------------------------------------------
if [[ -f $HOOK_FILE ]] && grep -qi "flatpak" "$HOOK_FILE"; then
  rm -f "$HOOK_FILE"
  echo "hook: removed $HOOK_FILE"
fi

# --- 3. Remove menu entries (current and legacy blocks) --------------------
if [[ -f $MENU_FILE ]]; then
  tmp=$(mktemp "$MENU_FILE.XXXXXX") || exit 1
  awk -v s_new="$TAG_START" -v e_new="$TAG_END" \
      -v s_old="$OLD_TAG_START" -v e_old="$OLD_TAG_END" '
    index($0, s_new) { skip = 1; next }
    index($0, e_new) { skip = 0; next }
    index($0, s_old) { skip = 1; next }
    index($0, e_old) { skip = 0; next }
    skip { next }
    { print }
  ' "$MENU_FILE" >"$tmp"
  chmod --reference="$MENU_FILE" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  mv -f "$tmp" "$MENU_FILE"
  echo "menu: removed Flatpak entries from $MENU_FILE"
fi

# --- 4. Remove bar widget (current and legacy id) --------------------------
if [[ -f $SHELL_CONFIG ]] && have jq; then
  tmp=$(mktemp "$SHELL_CONFIG.XXXXXX") || exit 1
  if jq --arg new "$PLUGIN_ID" --arg old "$OLD_PLUGIN_ID" '
      if (.bar | type) == "object" then
        .bar.layout = (.bar.layout // {})
        | .bar.layout |= with_entries(
          if (.value | type) == "array" then
            .value |= map(
              select((type != "object") or ((.id? != $new) and (.id? != $old)))
            )
          else . end
        )
      else . end
    ' "$SHELL_CONFIG" >"$tmp"; then
    chmod --reference="$SHELL_CONFIG" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
    mv -f "$tmp" "$SHELL_CONFIG"
    echo "bar: removed $PLUGIN_ID from shell.json"
  else
    rm -f "$tmp"
    echo "bar: warning - could not update shell.json" >&2
  fi
elif [[ -f $SHELL_CONFIG ]]; then
  echo "bar: jq is missing; remove the $PLUGIN_ID entry from $SHELL_CONFIG manually" >&2
fi

# --- 5. Remove app menu bridge links ---------------------------------------
if declare -F fp_remove_desktop_bridge >/dev/null 2>&1; then
  removed=$(fp_remove_desktop_bridge)
  [[ -n $removed ]] && echo "app menu: removed $removed Flatpak entry links"
fi

if have omarchy-shell; then
  omarchy-shell -q shell reloadConfig >/dev/null 2>&1 || true
fi

echo "$PLUGIN_ID: uninstall completed. Your Flatpak applications and settings were not touched."
