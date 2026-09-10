# codexbar-serve: install the CodexBar plan-quota collector (LLM usage HTTP
# API) as a LaunchAgent, bound to this Mac's Tailscale address. Installs the
# com.github.ctaylor.codexbar-serve agent running scripts/codexbar-serve.
#
# Activated ONLY on macOS hosts listed in configs/codexbar/collectors.conf.
# Non-listed Macs (and all non-macOS hosts) skip silently — same host-gate
# shape as 76_smb_mounts.zsh, which this fragment is modelled on.
#
# Why macOS: CodexBar's cookie-based sources (claude.ai / chatgpt.com browser
# sessions) exist only here, and the CLI-probe fallback headless hosts are
# stuck with cannot refresh its OAuth tokens. The systemd twin on ceres is
# retired; ceres keeps the cue engine, ntfy and the Caddy ingress, which now
# point at this collector over the tailnet. Runbook: ~/.local/agents/docs/
# llm-quota.md (agents repo).
#
# No root anywhere: everything lands in $HOME (state dir, LaunchAgent, Logs).
# Secrets (dashboard token, z.ai API key) do not ride with deploy — the token
# is generated here once and mirrored TO ceres by hand (the caddy env sync
# there reads the mirrored file); the z.ai key is copied FROM the previous
# collector. Both one-liners are printed when needed below.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

collectors_conf=$SCRIPT_DIR/configs/codexbar/collectors.conf
if [[ ! -r $collectors_conf ]]; then
    printf '%s\n' "codexbar-serve: $collectors_conf not found, skipping"
    return 0
fi

cxb_self=
cxb_self=$(scutil --get LocalHostName 2>/dev/null) || cxb_self=$(hostname -s 2>/dev/null) || cxb_self=""
if [[ -z $cxb_self ]]; then
    printf '%s\n' "codexbar-serve: could not determine local hostname, skipping"
    return 0
fi

# First field of each non-comment row is the collector hostname. The
# while-read replaces zsh's ${(@f)…} line-split; awk drops empty lines.
cxb_hosts=()
while IFS= read -r _cxb_host; do
    [[ -n $_cxb_host ]] && cxb_hosts+=("$_cxb_host")
done < <(awk '{ sub(/#.*$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") } NF > 0 { print $1 }' $collectors_conf)

cxb_host= cxb_listed=0
for cxb_host in "${cxb_hosts[@]}"; do
    [[ $cxb_host == $cxb_self ]] && cxb_listed=1
done

if (( ! cxb_listed )); then
    printf '%s\n' "codexbar-serve: $cxb_self not in collectors.conf, skipping setup"
    return 0
fi

printf '%s\n' "Setting up codexbar-serve on $cxb_self..."

cxb_script=$SCRIPT_DIR/scripts/codexbar-serve
if [[ ! -x $cxb_script ]]; then
    printf '%s\n' "  ...$cxb_script missing or not executable, skipping"
    return 0
fi

cxb_plist_template=$SCRIPT_DIR/configs/codexbar/com.github.ctaylor.codexbar-serve.plist
cxb_plist_target=$HOME/Library/LaunchAgents/com.github.ctaylor.codexbar-serve.plist
if [[ ! -f $cxb_plist_template ]]; then
    printf '%s\n' "  ...plist template $cxb_plist_template missing, skipping"
    return 0
fi

# --- dashboard token + env file -------------------------------------------
# Same layout setup-llm-quota.sh established on ceres: the token gates
# /dashboard/v1/snapshot everywhere and /usage + /cost on the non-loopback
# bind; the env file keeps it out of argv (CodexBar's own docs warn
# --dashboard-token leaks via ps) and out of launchd's plist.
cxb_state=$HOME/.local/state/codexbar
cxb_token_generated=0
if [[ $DEPLOY_DRY_RUN == 0 ]]; then
    mkdir -p -m 700 $cxb_state $HOME/Library/Logs
    if [[ ! -s $cxb_state/dashboard-token ]]; then
        ( umask 077; openssl rand -hex 32 > $cxb_state/dashboard-token )
        cxb_token_generated=1
    fi
    # Compare the token VALUE (sed-extracted), not raw file bytes: the env
    # file's trailing newline makes byte compares fail every deploy.
    cxb_env_expected=$(cat $cxb_state/dashboard-token)
    cxb_env_current=$(sed -n 's/^CODEXBAR_DASHBOARD_TOKEN=//p' $cxb_state/env 2>/dev/null)
    if [[ "$cxb_env_current" != "$cxb_env_expected" ]]; then
        ( umask 077; printf 'CODEXBAR_DASHBOARD_TOKEN=%s\n' "$cxb_env_expected" > $cxb_state/env )
    fi
fi
if (( cxb_token_generated )); then
    printf '%s\n' "  ...generated a NEW dashboard token ($cxb_state/dashboard-token)"
    printf '%s\n' "     ceres must mirror it before the ingress can auth; run:"
    printf '%s\n' "       ssh ceres 'install -m600 /dev/stdin ~/.local/state/codexbar/dashboard-token' \\"
    printf '%s\n' "           < $cxb_state/dashboard-token"
    printf '%s\n' "     then sudo sh ~/.local/dotfiles/scripts/setup-caddy-usage-site.sh (on ceres)"
fi

# --- providers --------------------------------------------------------------
# Providers are opt-in and default to codex only; enable the set the cue
# engine expects (zai needs its API key copied from the previous collector —
# deploy does not move secrets). Real runs only: `config enable` writes
# ~/.config/codexbar/config.json, and the dry-run legs must stay side-effect
# free.
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: ensure providers codex+claude enabled (zai key is copy-by-hand)"
    have codexbar || printf '%s\n' "  [dry-run] ...codexbar cask not installed here"
elif have codexbar; then
    codexbar config enable --provider codex  > /dev/null 2>&1 || \
        printf '%s\n' "  ...warning: could not enable provider codex"
    codexbar config enable --provider claude > /dev/null 2>&1 || \
        printf '%s\n' "  ...warning: could not enable provider claude"
    if have jq && ! codexbar config providers --json 2>/dev/null \
            | jq -e '.[]|select(.provider=="zai" and .enabled)' > /dev/null 2>&1; then
        printf '%s\n' "  ...z.ai not enabled; copy the key from the previous collector:"
        printf '%s\n' "       ssh ceres cat '~/.config/codexbar/config.json' >/tmp/cb-ceres.json"
        printf '%s\n' "       # extract the zai apiKey, then:"
        printf '%s\n' "       codexbar config set-api-key --provider zai --stdin"
    fi
else
    printf '%s\n' "  ...codexbar binary not found — install the cask (75_brew_setup) first"
    return 0
fi

# --- LaunchAgent ------------------------------------------------------------
cxb_plist_rendered=
cxb_plist_rendered=$(awk -v home="$HOME" -v script="$cxb_script" '
    { gsub(/@HOME@/, home); gsub(/@SCRIPT@/, script); print }
' $cxb_plist_template)

cxb_needs_write=1
if [[ -f $cxb_plist_target ]]; then
    if [[ "$cxb_plist_rendered" == "$(cat $cxb_plist_target)" ]]; then
        cxb_needs_write=0
    fi
fi

if (( cxb_needs_write )); then
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: render plist -> $cxb_plist_target"
    else
        mkdir -p $HOME/Library/LaunchAgents
        printf '%s\n' "$cxb_plist_rendered" > $cxb_plist_target
        printf '%s\n' "  ...rendered $cxb_plist_target"
    fi
fi

# Bootstrap (or reload on plist change) the LaunchAgent — modern domain-style
# API; `launchctl load` is deprecated on macOS 11+.
cxb_label=com.github.ctaylor.codexbar-serve
cxb_domain=gui/$(id -u)

cxb_loaded=0
if launchctl print "$cxb_domain/$cxb_label" > /dev/null 2>&1; then
    cxb_loaded=1
fi

if (( DEPLOY_DRY_RUN )); then
    if (( cxb_loaded )); then
        printf '%s\n' "  [dry-run] would: launchctl bootout + bootstrap (reload)"
    else
        printf '%s\n' "  [dry-run] would: launchctl bootstrap $cxb_domain $cxb_plist_target"
    fi
    return 0
fi

if (( cxb_needs_write && cxb_loaded )); then
    launchctl bootout "$cxb_domain/$cxb_label" > /dev/null 2>&1 || true
    cxb_loaded=0
fi

if (( ! cxb_loaded )); then
    if launchctl bootstrap "$cxb_domain" "$cxb_plist_target" > /dev/null 2>&1; then
        printf '%s\n' "  ...launchd agent $cxb_label loaded"
    else
        printf '%s\n' "  ...launchctl bootstrap failed (already loaded? rerun with --upgrade to refresh)"
    fi
elif $upgrade_mode; then
    # Sparkle swaps the CLI underneath a running collector; kickstart is how
    # the new binary ever gets picked up.
    launchctl kickstart -k "$cxb_domain/$cxb_label" > /dev/null 2>&1 || true
    printf '%s\n' "  ...launchd agent $cxb_label kickstarted"
fi
