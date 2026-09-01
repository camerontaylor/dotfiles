# macOS settings — App Shortcuts + Finder/navigation prefs (macOS only).
#
# Source of truth: scripts/macos/macos-defaults.sh. That script is change-aware
# (writes a `defaults` value only when it differs) and relaunches Finder only on
# an actual change, so running it on every deploy — including the post-merge
# auto-deploy after each `git pull` — is a quiet no-op once settings are applied.
# See scripts/macos/README.md for what it covers vs. what iCloud/Raycast sync.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

local macos_script=$SCRIPT_DIR/scripts/macos/macos-defaults.sh
if [[ ! -x $macos_script ]]; then
    printf '%s\n' "macos-defaults.sh missing or not executable; skipping"
    return 0
fi

printf '%s\n' "Applying macOS defaults (shortcuts + Finder prefs)..."
# Honour --dry-run by forwarding it as DRY_RUN=1 so the script previews without
# mutating. `|| true` keeps cosmetic-settings failures from aborting deploy
# (deploy.zsh runs under setopt err_exit).
if (( DEPLOY_DRY_RUN )); then
    DRY_RUN=1 bash "$macos_script" || true
else
    bash "$macos_script" || printf '%s\n' "  ...macos-defaults.sh reported issues (non-fatal)"
fi
