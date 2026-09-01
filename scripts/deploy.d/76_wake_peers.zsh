# wake-peers: macOS-only screen-wake fanout for Universal Control. When this
# Mac's display wakes, sleepwatcher fires ~/.displaywakeup which runs
# scripts/wake-peers, SSHing `caffeinate -u -t 1` to every other peer.
#
# Activated ONLY on macOS hosts whose short hostname appears in
# configs/wake-peers/peers.conf. Non-peer Macs (and all non-macOS hosts) skip
# silently. Custom launchd label avoids collision with brew's default
# homebrew.mxcl.sleepwatcher plist.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

peers_conf=$SCRIPT_DIR/configs/wake-peers/peers.conf
if [[ ! -r $peers_conf ]]; then
    printf '%s\n' "wake-peers: $peers_conf not found, skipping"
    return 0
fi

# Canonical short hostname; falls back to BSD hostname -s.
self=
self=$(scutil --get LocalHostName 2>/dev/null) || self=$(hostname -s 2>/dev/null) || self=""
if [[ -z $self ]]; then
    printf '%s\n' "wake-peers: could not determine local hostname, skipping"
    return 0
fi

# Strip comments/blank lines from peers.conf into an array.
peers=()
peers=("${(@f)$(awk '{ sub(/#.*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") } NF > 0' $peers_conf)}")

host= self_in_list=0
for host in "${peers[@]}"; do
    [[ $host == $self ]] && self_in_list=1
done

if (( ! self_in_list )); then
    printf '%s\n' "wake-peers: $self not in peer list, skipping setup"
    return 0
fi

printf '%s\n' "Setting up wake-peers on $self..."

# 1. Install sleepwatcher (brew formula provides /opt/homebrew/sbin/sleepwatcher
#    on Apple Silicon, /usr/local/sbin/sleepwatcher on Intel).
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: brew_install_or_upgrade sleepwatcher"
else
    brew_install_or_upgrade sleepwatcher sleepwatcher || {
        printf '%s\n' "  ...sleepwatcher install failed, skipping LaunchAgent setup"
        return 0
    }
fi

# 2. Resolve sleepwatcher path (brew puts it in sbin/, which is not always on
#    interactive PATH but is fine in launchd ProgramArguments as an absolute).
sw_path=""
candidate=
for candidate in /opt/homebrew/sbin/sleepwatcher /usr/local/sbin/sleepwatcher; do
    if [[ -x $candidate ]]; then
        sw_path=$candidate
        break
    fi
done
if [[ -z $sw_path ]] && (( ! DEPLOY_DRY_RUN )); then
    printf '%s\n' "  ...sleepwatcher binary not found after install, skipping LaunchAgent"
    return 0
fi
[[ -z $sw_path ]] && sw_path="/opt/homebrew/sbin/sleepwatcher"  # placeholder for dry-run print

# 3. Render the LaunchAgent plist. Substituting @HOME@ and @SLEEPWATCHER_PATH@
#    lets a single tracked template serve both Apple Silicon and Intel Macs.
plist_template=$SCRIPT_DIR/configs/wake-peers/com.github.ctaylor.wake-peers.plist
plist_target=$HOME/Library/LaunchAgents/com.github.ctaylor.wake-peers.plist
if [[ ! -f $plist_template ]]; then
    printf '%s\n' "  ...plist template $plist_template missing, skipping"
    return 0
fi

plist_rendered=
plist_rendered=$(awk -v home="$HOME" -v sw="$sw_path" '
    { gsub(/@HOME@/, home); gsub(/@SLEEPWATCHER_PATH@/, sw); print }
' $plist_template)

needs_write=1
if [[ -f $plist_target ]]; then
    if [[ "$plist_rendered" == "$(cat $plist_target)" ]]; then
        needs_write=0
    fi
fi

if (( needs_write )); then
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: render plist -> $plist_target"
    else
        mkdir -p $HOME/Library/LaunchAgents
        printf '%s\n' "$plist_rendered" > $plist_target
        printf '%s\n' "  ...rendered $plist_target"
    fi
fi

# 4. Bootstrap (or reload on upgrade / plist change) the LaunchAgent. Use
#    bootstrap/bootout for the modern domain-style API; fall back nowhere
#    (launchctl load is deprecated on macOS 11+).
agent_label=com.github.ctaylor.wake-peers
domain=gui/$(id -u)

# Probe whether the agent is currently loaded.
already_loaded=0
if launchctl print "$domain/$agent_label" > /dev/null 2>&1; then
    already_loaded=1
fi

if (( DEPLOY_DRY_RUN )); then
    if (( already_loaded )); then
        printf '%s\n' "  [dry-run] would: launchctl bootout + bootstrap (reload)"
    else
        printf '%s\n' "  [dry-run] would: launchctl bootstrap $domain $plist_target"
    fi
    return 0
fi

if (( needs_write && already_loaded )); then
    launchctl bootout "$domain/$agent_label" > /dev/null 2>&1 || true
    already_loaded=0
fi

if (( ! already_loaded )); then
    if launchctl bootstrap "$domain" "$plist_target" > /dev/null 2>&1; then
        printf '%s\n' "  ...launchd agent $agent_label loaded"
    else
        printf '%s\n' "  ...launchctl bootstrap failed (already loaded? rerun with --upgrade to refresh)"
    fi
elif $upgrade_mode; then
    launchctl kickstart -k "$domain/$agent_label" > /dev/null 2>&1 || true
    printf '%s\n' "  ...launchd agent $agent_label kickstarted"
fi
