# ZeroTier install + network join. Network ID(s) come from $ZEROTIER_NETWORK_ID
# (or $ZEROTIER_NETWORK_IDS, space-separated) in zsh/env.d/9*_zerotier_secrets.zsh.
# Skipped silently when no network id is configured.

if [[ $DOTFILES_OS != Linux && $DOTFILES_OS != Darwin ]]; then
    return 0
fi

# Source secret env files since deploy.zsh runs in a fresh shell.
local secret_file
for secret_file in $SCRIPT_DIR/zsh/env.d/9[0-9]_zerotier_secrets.zsh(N); do
    source $secret_file
done

local -a zt_networks
if [[ -n ${ZEROTIER_NETWORK_IDS:-} ]]; then
    zt_networks=(${(z)ZEROTIER_NETWORK_IDS})
elif [[ -n ${ZEROTIER_NETWORK_ID:-} ]]; then
    zt_networks=($ZEROTIER_NETWORK_ID)
fi

if (( ${#zt_networks} == 0 )); then
    print "ZeroTier: no \$ZEROTIER_NETWORK_ID configured, skipping"
    return 0
fi

# Install the daemon when missing; refresh under --upgrade on macOS.
if [[ $DOTFILES_OS == Darwin ]]; then
    if ! ensure_homebrew_path; then
        print "ZeroTier: Homebrew not available, skipping"
        return 0
    fi
    if ! brew list --cask zerotier-one > /dev/null 2>&1; then
        print "Installing ZeroTier..."
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: brew install --cask zerotier-one"
        else
            if brew_cask_install_or_upgrade zerotier-one; then
                rehash
                print "  ...macOS may prompt to allow the ZeroTier system extension"
                print "     in System Settings -> Privacy & Security."
            else
                return 0
            fi
        fi
    elif $upgrade_mode; then
        print "Upgrading ZeroTier..."
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: brew upgrade --cask zerotier-one"
        else
            brew_cask_install_or_upgrade zerotier-one || true
        fi
    fi
else
    if (( ! ${+commands[curl]} )); then
        print "ZeroTier: curl not available, skipping install"
        return 0
    fi
    if (( ! ${+commands[zerotier-cli]} )); then
        print "Installing ZeroTier..."
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: curl -s https://install.zerotier.com | sudo bash"
        else
            if curl -s https://install.zerotier.com | sudo bash > /dev/null 2>&1; then
                rehash
                print "  ...done"
            else
                print "  ...failed to install ZeroTier"
                return 0
            fi
        fi
    fi
fi

# Ensure the daemon is running.
if [[ $DOTFILES_OS == Linux ]]; then
    if (( ${+commands[systemctl]} )) && ! systemctl is-active --quiet zerotier-one 2>/dev/null; then
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: sudo systemctl enable --now zerotier-one"
        else
            sudo systemctl enable --now zerotier-one > /dev/null 2>&1 || true
        fi
    fi
elif [[ $DOTFILES_OS == Darwin ]]; then
    local zt_plist=/Library/LaunchDaemons/com.zerotier.one.plist
    if [[ -f $zt_plist ]] && ! pgrep -x zerotier-one > /dev/null 2>&1; then
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: sudo launchctl load -w $zt_plist"
        else
            sudo launchctl load -w $zt_plist > /dev/null 2>&1 || true
        fi
    fi
fi

if (( ! ${+commands[zerotier-cli]} )); then
    print "ZeroTier: zerotier-cli still not on PATH, skipping join"
    return 0
fi

# zerotier-cli requires root to talk to the local service socket.
local joined_raw
if (( DEPLOY_DRY_RUN )); then
    joined_raw=""
else
    joined_raw=$(sudo zerotier-cli -j listnetworks 2>/dev/null) || joined_raw=""
fi

local network_id
for network_id in $zt_networks; do
    if [[ $joined_raw == *\"$network_id\"* ]]; then
        continue
    fi
    print "ZeroTier: joining network $network_id..."
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would: sudo zerotier-cli join $network_id"
    else
        if sudo zerotier-cli join $network_id > /dev/null 2>&1; then
            print "  ...done (controller must authorize this node before traffic flows)"
        else
            print "  ...failed to join $network_id"
        fi
    fi
done
