# Install a periodic-update task that runs `git pull` daily on its own.
# Prefers (in order): systemd timer (user or system), macOS launchd LaunchAgent,
# crontab fallback. Each branch is idempotent — re-running rewrites the unit.

print "Installing periodic update task..."
if have systemctl; then
    print "  ...systemd detected, installing timer for periodic updates..."

    local systemd_unit_dir systemctl_cmd
    if (( EUID == 0 )); then
        systemd_unit_dir=/etc/systemd/system
        systemctl_cmd=(systemctl)
        print "  ...running as root, installing system-wide timer..."
    else
        systemd_unit_dir=$XDG_CONFIG_HOME/systemd/user
        systemctl_cmd=(systemctl --user)
        print "  ...running as regular user, installing user timer..."
    fi
    zf_mkdir -p $systemd_unit_dir

    local service_name=pull-dotfiles.service
    local service_content="[Unit]
Description=Pull dotfiles update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/git -c user.name=systemd.update -c user.email=systemd@localhost pull --force
WorkingDirectory=$SCRIPT_DIR"
    print -r -- $service_content > $systemd_unit_dir/$service_name

    local timer_name=pull-dotfiles.timer
    local timer_content="[Unit]
Description=Pull dotfiles update daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=120s
Persistent=true

[Install]
WantedBy=timers.target"
    print -r -- $timer_content > $systemd_unit_dir/$timer_name

    if ${systemctl_cmd[@]} daemon-reload > /dev/null && ${systemctl_cmd[@]} enable --now $timer_name > /dev/null; then
       print "  ...done"
    else
       print "Failed to install systemd timer. Check permissions and systemd setup"
    fi
elif [[ $DOTFILES_OS == Darwin ]] && have launchctl && (( EUID != 0 )); then
    print "  ...launchd detected, installing user LaunchAgent..."

    local launchd_dir=$HOME/Library/LaunchAgents
    local launchd_label=com.ctaylor.dotfiles.pull
    local launchd_plist=$launchd_dir/$launchd_label.plist
    zf_mkdir -p $launchd_dir

    local launchd_command="cd ${(q)SCRIPT_DIR} && git -c user.name=launchd.update -c user.email=launchd@localhost pull --force"
    local launchd_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$launchd_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-lc</string>
        <string>$launchd_command</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$XDG_STATE_HOME/dotfiles-pull.log</string>
    <key>StandardErrorPath</key>
    <string>$XDG_STATE_HOME/dotfiles-pull.err</string>
</dict>
</plist>"
    print -r -- $launchd_content > $launchd_plist

    launchctl bootout gui/$EUID $launchd_plist > /dev/null 2>&1 || true
    if launchctl bootstrap gui/$EUID $launchd_plist > /dev/null 2>&1 \
        && launchctl enable gui/$EUID/$launchd_label > /dev/null 2>&1; then
       print "  ...done"
    else
       print "Failed to install launchd task. Check $launchd_plist"
    fi
elif have crontab; then
    print "  ...cron detected, installing job for periodic updates..."
    local cron_task="cd $SCRIPT_DIR && git -c user.name=cron.update -c user.email=cron@localhost pull --force"
    local cron_schedule="0 0 * * * $cron_task"
    if cat <(grep --ignore-case --invert-match --fixed-strings $cron_task <(crontab -l)) <(echo $cron_schedule) | crontab -; then
        print "  ...done"
    else
        print "Please add \`cd $SCRIPT_DIR && git pull\` to your crontab or just ignore this, you can always update dotfiles manually"
    fi
else
    print "  ...no systemd or cron detected, skipping"
fi
