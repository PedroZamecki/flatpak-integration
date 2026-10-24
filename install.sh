#!/bin/bash

# flatpak-integration installer
#
# Wires the plugin into Omarchy:
#   1. CLI shims in ~/.local/bin
#   2. Post-update hook for `omarchy update`
#   3. Menu entries (Install > Flatpak, Setup > Flatpaks)
#   4. Topbar update widget in ~/.config/omarchy/shell.json
#   5. A dependency/remote check so a fresh Flatpak install works
#
# Idempotent and migration-aware: it replaces the old
# zamecki.flatpak-integration entries left by earlier versions.

set -uo pipefail

PLUGIN_ID="flatpak-integration"
OLD_PLUGIN_ID="zamecki.flatpak-integration"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
HOOKS_DIR="$HOME/.config/omarchy/hooks/post-update.d"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
SHIMS=(omarchy-flatpak-menu omarchy-flatpak-install omarchy-flatpak-permissions omarchy-flatpak-update omarchy-flatpak-update-available omarchy-flatpak-setup)
MARKER="# $PLUGIN_ID shim"
TAG_START="// >>> $PLUGIN_ID:start"
TAG_END="// <<< $PLUGIN_ID:end"
OLD_TAG_START="// >>> $OLD_PLUGIN_ID:start"
OLD_TAG_END="// <<< $OLD_PLUGIN_ID:end"

# shellcheck source=bin/lib/flatpak-common.sh
source "$PLUGIN_DIR/bin/lib/flatpak-common.sh"

QUIET=0
RUN_SETUP=1
while (( $# > 0 )); do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    --no-setup) RUN_SETUP=0 ;;
    -h|--help)
      echo "Usage: install.sh [--quiet] [--no-setup]"
      exit 0
      ;;
    *) echo "install.sh: unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { (( QUIET )) || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

mkdir -p "$BIN_DIR" "$(dirname "$MENU_FILE")" "$HOOKS_DIR"

OLD_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$OLD_PLUGIN_ID"
if [[ -d $OLD_PLUGIN_DIR && $OLD_PLUGIN_DIR != "$PLUGIN_DIR" ]]; then
  warn "flatpak-integration: an old copy is still installed at:"
  warn "  $OLD_PLUGIN_DIR"
  warn "Remove it to avoid duplicate menu entries: omarchy plugin remove $OLD_PLUGIN_ID"
fi

# --- 0. Preflight ----------------------------------------------------------
# Never abort the install because the system is not ready yet: the menu's
# "Setup & Check" entry must remain reachable so the user can fix it there.
if (( ! QUIET )); then
  fp_print_check || true
  echo
fi

# --- 1. Shims in ~/.local/bin ---------------------------------------------
# Exec the real script directly so the shebang decides the interpreter
# (important for the Python permission helper). Fix modes for zip downloads
# that lose the executable bit.
chmod 0755 "$PLUGIN_DIR"/bin/omarchy-flatpak-* 2>/dev/null || true

for name in "${SHIMS[@]}"; do
  dst="$BIN_DIR/$name"
  tmp=$(mktemp "$dst.XXXXXX") || continue
  cat >"$tmp" <<SHIM
#!/bin/bash
$MARKER
exec "$PLUGIN_DIR/bin/$name" "\$@"
SHIM
  chmod 0755 "$tmp"
  mv -f "$tmp" "$dst"
  say "shim: installed $dst"
done

# --- 2. Post-update hook for `omarchy update` ------------------------------
HOOK_DST="$HOOKS_DIR/flatpak-update.hook"
cp -f "$PLUGIN_DIR/hooks/flatpak-update.hook" "$HOOK_DST"
chmod 0755 "$HOOK_DST"
say "hook: installed $HOOK_DST"

# --- 3. Menu extension in ~/.config/omarchy/extensions/omarchy-menu.jsonc ---
menu=$(realpath "$MENU_FILE" 2>/dev/null || echo "$MENU_FILE")
[[ -f $menu ]] || printf '{\n}\n' >"$menu"

MENU_BLOCK=$(cat <<'EOF'
  // >>> flatpak-integration:start
  "install.flatpak": {"icon":"󰏓","label":"Flatpak","description":"Search and install Flatpaks from Flathub","action":"omarchy-flatpak-menu install"},
  "setup.flatpak": {"icon":"󰏓","label":"Flatpaks","aliases":["flatpak","flatpaks","flatseal"]},
  "setup.flatpak.setup": {"icon":"󰒓","label":"Setup & Check","description":"Install dependencies, configure Flathub, refresh lists","action":"omarchy-flatpak-menu setup"},
  "setup.flatpak.configure": {"icon":"󰒓","label":"Settings","description":"Choose per-user or system-wide installation","action":"omarchy-flatpak-menu configure"},
  "setup.flatpak.refresh": {"icon":"󰑐","label":"Refresh App Catalog","when":"omarchy-cmd-present flatpak","description":"Update the Flathub application list","action":"omarchy-flatpak-menu refresh"},
  "setup.flatpak.desktop": {"icon":"󰀻","label":"Refresh App Menu","when":"omarchy-cmd-present flatpak","description":"Link newly installed Flatpaks into the app menu","action":"omarchy-flatpak-menu desktop"},
  "setup.flatpak.permissions": {"icon":"󰌾","label":"Manage Permissions","when":"omarchy-cmd-present flatpak","description":"Configure sandbox permissions for Flatpaks","action":"omarchy-flatpak-menu permissions"},
  "setup.flatpak.install": {"icon":"󰉉","label":"Install Application","when":"omarchy-cmd-present flatpak","description":"Search and install new Flatpaks from Flathub","action":"omarchy-flatpak-menu install"},
  "setup.flatpak.remove": {"icon":"󰭌","label":"Remove Application","when":"omarchy-cmd-present flatpak","description":"Uninstall an installed Flatpak","action":"omarchy-flatpak-menu remove"},
  "setup.flatpak.update": {"icon":"","label":"Update Applications","when":"omarchy-cmd-present flatpak","description":"Update installed Flatpaks","action":"omarchy-flatpak-menu update"},
  "setup.flatpak.reset": {"icon":"","label":"Reset Permissions","when":"omarchy-cmd-present flatpak","description":"Reset user permission overrides to defaults","action":"omarchy-flatpak-menu reset"},
  // <<< flatpak-integration:end
EOF
)

tmp=$(mktemp "$menu.XXXXXX") || exit 1
awk -v block="$MENU_BLOCK" \
    -v s_new="$TAG_START" -v e_new="$TAG_END" \
    -v s_old="$OLD_TAG_START" -v e_old="$OLD_TAG_END" '
  index($0, s_new) { skip = 1; next }
  index($0, e_new) { skip = 0; next }
  index($0, s_old) { skip = 1; next }
  index($0, e_old) { skip = 0; next }
  skip { next }
  !done && /^[[:space:]]*\{/ {
    print
    print block
    done = 1
    next
  }
  { print }
' "$menu" >"$tmp"

if [[ -s $tmp ]] && grep -q . "$tmp"; then
  chmod --reference="$menu" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  mv -f "$tmp" "$menu"
  say "menu: updated $MENU_FILE"
else
  rm -f "$tmp"
  warn "menu: could not update $MENU_FILE"
fi

# --- 4. Bar widget in ~/.config/omarchy/shell.json -------------------------
if [[ -f $SHELL_CONFIG ]] && fp_have jq; then
  tmp=$(mktemp "$SHELL_CONFIG.XXXXXX") || exit 1
  if jq --arg old "$OLD_PLUGIN_ID" --arg new "$PLUGIN_ID" '
      if (.bar | type) == "object" then
        .bar.layout = (.bar.layout // {})
        | .bar.layout |= with_entries(
            if (.value | type) == "array" then
              .value |= map(
                if (type == "object") and (.id? == $old) then .id = $new else . end
              )
            else . end
          )
        | .bar.layout.center = (
            (.bar.layout.center // []) as $center
            | ($center | map(if type == "object" then .id? else empty end) | index($new)) as $present
            | if $present != null then $center
              else
                (($center | map(if type == "object" then .id? else empty end) | index("omarchy.system-update")) as $i
                 | if $i == null then $center + [{"id": $new}]
                   else $center[0:($i + 1)] + [{"id": $new}] + $center[($i + 1):]
                   end)
              end
          )
      else . end
    ' "$SHELL_CONFIG" >"$tmp"; then
    chmod --reference="$SHELL_CONFIG" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
    mv -f "$tmp" "$SHELL_CONFIG"
    say "bar: $PLUGIN_ID is in the center section of shell.json"
  else
    rm -f "$tmp"
    warn "bar: warning - could not update shell.json"
  fi
elif [[ -f $SHELL_CONFIG ]]; then
  warn "bar: jq is missing; edit $SHELL_CONFIG manually to add {\"id\": \"$PLUGIN_ID\"}"
fi

# --- 5. Make a fresh Flatpak installation usable ---------------------------
if fp_have flatpak; then
  if (( RUN_SETUP )); then
    "$PLUGIN_DIR/bin/omarchy-flatpak-setup" repair --stale-only --quiet || true
  fi

  # Always keep the app menu in sync. A session that started before Flatpak
  # was installed never received Flatpak's XDG_DATA_DIRS paths, so linking the
  # exports into ~/.local/share/applications is what makes new apps show up in
  # the Omarchy Apps menu without a logout.
  fp_sync_desktop_bridge_if_needed || true
  if (( ! QUIET )); then
    bridge_count=$(fp_desktop_bridge_count)
    if (( ${FP_DESKTOP_BRIDGE_CREATED:-0} > 0 )); then
      say "app menu: linked ${FP_DESKTOP_BRIDGE_CREATED} Flatpak entries"
    elif (( bridge_count > 0 )); then
      say "app menu: ${bridge_count} Flatpak entries available"
    fi
  fi
elif (( RUN_SETUP )); then
  (( QUIET )) || warn "flatpak: not installed yet. Open Setup > Flatpaks > Setup & Check after installing it."
fi

if fp_have omarchy-shell; then
  omarchy-shell -q shell reloadConfig >/dev/null 2>&1 || true
fi

# --- 6. Summary ------------------------------------------------------------
if (( ! QUIET )); then
  echo
  if fp_core_ready && fp_scope_with_remote >/dev/null 2>&1; then
    say "$PLUGIN_ID: installation completed. Flatpak is ready."
  else
    say "$PLUGIN_ID: integration installed, but Flatpak still needs setup."
    say "Open Setup > Flatpaks > Setup & Check, or run: omarchy-flatpak-setup setup"
  fi
fi
