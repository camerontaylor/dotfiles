# smb-mounts: macOS-only auto-mount of ceres's Samba shares. Installs the
# com.github.ctaylor.smb-mount LaunchAgent, which runs scripts/smb-mount at
# login and every 5 minutes to mount the shares listed for this host in
# configs/smb-mounts/mounts.conf.
#
# Activated ONLY on macOS hosts that appear in mounts.conf. Non-listed Macs
# (and all non-macOS hosts) skip silently — same host-gate shape as
# 76_wake_peers.zsh, which this fragment is modelled on.
#
# No root anywhere: the mounts land under $HOME (/Volumes is root:wheel 0755),
# and the SMB password comes from the login Keychain. Adding that Keychain
# entry is the one human step — see the header of scripts/smb-mount.
#
# The SERVER half (the [home] share itself) is not deployed: it lives in
# configs/samba/smb.conf and is installed on ceres by the hand-run, sudo-using
# scripts/setup-ceres-share.sh, per the "never wire a service installer into
# deploy.d" rule in AGENTS.md.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

mounts_conf=$SCRIPT_DIR/configs/smb-mounts/mounts.conf
if [[ ! -r $mounts_conf ]]; then
    printf '%s\n' "smb-mounts: $mounts_conf not found, skipping"
    return 0
fi

smb_self=
smb_self=$(scutil --get LocalHostName 2>/dev/null) || smb_self=$(hostname -s 2>/dev/null) || smb_self=""
if [[ -z $smb_self ]]; then
    printf '%s\n' "smb-mounts: could not determine local hostname, skipping"
    return 0
fi

# First field of each non-comment row is the client hostname. The while-read
# replaces zsh's ${(@f)…} line-split; awk already drops empty lines.
smb_hosts=()
while IFS= read -r _smb_host; do
    [[ -n $_smb_host ]] && smb_hosts+=("$_smb_host")
done < <(awk '{ sub(/#.*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") } NF > 0 { print $1 }' $mounts_conf)

smb_host= smb_self_listed=0
for smb_host in "${smb_hosts[@]}"; do
    [[ $smb_host == $smb_self ]] && smb_self_listed=1
done

if (( ! smb_self_listed )); then
    printf '%s\n' "smb-mounts: $smb_self has no rows in mounts.conf, skipping setup"
    return 0
fi

printf '%s\n' "Setting up smb-mounts on $smb_self..."

smb_script=$SCRIPT_DIR/scripts/smb-mount
if [[ ! -x $smb_script ]]; then
    printf '%s\n' "  ...$smb_script missing or not executable, skipping"
    return 0
fi

smb_plist_template=$SCRIPT_DIR/configs/smb-mounts/com.github.ctaylor.smb-mount.plist
smb_plist_target=$HOME/Library/LaunchAgents/com.github.ctaylor.smb-mount.plist
if [[ ! -f $smb_plist_template ]]; then
    printf '%s\n' "  ...plist template $smb_plist_template missing, skipping"
    return 0
fi

smb_plist_rendered=
smb_plist_rendered=$(awk -v home="$HOME" -v script="$smb_script" '
    { gsub(/@HOME@/, home); gsub(/@SCRIPT@/, script); print }
' $smb_plist_template)

smb_needs_write=1
if [[ -f $smb_plist_target ]]; then
    if [[ "$smb_plist_rendered" == "$(cat $smb_plist_target)" ]]; then
        smb_needs_write=0
    fi
fi

if (( smb_needs_write )); then
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: render plist -> $smb_plist_target"
    else
        mkdir -p $HOME/Library/LaunchAgents
        printf '%s\n' "$smb_plist_rendered" > $smb_plist_target
        printf '%s\n' "  ...rendered $smb_plist_target"
    fi
fi

# Bootstrap (or reload on plist change) the LaunchAgent — modern domain-style
# API; `launchctl load` is deprecated on macOS 11+.
smb_label=com.github.ctaylor.smb-mount
smb_domain=gui/$(id -u)

smb_loaded=0
if launchctl print "$smb_domain/$smb_label" > /dev/null 2>&1; then
    smb_loaded=1
fi

if (( DEPLOY_DRY_RUN )); then
    if (( smb_loaded )); then
        printf '%s\n' "  [dry-run] would: launchctl bootout + bootstrap (reload)"
    else
        printf '%s\n' "  [dry-run] would: launchctl bootstrap $smb_domain $smb_plist_target"
    fi
    return 0
fi

if (( smb_needs_write && smb_loaded )); then
    launchctl bootout "$smb_domain/$smb_label" > /dev/null 2>&1 || true
    smb_loaded=0
fi

if (( ! smb_loaded )); then
    if launchctl bootstrap "$smb_domain" "$smb_plist_target" > /dev/null 2>&1; then
        printf '%s\n' "  ...launchd agent $smb_label loaded"
    else
        printf '%s\n' "  ...launchctl bootstrap failed (already loaded? rerun with --upgrade to refresh)"
    fi
elif $upgrade_mode; then
    launchctl kickstart -k "$smb_domain/$smb_label" > /dev/null 2>&1 || true
    printf '%s\n' "  ...launchd agent $smb_label kickstarted"
fi

# The Keychain entry cannot be created unattended (it needs the password), so
# nudge rather than fail. Checked per address, since mount_smbfs looks the
# entry up by the exact server string it was handed.
smb_addr=
while IFS= read -r smb_addr; do
    [[ -z $smb_addr ]] && continue
    if ! security find-internet-password -a "$(id -un)" -s "$smb_addr" -r 'smb ' > /dev/null 2>&1; then
        printf '%s\n' "  ...no Keychain entry for $smb_addr — mounts will fail until you run:"
        printf '%s\n' "       security add-internet-password -a $(id -un) -r 'smb ' -s $smb_addr \\"
        printf '%s\n' "           -l 'ceres (SMB)' -T /sbin/mount_smbfs -U -w"
    fi
done < <(awk -v self="$smb_self" '{ sub(/#.*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") } NF > 3 && $1 == self { n = split($4, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") print a[i] }' $mounts_conf | sort -u || true)
