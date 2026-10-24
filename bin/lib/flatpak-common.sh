#!/usr/bin/env bash

# Shared helpers for the flatpak-integration Omarchy plugin.
#
# Sourced by every entry point. Keeps dependency checks, installation-scope
# resolution, remote management, AppStream refreshes and cache handling in one
# place so the menu, the TUI installer, the updater and the bar widget agree.

if [[ -n ${_FLATPAK_INTEGRATION_COMMON:-} ]]; then
  return 0
fi
_FLATPAK_INTEGRATION_COMMON=1

# --------------------------------------------------------------------------
# Defaults and configuration
# --------------------------------------------------------------------------

FP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/flatpak-integration"
FP_CONFIG_FILE="$FP_CONFIG_DIR/config"
FP_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy"
FP_APPS_CACHE="$FP_CACHE_DIR/flatpak-integration-apps.cache"

# Launcher bridge: Flatpak exports desktop entries and icons outside the
# standard application dirs. When the session started before Flatpak was
# installed, the shell's XDG_DATA_DIRS does not include them and the app menu
# stays empty. Mirroring the exports into these standard, always-scanned paths
# makes new apps appear immediately, with icons, without a logout.
FP_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
FP_APP_LINKS_DIR="$FP_DATA_HOME/applications"
FP_ICON_BRIDGE_DIR="$FP_DATA_HOME/icons/flatpak"
FP_DESKTOP_BRIDGE_STAMP="$FP_CACHE_DIR/flatpak-integration-desktop-bridge.stamp"

FP_SCOPE="auto"
FP_REMOTE="flathub"
FP_REMOTE_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FP_CACHE_MAX_AGE=86400

# Commands the plugin itself needs. Packages are the Arch names Omarchy uses.
FP_REQUIRED_COMMANDS=(flatpak bwrap fzf python3 jq timeout)
FP_REQUIRED_OMARCHY=(omarchy-menu-select omarchy-notification-send omarchy-launch-floating-terminal-with-presentation)

fp_load_config() {
  if [[ -f $FP_CONFIG_FILE ]]; then
    # shellcheck disable=SC1090
    . "$FP_CONFIG_FILE"
  fi

  FP_SCOPE="${OMARCHY_FLATPAK_SCOPE:-$FP_SCOPE}"
  FP_REMOTE="${OMARCHY_FLATPAK_REMOTE:-$FP_REMOTE}"
  FP_REMOTE_URL="${OMARCHY_FLATPAK_REMOTE_URL:-$FP_REMOTE_URL}"

  [[ $FP_SCOPE =~ ^(auto|user|system)$ ]] || FP_SCOPE="auto"
  [[ -n $FP_REMOTE ]] || FP_REMOTE="flathub"
  [[ -n $FP_REMOTE_URL ]] || FP_REMOTE_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
  [[ $FP_CACHE_MAX_AGE =~ ^[0-9]+$ ]] || FP_CACHE_MAX_AGE=86400
}

fp_load_config

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  FP_BOLD=$'\033[1m'
  FP_DIM=$'\033[2m'
  FP_RED=$'\033[31m'
  FP_GREEN=$'\033[32m'
  FP_YELLOW=$'\033[33m'
  FP_BLUE=$'\033[34m'
  FP_RESET=$'\033[0m'
else
  FP_BOLD=""
  FP_DIM=""
  FP_RED=""
  FP_GREEN=""
  FP_YELLOW=""
  FP_BLUE=""
  FP_RESET=""
fi

fp_info() { printf '%s\n' "$*" >&2; }
fp_ok() { printf '  %s[ok]%s %s\n' "$FP_GREEN" "$FP_RESET" "$*"; }
fp_warn() { printf '  %s[warn]%s %s\n' "$FP_YELLOW" "$FP_RESET" "$*" >&2; }
fp_err() { printf '  %s[fail]%s %s\n' "$FP_RED" "$FP_RESET" "$*" >&2; }
fp_note() { printf '  %s[info]%s %s\n' "$FP_BLUE" "$FP_RESET" "$*"; }

fp_heading() {
  printf '%s%s%s\n' "$FP_BOLD" "$*" "$FP_RESET"
  printf '%s%s%s\n' "$FP_DIM" "────────────────────────────────────────────────────────────" "$FP_RESET"
}

# --------------------------------------------------------------------------
# Small utilities
# --------------------------------------------------------------------------

fp_have() { command -v "$1" >/dev/null 2>&1; }

fp_flatpak_version() {
  flatpak --version 2>/dev/null | awk '{print $2; exit}'
}

fp_scope_flag() {
  case "${1:-$FP_SCOPE}" in
    user) printf '%s' "--user" ;;
    system) printf '%s' "--system" ;;
    *) return 1 ;;
  esac
}

fp_other_scope() {
  [[ ${1:-$FP_SCOPE} == "user" ]] && printf '%s' "system" || printf '%s' "user"
}

fp_scope_label() {
  case "${1:-$FP_SCOPE}" in
    user) printf '%s' "per-user" ;;
    system) printf '%s' "system-wide" ;;
    auto) printf '%s' "automatic" ;;
    *) printf '%s' "$1" ;;
  esac
}

# True when the file exists and is newer than FP_CACHE_MAX_AGE seconds.
fp_file_is_fresh() {
  local file="$1"
  [[ -f $file ]] || return 1
  local mtime now
  mtime=$(stat -c %Y -- "$file" 2>/dev/null) || return 1
  now=$(date +%s)
  (( now - mtime < FP_CACHE_MAX_AGE ))
}

# --------------------------------------------------------------------------
# Flathub remote and installation scope
# --------------------------------------------------------------------------

# True when the given scope has the configured remote.
fp_remote_exists() {
  local scope="${1:-$(fp_resolve_scope)}" remote="${2:-$FP_REMOTE}" flag
  flag=$(fp_scope_flag "$scope") || return 1
  fp_have flatpak || return 1

  flatpak remotes "$flag" --columns=name 2>/dev/null |
    awk -v want="$remote" '$1 == want { found = 1 } END { exit !found }'
}

# True when the remote exists and is not disabled.
fp_remote_enabled() {
  local scope="${1:-$(fp_resolve_scope)}" remote="${2:-$FP_REMOTE}" flag options
  flag=$(fp_scope_flag "$scope") || return 1
  fp_have flatpak || return 1

  options=$(flatpak remotes "$flag" --columns=name,options 2>/dev/null |
    awk -F '\t' -v want="$remote" '$1 == want { print $2; exit }')
  [[ -n $options ]] || return 0
  [[ $options != *disabled* ]]
}

# Work out which installation to use.
#
# "auto" keeps an existing setup working: it prefers the per-user installation
# when a remote is already there, otherwise the system installation, and only
# falls back to creating a per-user setup when neither has the remote.
fp_resolve_scope() {
  if [[ $FP_SCOPE == "user" || $FP_SCOPE == "system" ]]; then
    printf '%s' "$FP_SCOPE"
    return 0
  fi

  fp_have flatpak || {
    printf '%s' "user"
    return 0
  }

  if fp_remote_exists user "$FP_REMOTE"; then
    printf '%s' "user"
  elif fp_remote_exists system "$FP_REMOTE"; then
    printf '%s' "system"
  else
    printf '%s' "user"
  fi
}

# Pick the scope that actually has the configured remote, preferring the
# resolved scope. Prints nothing when no installation has it.
fp_scope_with_remote() {
  local preferred other
  preferred=$(fp_resolve_scope)
  other=$(fp_other_scope "$preferred")

  # Prefer an enabled remote; fall back to a configured-but-disabled one so
  # repair can turn it back on.
  if fp_remote_exists "$preferred" && fp_remote_enabled "$preferred"; then
    printf '%s' "$preferred"
  elif fp_remote_exists "$other" && fp_remote_enabled "$other"; then
    printf '%s' "$other"
  elif fp_remote_exists "$preferred"; then
    printf '%s' "$preferred"
  elif fp_remote_exists "$other"; then
    printf '%s' "$other"
  else
    return 1
  fi
}

# Add (or re-enable) the configured remote in the resolved installation.
fp_ensure_remote() {
  local scope flag
  scope=$(fp_resolve_scope)
  flag=$(fp_scope_flag "$scope")

  if fp_have flatpak && fp_remote_exists "$scope"; then
    if ! fp_remote_enabled "$scope"; then
      fp_info "Enabling the $FP_REMOTE remote in the $(fp_scope_label "$scope") installation..."
      flatpak remote-modify "$flag" --enable "$FP_REMOTE" >/dev/null 2>&1 || {
        fp_warn "Could not enable the $FP_REMOTE remote."
        return 1
      }
    fi
    return 0
  fi

  fp_info "Adding the $FP_REMOTE remote to the $(fp_scope_label "$scope") installation..."
  if flatpak remote-add --if-not-exists "$flag" "$FP_REMOTE" "$FP_REMOTE_URL"; then
    fp_ok "$FP_REMOTE remote added ($(fp_scope_label "$scope"))"
    return 0
  fi

  fp_err "Could not add the $FP_REMOTE remote to the $(fp_scope_label "$scope") installation."
  if [[ $scope == "system" ]]; then
    fp_info "Try again from a terminal so Flatpak can ask for administrator access,"
    fp_info "or choose the per-user installation with: omarchy-flatpak-setup configure --scope=user"
  fi
  return 1
}

# --------------------------------------------------------------------------
# AppStream and the application catalog
# --------------------------------------------------------------------------

fp_appstream_dir() {
  local scope="${1:-$(fp_scope_with_remote 2>/dev/null || fp_resolve_scope)}"
  if [[ $scope == "user" ]]; then
    printf '%s' "$HOME/.local/share/flatpak/appstream/$FP_REMOTE"
  else
    printf '%s' "/var/lib/flatpak/appstream/$FP_REMOTE"
  fi
}

fp_appstream_present() {
  local scope="${1:-$(fp_scope_with_remote 2>/dev/null || fp_resolve_scope)}"
  [[ -d $(fp_appstream_dir "$scope") ]]
}

# Refresh AppStream metadata. With --stale-only the network is only touched
# when the stamp is older than FP_CACHE_MAX_AGE (or metadata is missing).
fp_ensure_appstream() {
  local stale_only=0
  [[ ${1:-} == "--stale-only" ]] && stale_only=1

  fp_have flatpak || return 1

  local scope flag stamp
  scope=$(fp_scope_with_remote) || {
    fp_warn "No $FP_REMOTE remote available; cannot refresh AppStream metadata."
    return 1
  }
  flag=$(fp_scope_flag "$scope")
  stamp="$FP_CACHE_DIR/appstream-$scope-$FP_REMOTE.stamp"

  if (( stale_only )) && fp_file_is_fresh "$stamp" && fp_appstream_present "$scope"; then
    return 0
  fi

  fp_info "Refreshing $FP_REMOTE metadata ($(fp_scope_label "$scope"))..."
  timeout 180 flatpak update "$flag" --appstream >/dev/null 2>&1
  local status=$?
  if (( status == 0 )); then
    mkdir -p "$FP_CACHE_DIR"
    touch "$stamp"
    return 0
  fi

  fp_warn "Could not refresh $FP_REMOTE metadata (network or permission problem)."
  return 1
}

# Emit one tab-separated "application<TAB>name<TAB>version" row per application
# across both installations, preferring the resolved scope.
fp_remote_app_rows() {
  fp_have flatpak || return 1

  local preferred other scope flag out rows=""
  preferred=$(fp_resolve_scope)
  other=$(fp_other_scope "$preferred")

  for scope in "$preferred" "$other"; do
    fp_remote_exists "$scope" || continue
    flag=$(fp_scope_flag "$scope")
    out=$(timeout 120 flatpak remote-ls "$flag" --app "$FP_REMOTE" \
      --columns=application,name,version 2>/dev/null) || continue
    [[ -n $out ]] && rows+="$out"$'\n'
  done

  [[ -n $rows ]] || return 1

  # The same app id can exist in both installations; keep the preferred one.
  printf '%s' "$rows" |
    awk -F '\t' 'NF >= 3 && !seen[$1]++ { print $1 "\t" $2 "\t" $3 }' |
    LC_ALL=C sort -t $'\t' -k2,2f -k1,1
}

fp_refresh_app_cache() {
  local force=0 quiet=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      --quiet) quiet=1 ;;
    esac
  done

  if (( ! force )) && fp_file_is_fresh "$FP_APPS_CACHE"; then
    return 0
  fi

  local rows tmp
  rows=$(fp_remote_app_rows)

  if [[ -z $rows ]]; then
    if [[ -s $FP_APPS_CACHE ]]; then
      (( quiet )) || fp_warn "Could not refresh the application list; using the cached copy."
      return 0
    fi
    (( quiet )) || fp_warn "The application list is empty."
    return 1
  fi

  mkdir -p "$FP_CACHE_DIR"
  tmp=$(mktemp "$FP_APPS_CACHE.XXXXXX")
  printf '%s\n' "$rows" >"$tmp"
  mv -f "$tmp" "$FP_APPS_CACHE"

  if (( ! quiet )); then
    fp_ok "Application catalog updated ($(wc -l <"$FP_APPS_CACHE") applications)."
  fi
  return 0
}

# --------------------------------------------------------------------------
# Installed applications and their installation
# --------------------------------------------------------------------------

# Tab-separated "application<TAB>name<TAB>installation" for every installed app.
fp_installed_app_rows() {
  fp_have flatpak || return 1
  flatpak list --app --columns=application,name,installation 2>/dev/null |
    awk -F '\t' 'NF >= 3 { print $1 "\t" $2 "\t" $3 }'
}

fp_installed_app_ids() {
  fp_have flatpak || return 1
  flatpak list --app --columns=application 2>/dev/null
}

# Which installation owns an app: user, system, or a named installation.
fp_app_installation() {
  local app="$1"
  fp_have flatpak || return 1
  flatpak list --app --columns=application,installation 2>/dev/null |
    awk -F '\t' -v want="$app" '$1 == want { print $2; exit }'
}

# Flag for commands that operate on a specific installed app.
fp_flag_for_app() {
  local app="$1" installation
  installation=$(fp_app_installation "$app")

  case $installation in
    ""|system|default) printf '%s' "--system" ;;
    user) printf '%s' "--user" ;;
    *) printf '%s' "--installation=$installation" ;;
  esac
}

fp_scope_has_refs() {
  local scope="${1:-$FP_SCOPE}" flag
  flag=$(fp_scope_flag "$scope") || return 1
  [[ -n $(flatpak list "$flag" --columns=ref 2>/dev/null | head -n 1) ]]
}

# --------------------------------------------------------------------------
# Launcher bridge (desktop entries and icons)
# --------------------------------------------------------------------------

# Every directory Flatpak exports desktop files and icons into, deduplicated.
fp_export_share_dirs() {
  {
    printf '%s\n' "$FP_DATA_HOME/flatpak/exports/share"
    if fp_have flatpak; then
      flatpak --installations 2>/dev/null | while IFS= read -r root; do
        [[ -n $root ]] && printf '%s\n' "$root/exports/share"
      done
    else
      printf '%s\n' "/var/lib/flatpak/exports/share"
    fi
  } | awk 'NF && !seen[$0]++'
}

# True when a path lives under one of the given Flatpak export directories.
fp_path_in_export_dirs() {
  local target="${1:-}" dirs="${2:-}" dir
  [[ -n $target ]] || return 1
  while IFS= read -r dir; do
    [[ -n $dir && $target == "$dir"/* ]] && return 0
  done <<<"$dirs"
  return 1
}

# True when a path lives under one of Flatpak's export directories.
fp_is_flatpak_export_path() {
  local target="${1:-}"
  [[ -n $target ]] || return 1
  fp_path_in_export_dirs "$target" "$(fp_export_share_dirs)"
}

# True when the desktop session exposes Flatpak's export directories, i.e.
# whether a freshly started shell can list Flatpak apps without the bridge. The
# systemd user environment is what a new Hyprland session inherits; the current
# process environment is only a fallback.
fp_data_dirs_include_exports() {
  local dirs="" dir
  if fp_have systemctl; then
    dirs=$(systemctl --user show-environment 2>/dev/null |
      sed -n 's/^XDG_DATA_DIRS=//p' | tail -n 1)
  fi
  [[ -n $dirs ]] || dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

  while IFS= read -r dir; do
    case ":$dirs:" in
      *":$dir:"*|*":$dir/:"*) ;;
      *) return 1 ;;
    esac
  done < <(fp_export_share_dirs)
  return 0
}

# Remove links in a directory whose Flatpak export target no longer exists.
fp_prune_flatpak_links() {
  local dir="${1:-}" file target removed=0 dirs
  [[ -d $dir ]] || { printf '0'; return 0; }
  dirs=$(fp_export_share_dirs)

  while IFS= read -r -d '' file; do
    [[ -L $file ]] || continue
    target=$(readlink -- "$file" 2>/dev/null) || continue
    fp_path_in_export_dirs "$target" "$dirs" || continue
    [[ -e $file ]] && continue
    rm -f -- "$file" && removed=$((removed + 1))
  done < <(find "$dir" -type l -print0 2>/dev/null)

  printf '%s' "$removed"
}

# Sorted list of every desktop entry Flatpak currently exports, one file name
# per line and deduplicated across installations.
fp_export_desktop_names() {
  local dir
  while IFS= read -r dir; do
    [[ -d $dir/applications ]] || continue
    find "$dir/applications" -maxdepth 1 -name '*.desktop' -printf '%f\n' 2>/dev/null
  done < <(fp_export_share_dirs) | LC_ALL=C sort -u
}

# Desktop entries and icons Flatpak exports that the bridge has not linked yet.
# Zero means the app menu is up to date.
fp_desktop_bridge_pending() {
  local name dest count=0 dir file rel
  while IFS= read -r name; do
    dest="$FP_APP_LINKS_DIR/$name"
    [[ -e $dest || -L $dest ]] && continue
    count=$((count + 1))
  done < <(fp_export_desktop_names)

  while IFS= read -r dir; do
    [[ -d $dir/icons/hicolor ]] || continue
    while IFS= read -r -d '' file; do
      rel="${file#"$dir/icons/hicolor/"}"
      dest="$FP_ICON_BRIDGE_DIR/$rel"
      [[ -e $dest || -L $dest ]] && continue
      count=$((count + 1))
    done < <(find "$dir/icons/hicolor" -path '*/apps/*' \
      \( -name '*.png' -o -name '*.svg' \) \( -type f -o -type l \) -print0 2>/dev/null)
  done < <(fp_export_share_dirs)

  printf '%s' "$count"
}

# Hash of the Flatpak export tree. It changes when an app is installed,
# updated, or removed, which is exactly when the bridge needs a resync.
fp_desktop_bridge_fingerprint() {
  local dir
  {
    while IFS= read -r dir; do
      [[ -d $dir/applications ]] &&
        find "$dir/applications" -maxdepth 1 -name '*.desktop' -print 2>/dev/null
      [[ -d $dir/icons/hicolor ]] &&
        find "$dir/icons/hicolor" -path '*/apps/*' \
          \( -name '*.png' -o -name '*.svg' \) -print 2>/dev/null
    done < <(fp_export_share_dirs)
  } | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

fp_write_desktop_bridge_stamp() {
  local fingerprint="${1:-}"
  [[ -n $fingerprint ]] || fingerprint=$(fp_desktop_bridge_fingerprint)
  mkdir -p -- "$FP_CACHE_DIR" 2>/dev/null || return 0
  printf '%s\n' "$fingerprint" >"$FP_DESKTOP_BRIDGE_STAMP" 2>/dev/null || true
}

# Mirror Flatpak's exported .desktop files and icons into paths every launcher
# reads. Existing user files are never replaced; stale links are pruned. Safe
# to run on every shell start and after every install/uninstall.
fp_sync_desktop_bridge() {
  local source file name size dest created=0 removed=0
  local fingerprint
  fingerprint=$(fp_desktop_bridge_fingerprint)

  mkdir -p "$FP_APP_LINKS_DIR" || return 1

  removed=$((removed + $(fp_prune_flatpak_links "$FP_APP_LINKS_DIR")))
  [[ -d $FP_ICON_BRIDGE_DIR ]] &&
    removed=$((removed + $(fp_prune_flatpak_links "$FP_ICON_BRIDGE_DIR")))

  # Desktop entries. Exported files are symlinks, so match by name only.
  while IFS= read -r source; do
    [[ -d $source/applications ]] || continue
    while IFS= read -r -d '' file; do
      name=$(basename -- "$file")
      dest="$FP_APP_LINKS_DIR/$name"
      [[ -e $dest || -L $dest ]] && continue
      ln -s -- "$file" "$dest" && created=$((created + 1))
    done < <(find "$source/applications" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
  done < <(fp_export_share_dirs)

  # Icons, mirrored into a private hicolor-shaped tree. Omarchy's app library
  # scans ~/.local/share/icons recursively, so no theme merge is needed.
  while IFS= read -r source; do
    [[ -d $source/icons/hicolor ]] || continue
    while IFS= read -r -d '' file; do
      size=$(basename -- "$(dirname -- "$(dirname -- "$file")")")
      name=$(basename -- "$file")
      dest="$FP_ICON_BRIDGE_DIR/$size/apps/$name"
      [[ -e $dest || -L $dest ]] && continue
      mkdir -p -- "$(dirname -- "$dest")" || continue
      ln -s -- "$file" "$dest" && created=$((created + 1))
    done < <(find "$source/icons/hicolor" -path '*/apps/*' \
      \( -name '*.png' -o -name '*.svg' \) \( -type f -o -type l \) -print0 2>/dev/null)
  done < <(fp_export_share_dirs)

  # Refresh the MIME cache only when the set of links actually changed.
  if (( created > 0 || removed > 0 )) && fp_have update-desktop-database; then
    update-desktop-database "$FP_APP_LINKS_DIR" >/dev/null 2>&1 || true
  fi

  # Do not leave empty size/apps directories behind after pruning.
  if [[ -d $FP_ICON_BRIDGE_DIR ]]; then
    find "$FP_ICON_BRIDGE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  fi

  fp_write_desktop_bridge_stamp "$fingerprint"

  FP_DESKTOP_BRIDGE_CREATED=$created
  FP_DESKTOP_BRIDGE_REMOVED=$removed
  return 0
}

# Cheap variant for periodic checks: does nothing unless Flatpak's exports
# changed or a link went missing. Used by the shell service every 30 seconds.
fp_sync_desktop_bridge_if_needed() {
  local fingerprint
  fingerprint=$(fp_desktop_bridge_fingerprint)

  if [[ -f $FP_DESKTOP_BRIDGE_STAMP ]] &&
    [[ $(<"$FP_DESKTOP_BRIDGE_STAMP") == "$fingerprint" ]] &&
    (( $(fp_desktop_bridge_pending) == 0 )); then
    FP_DESKTOP_BRIDGE_CREATED=0
    FP_DESKTOP_BRIDGE_REMOVED=0
    return 0
  fi

  fp_sync_desktop_bridge
}

# Number of Flatpak entries currently linked into the app menu.
fp_desktop_bridge_count() {
  local file target count=0 dirs
  [[ -d $FP_APP_LINKS_DIR ]] || { printf '0'; return 0; }
  dirs=$(fp_export_share_dirs)

  while IFS= read -r -d '' file; do
    target=$(readlink -- "$file" 2>/dev/null) || continue
    fp_path_in_export_dirs "$target" "$dirs" && count=$((count + 1))
  done < <(find "$FP_APP_LINKS_DIR" -maxdepth 1 -type l -name '*.desktop' -print0 2>/dev/null)

  printf '%s' "$count"
}

# Remove every bridge link this plugin created. Used by the uninstaller.
fp_remove_desktop_bridge() {
  local file target removed=0

  while IFS= read -r -d '' file; do
    target=$(readlink -- "$file" 2>/dev/null) || continue
    fp_is_flatpak_export_path "$target" || continue
    rm -f -- "$file" && removed=$((removed + 1))
  done < <(
    find "$FP_APP_LINKS_DIR" -maxdepth 1 -type l -name '*.desktop' -print0 2>/dev/null
    find "$FP_ICON_BRIDGE_DIR" -type l -print0 2>/dev/null
  )

  if [[ -d $FP_ICON_BRIDGE_DIR ]]; then
    find "$FP_ICON_BRIDGE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  fi
  if fp_have update-desktop-database; then
    update-desktop-database "$FP_APP_LINKS_DIR" >/dev/null 2>&1 || true
  fi

  printf '%s' "$removed"
}

# --------------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------------

# Prints the missing command names, one per line.
fp_missing_commands() {
  local cmd
  for cmd in "${FP_REQUIRED_COMMANDS[@]}"; do
    fp_have "$cmd" || printf '%s\n' "$cmd"
  done
}

fp_missing_omarchy_commands() {
  local cmd
  for cmd in "${FP_REQUIRED_OMARCHY[@]}"; do
    fp_have "$cmd" || printf '%s\n' "$cmd"
  done
}

# Map a missing command to its Arch package.
fp_package_for_command() {
  case "$1" in
    flatpak) printf '%s' "flatpak" ;;
    bwrap) printf '%s' "bubblewrap" ;;
    fzf) printf '%s' "fzf" ;;
    python3) printf '%s' "python" ;;
    jq) printf '%s' "jq" ;;
    timeout) printf '%s' "coreutils" ;;
    gum) printf '%s' "gum" ;;
    *) return 1 ;;
  esac
}

fp_missing_packages() {
  fp_have pacman || return 1
  local cmd pkg seen=""
  while IFS= read -r cmd; do
    [[ -n $cmd ]] || continue
    pkg=$(fp_package_for_command "$cmd") || continue
    pacman -Q -- "$pkg" >/dev/null 2>&1 && continue
    case " $seen " in *" $pkg "*) continue ;; esac
    seen+=" $pkg"
    printf '%s\n' "$pkg"
  done < <(fp_missing_commands)
}

fp_install_packages() {
  (( $# > 0 )) || return 0

  if fp_have omarchy-pkg-add; then
    omarchy-pkg-add "$@"
  elif fp_have pacman; then
    if (( EUID == 0 )); then
      pacman -S --noconfirm --needed -- "$@"
    else
      sudo pacman -S --noconfirm --needed -- "$@"
    fi
  else
    fp_err "No supported package manager found. Install manually: $*"
    return 1
  fi
}

# Returns 0 when the plugin can actually work.
fp_core_ready() {
  fp_have flatpak && fp_have bwrap && fp_have fzf
}

# --------------------------------------------------------------------------
# Human-readable diagnostics
# --------------------------------------------------------------------------

# Print a full report. Returns 0 when everything critical is available.
fp_print_check() {
  local ready=0
  fp_heading "Flatpak Integration — system check"

  if fp_have flatpak; then
    fp_ok "Flatpak $(fp_flatpak_version)"
  else
    fp_err "Flatpak is not installed (package: flatpak)"
    ready=1
  fi

  if fp_have bwrap; then
    fp_ok "Bubblewrap sandbox helper"
  else
    fp_err "bubblewrap is missing (package: bubblewrap)"
    ready=1
  fi

  if fp_have fzf; then
    fp_ok "fzf fuzzy finder"
  else
    fp_err "fzf is missing (package: fzf)"
    ready=1
  fi

  if fp_have python3; then
    fp_ok "Python permission engine"
  else
    fp_err "python3 is missing (package: python) — permission manager disabled"
  fi

  if fp_have jq; then
    fp_ok "jq"
  else
    fp_warn "jq is missing (package: jq) — bar widget setup is limited"
  fi

  local missing_omarchy
  missing_omarchy=$(fp_missing_omarchy_commands)
  if [[ -z $missing_omarchy ]]; then
    fp_ok "Omarchy menu helpers"
  else
    fp_err "Missing Omarchy helpers: $(tr '\n' ' ' <<<"$missing_omarchy")"
    ready=1
  fi

  if fp_have flatpak; then
    local remote_scope
    if remote_scope=$(fp_scope_with_remote); then
      fp_ok "$FP_REMOTE remote configured ($(fp_scope_label "$remote_scope") installation)"
      if ! fp_remote_enabled "$remote_scope"; then
        fp_warn "$FP_REMOTE remote is disabled"
      fi
    else
      fp_err "$FP_REMOTE remote is not configured in any installation"
      ready=1
    fi

    if [[ -n $remote_scope ]]; then
      if fp_appstream_present "$remote_scope"; then
        fp_ok "AppStream metadata present"
      else
        fp_warn "AppStream metadata not downloaded yet (run setup)"
      fi
    fi

    if [[ -s $FP_APPS_CACHE ]]; then
      fp_ok "Application catalog cached ($(wc -l <"$FP_APPS_CACHE") apps)"
    else
      fp_warn "Application catalog not cached yet (run setup)"
    fi

    local installed_count bridge_count
    installed_count=$(fp_installed_app_ids 2>/dev/null | grep -c . || true)
    fp_ok "Installed Flatpak applications: ${installed_count:-0}"

    bridge_count=$(fp_desktop_bridge_count)
    if (( bridge_count > 0 )); then
      fp_ok "App menu entries linked ($bridge_count applications)"
    else
      fp_note "App menu entries will be linked after the first app install"
    fi

    if ! fp_data_dirs_include_exports; then
      fp_note "Flatpak's export paths are not in this session yet; the plugin links them for the app menu."
    fi
  fi

  echo
  if (( ready == 0 )); then
    printf '%sResult: ready.%s\n' "$FP_GREEN" "$FP_RESET"
    return 0
  fi

  printf '%sResult: setup required.%s\n' "$FP_YELLOW" "$FP_RESET"
  printf 'Run: omarchy-flatpak-setup setup\n'
  return 1
}

# Short machine-readable status used by the service/bar widget.
fp_print_status() {
  local ready=false flatpak_version="" scope="" remote_ok=false missing="" missing_omarchy=""
  local desktop_entries=0 session_exports=false
  fp_core_ready && fp_have python3 && ready=true
  flatpak_version=$(fp_have flatpak && fp_flatpak_version || true)
  scope=$(fp_resolve_scope)
  fp_remote_exists "$scope" && remote_ok=true
  missing=$(fp_missing_commands | tr '\n' ' ')
  missing_omarchy=$(fp_missing_omarchy_commands | tr '\n' ' ')
  desktop_entries=$(fp_desktop_bridge_count)
  fp_data_dirs_include_exports && session_exports=true

  jq -n \
    --argjson ready "$ready" \
    --arg flatpak "$flatpak_version" \
    --arg scope "$scope" \
    --arg remote "$FP_REMOTE" \
    --argjson remote_ok "$remote_ok" \
    --arg missing "$missing" \
    --arg missing_omarchy "$missing_omarchy" \
    --argjson desktop_entries "${desktop_entries:-0}" \
    --argjson session_exports "$session_exports" \
    --arg config "$FP_CONFIG_FILE" \
    '{
      ready: $ready,
      flatpak: $flatpak,
      scope: $scope,
      remote: $remote,
      remote_ok: $remote_ok,
      missing: ($missing | split(" ") | map(select(length > 0))),
      missing_omarchy: ($missing_omarchy | split(" ") | map(select(length > 0))),
      desktop_entries: $desktop_entries,
      session_exports: $session_exports,
      config: $config
    }'
}
