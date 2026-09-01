# obs: macOS-only two-track audio recording setup (OBS Studio).
# Track 1 = mic, Track 2 = desktop/app audio via ScreenCaptureKit.
#
# OPT-IN, not default: activated ONLY on macOS hosts whose short hostname
# appears in configs/obs/hosts.conf. Every other Mac (and all non-macOS hosts)
# skips silently. This mirrors the wake-peers gate in 76_wake_peers.zsh.
#
# Unlike read-only configs (aerospace.toml, sway/config) that are symlinked in
# 20_symlinks.zsh, OBS continuously writes back to its scene/profile files, so
# a repo symlink would spew machine-specific state into git. The config is
# therefore SEEDED (copy-if-absent) by scripts/configure-obs.py instead.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

obs_hosts=$SCRIPT_DIR/configs/obs/hosts.conf
if [[ ! -r $obs_hosts ]]; then
    printf '%s\n' "obs: $obs_hosts not found, skipping"
    return 0
fi

# Canonical short hostname; falls back to BSD hostname -s.
self=
self=$(scutil --get LocalHostName 2>/dev/null) || self=$(hostname -s 2>/dev/null) || self=""
if [[ -z $self ]]; then
    printf '%s\n' "obs: could not determine local hostname, skipping"
    return 0
fi

# Strip comments/blank lines from hosts.conf into an array (BSD awk clean).
obs_enabled=()
obs_enabled=("${(@f)$(awk '{ sub(/#.*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") } NF > 0' $obs_hosts)}")

host= self_enabled=0
for host in $obs_enabled; do
    [[ $host == $self ]] && self_enabled=1
done

if (( ! self_enabled )); then
    printf '%s\n' "obs: $self not in configs/obs/hosts.conf, skipping setup"
    return 0
fi

printf '%s\n' "Setting up OBS two-track recording on $self..."

# 1. Install the OBS cask (official homebrew/cask, no tap trust needed).
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: brew_cask_install_or_upgrade obs"
else
    brew_cask_install_or_upgrade obs || {
        printf '%s\n' "  ...OBS install failed, skipping config seed"
        return 0
    }
fi

# 2. Seed the tracked two-track config (non-destructive; honors DEPLOY_DRY_RUN
#    itself). Use /usr/bin/python3 (stable path, no mise dependency) like
#    configure_iterm2_profile does.
obs_dir="$HOME/Library/Application Support/obs-studio"
if [[ ! -x /usr/bin/python3 ]]; then
    printf '%s\n' "  ...python3 unavailable, skipping OBS config seed"
    return 0
fi
/usr/bin/python3 "$SCRIPT_DIR/scripts/configure-obs.py" \
    "$SCRIPT_DIR/configs/obs" "$obs_dir"
