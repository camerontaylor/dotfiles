# Install a daily reaper for $TMPDIR, and sweep once now.
#
# zsh/env.d/05_tmp_dir.zsh points TMPDIR at ~/.tmp so temp paths are stable
# across login sessions and, on Linux, stay off tmpfs. The trade-off is that
# the OS no longer reaps it: macOS only sweeps /var/folders/..., and
# systemd-tmpfiles only sweeps /tmp. Nothing had ever cleaned ~/.tmp, so it
# grew unbounded — on neptune it reached 11 GB of abandoned ruby-build scratch
# dirs (ruby-build only cleans up after a *successful* build) and filled the
# disk to 186 MB free.
#
# Scheduling mirrors 99_periodic.zsh: systemd timer (user or system), macOS
# launchd LaunchAgent, then crontab. Each branch is idempotent.

pruner=$SCRIPT_DIR/scripts/prune-tmpdir

if [[ ! -x $pruner ]]; then
    printf '%s\n' "Skipping TMPDIR prune: $pruner not executable"
    return 0
fi

printf '%s\n' "Pruning stale TMPDIR entries..."
if (( DEPLOY_DRY_RUN )); then
    $pruner --dry-run | tail -1
else
    $pruner
fi

printf '%s\n' "Installing daily TMPDIR prune task..."

# The job must run through a login shell so env.d sets TMPDIR before the
# pruner reads it; launchd and cron otherwise hand it a bare environment.
zsh_bin=$(command -v zsh || printf '%s' /bin/zsh)
prune_command="${(q)pruner}"

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would schedule: $zsh_bin -lc $prune_command (daily)"
    return 0
fi

if have systemctl; then
    printf '%s\n' "  ...systemd detected, installing timer..."

    systemd_unit_dir= systemctl_cmd=
    if (( EUID == 0 )); then
        systemd_unit_dir=/etc/systemd/system
        systemctl_cmd=(systemctl)
    else
        systemd_unit_dir=$XDG_CONFIG_HOME/systemd/user
        systemctl_cmd=(systemctl --user)
    fi
    deploy_mkdir -p $systemd_unit_dir

    service_content="[Unit]
Description=Prune stale TMPDIR entries

[Service]
Type=oneshot
ExecStart=$zsh_bin -lc $prune_command"
    printf '%s\n' "$service_content" > $systemd_unit_dir/prune-tmpdir.service

    timer_content="[Unit]
Description=Prune stale TMPDIR entries daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=600s
Persistent=true

[Install]
WantedBy=timers.target"
    printf '%s\n' "$timer_content" > $systemd_unit_dir/prune-tmpdir.timer

    if ${systemctl_cmd[@]} daemon-reload > /dev/null && ${systemctl_cmd[@]} enable --now prune-tmpdir.timer > /dev/null; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "Failed to install prune-tmpdir timer. Check permissions and systemd setup"
    fi
elif [[ $DOTFILES_OS == Darwin ]] && have launchctl && (( EUID != 0 )); then
    printf '%s\n' "  ...launchd detected, installing user LaunchAgent..."

    launchd_dir=$HOME/Library/LaunchAgents
    launchd_label=com.ctaylor.dotfiles.prune-tmpdir
    launchd_plist=$launchd_dir/$launchd_label.plist
    deploy_mkdir -p $launchd_dir

    launchd_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$launchd_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$zsh_bin</string>
        <string>-lc</string>
        <string>$prune_command</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$XDG_STATE_HOME/prune-tmpdir.log</string>
    <key>StandardErrorPath</key>
    <string>$XDG_STATE_HOME/prune-tmpdir.err</string>
</dict>
</plist>"
    printf '%s\n' "$launchd_content" > $launchd_plist

    launchctl bootout gui/$EUID $launchd_plist > /dev/null 2>&1 || true
    if launchctl bootstrap gui/$EUID $launchd_plist > /dev/null 2>&1 \
        && launchctl enable gui/$EUID/$launchd_label > /dev/null 2>&1; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "Failed to install launchd task. Check $launchd_plist"
    fi
elif have crontab; then
    printf '%s\n' "  ...cron detected, installing job..."
    cron_task="$zsh_bin -lc $prune_command"
    cron_schedule="30 3 * * * $cron_task"
    if cat <(grep --invert-match --fixed-strings $cron_task <(crontab -l 2>/dev/null)) <(echo $cron_schedule) | crontab -; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "Failed to install cron job; run $pruner manually or add it to crontab"
    fi
else
    printf '%s\n' "  ...no scheduler detected, skipping"
fi
