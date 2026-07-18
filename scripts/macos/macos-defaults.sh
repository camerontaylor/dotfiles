#!/usr/bin/env bash
# macos-defaults.sh — reproducible macOS settings for the dotfiles.
# Applies preferred App Shortcuts and Finder/navigation prefs. Run on any Mac,
# or let deploy run it (scripts/deploy.d/77_macos_defaults.zsh, macOS only).
#
#   ./macos-defaults.sh           # apply
#   DRY_RUN=1 ./macos-defaults.sh # print what would change, touch nothing
#
# Safe to re-run: each setting is applied only when it differs from the current
# value, and Finder is relaunched ONLY when a Finder pref actually changed — so
# running this on every `git pull` deploy is a quiet no-op once settings are in
# place. Everything here is reversible (flip the booleans / delete the
# NSUserKeyEquivalents keys).
#
# These are macOS-native tools (defaults/osascript/plutil/killall), so the script
# is inherently macOS-only; the deploy fragment gates it on Darwin.
#
# ---------------------------------------------------------------------------
# App Shortcut modifier encoding (NSUserKeyEquivalents):
#   @ = Command (⌘)   ~ = Option (⌥)   ^ = Control (⌃)   $ = Shift (⇧)
#   The trailing character is the key. Letters are literal; use the actual
#   shifted glyph if the menu shortcut shows one.
#   Examples:  ⌘⇧.  ->  "@$."     ⌃⌥F  ->  "^~f"     ⌘⌥i  ->  "@~i"
# ---------------------------------------------------------------------------
set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
pref_changes=0
duti_changes=0

# --- Rollback backups ------------------------------------------------------
# This script intentionally STOMPS drift (re-applies its values over whatever is
# live). Before overwriting any differing value, snapshot the current (old) value
# into a timestamped, NON-TRACKED restore script under XDG state — outside the
# repo, so it's never committed. Re-run that file to roll back. Created lazily on
# the first real write; nothing is written in DRY_RUN mode (no writes → no loss).
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macos-defaults"
BACKUP_TS="$(date +%Y%m%dT%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/backup-$BACKUP_TS.sh"
backup_started=0

ensure_backup() {
  [[ "$backup_started" == 1 ]] && return 0
  mkdir -p "$BACKUP_DIR"
  {
    echo "#!/bin/sh"
    echo "# macOS defaults rollback — values as they were at $BACKUP_TS, just before"
    echo "# macos-defaults.sh overwrote them. Run this file to restore them, then"
    echo "# 'killall Finder' if you reverted a Finder pref."
    echo
  } > "$BACKUP_FILE"
  chmod +x "$BACKUP_FILE"
  backup_started=1
  echo "  backup: $BACKUP_FILE"
}

# backup_pref <domain> <key> — append a restore command for one pref's old value.
backup_pref() {
  local domain="$1" key="$2" typ val
  ensure_backup
  if val="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    typ="$(defaults read-type "$domain" "$key" 2>/dev/null)"
    case "$typ" in
      *boolean*)
        # `defaults read` returns 0/1, but `defaults write -bool` only accepts
        # true|false|yes|no — normalise so the rollback command is valid.
        [[ "$val" == 1 ]] && val=true || val=false
        printf 'defaults write %q %q -bool %s\n'   "$domain" "$key" "$val" ;;
      *integer*) printf 'defaults write %q %q -int %s\n'    "$domain" "$key" "$val" ;;
      *float*)   printf 'defaults write %q %q -float %s\n'  "$domain" "$key" "$val" ;;
      *)         printf 'defaults write %q %q -string %q\n' "$domain" "$key" "$val" ;;
    esac >> "$BACKUP_FILE"
  else
    # Key was unset; rollback deletes whatever we are about to write.
    printf 'defaults delete %q %q 2>/dev/null || true\n' "$domain" "$key" >> "$BACKUP_FILE"
  fi
}

# backup_shortcut <domain> <menu title> — append a restore for one App Shortcut.
backup_shortcut() {
  local domain="$1" title="$2" cur
  ensure_backup
  cur="$(defaults export "$domain" - 2>/dev/null \
          | plutil -extract "NSUserKeyEquivalents.${title}" raw -o - - 2>/dev/null || true)"
  if [[ -n "$cur" ]]; then
    printf 'defaults write %q NSUserKeyEquivalents -dict-add %q %q\n' "$domain" "$title" "$cur" >> "$BACKUP_FILE"
  else
    {
      echo "# '${title}' was previously unset on ${domain}; rollback removes the entry we added:"
      printf '/usr/libexec/PlistBuddy -c %q "$HOME/Library/Preferences/%s.plist" 2>/dev/null || true\n' \
        "Delete :NSUserKeyEquivalents:${title}" "$domain"
    } >> "$BACKUP_FILE"
  fi
}

# duti_set_ext <bundle-id> <.ext> — point a file extension at an app only when it
# currently resolves elsewhere, recording the prior handler to the rollback file
# first. duti wants a leading dot for -s (extension) but no dot for -x (query).
duti_set_ext() {
  local id="$1" ext="$2" curid
  curid="$(duti -x "${ext#.}" 2>/dev/null | sed -n '2p')"
  [[ "$curid" == "$id" ]] && return 0
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "    would set: $ext -> $id (was: ${curid:-none})"
    duti_changes=$((duti_changes + 1)); return 0
  fi
  ensure_backup
  if [[ -n "$curid" ]]; then
    printf 'duti -s %q %q all\n' "$curid" "$ext" >> "$BACKUP_FILE"
  else
    printf '# %s had no prior default handler; rollback would clear it manually\n' "$ext" >> "$BACKUP_FILE"
  fi
  if duti -s "$id" "$ext" all 2>/dev/null; then
    echo "    set : $ext -> $id"
    duti_changes=$((duti_changes + 1))
  fi
}

# Resolve an app's bundle identifier from its display name (e.g. "ForkLift").
bundle_id() { osascript -e "id of app \"$1\"" 2>/dev/null; }

# set_app_shortcut <app-name | "global"> <exact menu title> <key-equivalent>
# Binds a menu item to a keystroke, exactly like System Settings > Keyboard >
# Keyboard Shortcuts > App Shortcuts. "global" = applies to all apps. Re-adding
# an identical binding is harmless; shortcuts register on next app launch/logout
# (no Finder relaunch needed), so these never trigger the relaunch gate.
set_app_shortcut() {
  local target="$1" title="$2" keyeq="$3" domain cur
  if [[ "$target" == "global" ]]; then
    domain="NSGlobalDomain"
  else
    domain="$(bundle_id "$target")"
    if [[ -z "$domain" ]]; then
      echo "  skip: '$target' not installed — shortcut not set"
      return
    fi
  fi
  # Read the current binding for this exact menu title, if any. Use the same
  # cfprefsd-safe path as capture-shortcuts.sh (export | extract) rather than
  # guessing a .plist location, which is wrong for global/sandboxed domains.
  cur="$(defaults export "$domain" - 2>/dev/null \
          | plutil -extract "NSUserKeyEquivalents.${title}" raw -o - - 2>/dev/null || true)"
  if [[ "$cur" == "$keyeq" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would set: [$target] \"$title\" = $keyeq (was: ${cur:-unset})"
    return 0
  fi
  backup_shortcut "$domain" "$title"
  defaults write "$domain" NSUserKeyEquivalents -dict-add "$title" "$keyeq"
  echo "  set : [$target] \"$title\" = $keyeq"
}

# pref <domain> <key> <-bool|-string|-int> <value>
# Writes only when the current value differs; tracks changes so we can relaunch
# Finder exactly once when something actually moved.
pref() {
  local domain="$1" key="$2" type="$3" value="$4" cur want
  cur="$(defaults read "$domain" "$key" 2>/dev/null || echo "__unset__")"
  if [[ "$type" == "-bool" ]]; then
    [[ "$value" == "true" ]] && want=1 || want=0
  else
    want="$value"
  fi
  if [[ "$cur" == "$want" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would set: $domain $key = $value (was: $cur)"
  else
    backup_pref "$domain" "$key"
    defaults write "$domain" "$key" "$type" "$value"
    echo "  set : $domain $key = $value"
  fi
  pref_changes=$((pref_changes + 1))
}

echo "Applying App Shortcuts..."
# --- Your custom keyboard shortcuts ---------------------------------------
# ForkLift: toggle hidden/dotfiles with ⌘⇧. (mirrors Finder's muscle memory).
# Menu title must match ForkLift's View menu exactly.
set_app_shortcut "ForkLift" "Show Invisible Files" '@$.'
# Add more below as you discover them (capture-shortcuts.sh prints these for you):
# set_app_shortcut "global" "Show Inspector" '@~i'

echo "Applying Finder & global preferences..."
# --- Finder / navigation niceties (all reversible) ------------------------
pref com.apple.finder AppleShowAllFiles      -bool   true    # show hidden files in Finder
pref NSGlobalDomain   AppleShowAllExtensions -bool   true    # always show file extensions
pref com.apple.finder _FXSortFoldersFirst    -bool   true    # keep folders on top
pref com.apple.finder FXDefaultSearchScope   -string "SCcf"  # search current folder by default
pref com.apple.finder ShowPathbar            -bool   true    # show the path bar
pref com.apple.finder ShowStatusBar          -bool   true    # show the status bar

echo "Setting default-app associations (duti)..."
# --- File-type defaults: open most text/code in VS Code --------------------
# Requires duti (brew install duti; 75_brew_setup.zsh installs it). UTI families
# inherit and cover broad classes; the per-extension sweep is change-aware and
# recorded in the rollback file, so every per-extension association is reversible.
# (UTI-family handlers aren't individually queryable via duti, so they're applied
# idempotently and not individually backed up.)
if command -v duti >/dev/null 2>&1; then
  code_id="$(bundle_id "Visual Studio Code")"
  if [[ -n "$code_id" ]]; then
    # Broad UTI families (role all = viewer + editor).
    for uti in public.plain-text public.source-code public.shell-script \
               public.script public.python-script public.json public.xml \
               public.yaml net.daringfireball.markdown; do
      if [[ "$DRY_RUN" == 1 ]]; then
        echo "    would set: $uti -> VS Code"
      else
        duti -s "$code_id" "$uti" all 2>/dev/null || true
      fi
    done
    # Per-extension sweep (change-aware + backed up). Trim/extend to taste;
    # verify any binding with `duti -x md`.
    for ext in .txt .md .markdown .js .jsx .ts .tsx .json .yaml .yml .toml \
               .ini .conf .cfg .env .sh .bash .zsh .py .rb .go .rs .c .h \
               .cpp .hpp .java .css .scss .html .sql .lua .vim .log .csv; do
      duti_set_ext "$code_id" "$ext"
    done
    echo "  duti: ${duti_changes} extension association(s) changed"
  else
    echo "  skip: Visual Studio Code not installed"
  fi
else
  echo "  skip: duti not installed (brew install duti)"
fi
# Note: macOS special-cases folders (public.folder) to Finder; duti can't
# reliably reassign double-clicking a folder to ForkLift — use the Raycast
# 'Open in ForkLift' command (raycast/open-in-forklift.sh) for that instead.

# Relaunch Finder once if a pref or file association actually changed, so the new
# state shows immediately. (Skipped in dry-run and when nothing changed, so the
# post-merge auto-deploy never relaunches Finder on a no-op pull.)
if [[ "$DRY_RUN" == 1 ]]; then
  echo "Dry run: nothing applied."
elif (( pref_changes + duti_changes > 0 )); then
  killall Finder 2>/dev/null || true
  echo "Relaunched Finder ($pref_changes pref + $duti_changes association change(s))."
else
  echo "Already current; nothing changed, Finder not relaunched."
fi

echo "Done. Log out/in (or restart affected apps) for shortcut changes to register."
