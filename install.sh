#!/bin/bash

# zamecki.flatpak-integration installer
#
# Adds:
# 1. Flatpak entries to Omarchy Menu (Install -> Flatpak, Setup -> Flatpaks)
# 2. Post-update hook in ~/.config/omarchy/hooks/post-update.d/ to update Flatpaks during `omarchy update`
# 3. BarWidget in ~/.config/omarchy/shell.json (center section beside clock/system-update)
# 4. CLI shims in ~/.local/bin
#
# Idempotent: safe to run multiple times.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
HOOKS_DIR="$HOME/.config/omarchy/hooks/post-update.d"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
SHIMS=(omarchy-flatpak-menu omarchy-flatpak-install omarchy-flatpak-permissions omarchy-flatpak-update-available omarchy-flatpak-update)
MARKER='# zamecki.flatpak-integration shim'
TAG_START='// >>> zamecki.flatpak-integration:start'
TAG_END='// <<< zamecki.flatpak-integration:end'

mkdir -p "$BIN_DIR" "$(dirname "$MENU_FILE")" "$HOOKS_DIR"

# --- 1. Shims in ~/.local/bin ------------------------------------------------
for name in "${SHIMS[@]}"; do
  dst="$BIN_DIR/$name"
  tmp=$(mktemp "$dst.XXXXXX")
  cat >"$tmp" <<SHIM
#!/bin/bash
$MARKER
# Forward to plugin source directory
exec bash "$PLUGIN_DIR/bin/$name" "\$@"
SHIM
  chmod 0755 "$tmp"
  mv -f "$tmp" "$dst"
  echo "shim: installed $dst"
done

# --- 2. Post-update hook for `omarchy update` -------------------------------
HOOK_DST="$HOOKS_DIR/flatpak-update.hook"
cp -f "$PLUGIN_DIR/hooks/flatpak-update.hook" "$HOOK_DST"
chmod 0755 "$HOOK_DST"
echo "hook: installed $HOOK_DST"

# --- 3. Menu extension in ~/.config/omarchy/extensions/omarchy-menu.jsonc ---
menu=$(realpath "$MENU_FILE" 2>/dev/null || echo "$MENU_FILE")
[[ -f $menu ]] || printf '{\n}\n' >"$menu"

MENU_BLOCK=$(cat <<'EOF'
  // >>> zamecki.flatpak-integration:start
  "install.flatpak": {"icon":"󰏓","label":"Flatpak","when":"omarchy-cmd-present flatpak","description":"Search and install Flatpaks from Flathub","action":"xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-flatpak-install"},
  "setup.flatpak": {"icon":"󰏓","label":"Flatpaks","when":"omarchy-cmd-present flatpak","aliases":["flatpak","flatpaks","flatseal"]},
  "setup.flatpak.permissions": {"icon":"󰌾","label":"Manage Permissions","when":"omarchy-cmd-present flatpak","description":"Configure sandbox permissions for Flatpaks","action":"omarchy-flatpak-menu permissions"},
  "setup.flatpak.install": {"icon":"󰉉","label":"Install Application","when":"omarchy-cmd-present flatpak","description":"Search and install new Flatpaks from Flathub","action":"omarchy-flatpak-menu install"},
  "setup.flatpak.remove": {"icon":"󰭌","label":"Remove Application","when":"omarchy-cmd-present flatpak","description":"Uninstall an installed Flatpak","action":"omarchy-flatpak-menu remove"},
  "setup.flatpak.update": {"icon":"","label":"Update Applications","when":"omarchy-cmd-present flatpak","description":"Update installed Flatpaks","action":"omarchy-flatpak-menu update"},
  "setup.flatpak.reset": {"icon":"","label":"Reset Permissions","when":"omarchy-cmd-present flatpak","description":"Reset permissions to defaults","action":"omarchy-flatpak-menu reset"},
  // <<< zamecki.flatpak-integration:end
EOF
)

tmp=$(mktemp "$menu.XXXXXX")
awk -v block="$MENU_BLOCK" -v start="$TAG_START" -v end="$TAG_END" '
  $0 ~ start { in_block = 1; next }
  $0 ~ end { in_block = 0; next }
  in_block { next }
  !done && /^[[:space:]]*\{/ {
    print
    print block
    done = 1
    next
  }
  { print }
' "$menu" >"$tmp"

chmod --reference="$menu" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
mv -f "$tmp" "$menu"
echo "menu: updated $MENU_FILE with Flatpak integration"

# --- 4. Bar widget in ~/.config/omarchy/shell.json (center section) ----------
if [[ -f $SHELL_CONFIG ]]; then
  python3 - <<PY
import json

path = "$SHELL_CONFIG"
try:
    with open(path, "r") as f:
        data = json.load(f)
    center = data.get("bar", {}).get("layout", {}).get("center", [])
    ids = [x.get("id") for x in center if isinstance(x, dict)]
    if "zamecki.flatpak-integration" not in ids:
        pos = ids.index("omarchy.system-update") + 1 if "omarchy.system-update" in ids else len(center)
        center.insert(pos, {"id": "zamecki.flatpak-integration"})
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        print("bar: added zamecki.flatpak-integration to center section in shell.json")
    else:
        print("bar: zamecki.flatpak-integration already present in center section")
except Exception as e:
    print(f"bar: warning - could not update shell.json: {e}")
PY
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell reloadConfig 2>/dev/null || true
  fi
fi

echo "zamecki.flatpak-integration: installation completed successfully."
