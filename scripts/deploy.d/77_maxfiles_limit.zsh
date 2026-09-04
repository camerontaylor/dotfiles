# Raise the launchd-inherited soft file-descriptor limit for GUI-launched
# processes (editors, Electron apps, file watchers).
#
# A login shell already gets a generous soft limit (env.d/rc.d chains never
# touch it, and `ulimit -Hn` is 1,048,576 by default on modern macOS), but
# GUI apps are launched directly by launchd, not through any shell rc chain
# — `ulimit` in zsh/bash startup files cannot reach them at all. macOS's own
# launchd-wide default soft `maxfiles` is 256 (verified via
# `launchctl limit maxfiles` on neptune, 2026-09-04), so every
# GUI-launched process starts there.
#
# The only supported way to change what launchd hands out is a LaunchDaemon
# in the SYSTEM domain that calls `launchctl limit maxfiles <soft> <hard>`
# once at boot (RunAtLoad) — Apple's own long-documented technique, still
# the current fix on macOS 15. This is the one launchd job in this repo that
# genuinely needs the system (not gui/$UID) domain, so — unlike every other
# job here — it needs root.
#
# Hard ceiling is pinned to kern.maxfilesperproc (`sysctl kern.maxfilesperproc`)
# so we never ask launchd for more than the kernel will actually grant.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

maxfiles_label=com.ctaylor.dotfiles.maxfiles
maxfiles_plist=/Library/LaunchDaemons/$maxfiles_label.plist
maxfiles_soft=65536
# Read the kernel's real per-process ceiling rather than hardcoding it — it
# differs by machine and macOS version, and asking launchd for more than the
# kernel grants is rejected outright. Fall back to the common default if the
# sysctl is ever missing.
maxfiles_hard=$(sysctl -n kern.maxfilesperproc 2>/dev/null) || maxfiles_hard=
if [[ -z $maxfiles_hard ]]; then
    maxfiles_hard=184320
fi

maxfiles_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$maxfiles_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>launchctl</string>
        <string>limit</string>
        <string>maxfiles</string>
        <string>$maxfiles_soft</string>
        <string>$maxfiles_hard</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>"

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "maxfiles limit: [dry-run] would raise the launchd soft limit to $maxfiles_soft via $maxfiles_plist (needs sudo)"
    return 0
fi

# System LaunchDaemon => root. Never prompt mid-deploy for a password; if
# passwordless sudo isn't set up, print the exact manual steps and move on.
if ! sudo -n true 2>/dev/null; then
    printf '%s\n' "maxfiles limit: passwordless sudo not available, skipping. Run by hand:"
    printf '%s\n' "  sudo tee $maxfiles_plist > /dev/null <<'EOF'"
    printf '%s\n' "$maxfiles_content"
    printf '%s\n' "EOF"
    printf '%s\n' "  sudo chown root:wheel $maxfiles_plist && sudo chmod 644 $maxfiles_plist"
    printf '%s\n' "  sudo launchctl bootout system/$maxfiles_label >/dev/null 2>&1"
    printf '%s\n' "  sudo launchctl bootstrap system $maxfiles_plist"
    return 0
fi

printf '%s\n' "Raising the launchd maxfiles soft limit..."

needs_write=1
if [[ -f $maxfiles_plist ]]; then
    if [[ "$maxfiles_content" == "$(sudo -n cat $maxfiles_plist 2>/dev/null)" ]]; then
        needs_write=0
    fi
fi

if (( needs_write )); then
    printf '%s\n' "$maxfiles_content" | sudo -n tee $maxfiles_plist > /dev/null
    sudo -n chown root:wheel $maxfiles_plist
    sudo -n chmod 644 $maxfiles_plist
    printf '%s\n' "  ...wrote $maxfiles_plist"
fi

already_loaded=0
if sudo -n launchctl print system/$maxfiles_label > /dev/null 2>&1; then
    already_loaded=1
fi

if (( needs_write && already_loaded )); then
    sudo -n launchctl bootout system/$maxfiles_label > /dev/null 2>&1 || true
    already_loaded=0
fi

if (( ! already_loaded )); then
    if sudo -n launchctl bootstrap system $maxfiles_plist > /dev/null 2>&1; then
        printf '%s\n' "  ...launchd daemon $maxfiles_label loaded"
    else
        printf '%s\n' "  ...launchctl bootstrap failed for $maxfiles_label (already loaded under a stale definition? try: sudo launchctl bootout system/$maxfiles_label)"
    fi
else
    printf '%s\n' "  ...launchd daemon $maxfiles_label already loaded, no change needed"
fi

printf '%s\n' "  ...current maxfiles soft limit: $(launchctl limit maxfiles | awk '{print $2}')"
