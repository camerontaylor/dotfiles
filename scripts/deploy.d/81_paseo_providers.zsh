# paseo agent providers: gjc (Gajae Code) + claude-zai (Claude Code on Z.AI GLM),
# plus the gjc-backed "GLM-5.3 Flash" agent profile.
#
# ~/.paseo/config.json is app-owned and machine-specific (paseo rewrites it;
# it holds daemon.hostnames, a per-machine auth.password hash, and UI-set
# profiles), so this MERGES the repo's keys in rather than symlinking a file
# over it -- same reasoning as 78_karabiner.zsh. The merge lives in
# scripts/paseo-providers.py; configs/ai/paseo/providers.json is the template.
#
# The Z.AI token is NOT in the repo (which is public). paseo passes provider env
# to the agent verbatim and expands nothing, so the token must be literal in
# config.json; the merge substitutes it from this box's own ~/.gjc/agent/.env,
# rendered from ~/.local/secrets by 65_secrets.zsh. Hence the ordering: after
# 65 (token), 70 (gjc binary) and 75 (paseo.app on macOS).
#
# The script prints changed/unchanged/skip and never prints the token; reload
# only on an actual change, so a routine deploy does not churn a live daemon.

paseo_tmpl=$SCRIPT_DIR/configs/ai/paseo/providers.json
paseo_merge=$SCRIPT_DIR/scripts/paseo-providers.py

if [[ ! -f $paseo_tmpl || ! -f $paseo_merge ]]; then
    return 0
fi

# Gate on the config existing rather than on the `paseo` command: on macOS the
# CLI is a symlink into Paseo.app that a headless box will not have, but any box
# that has ever run the daemon has the config.
if [[ ! -f $HOME/.paseo/config.json ]]; then
    return 0
fi

if ! have python3; then
    printf '%s\n' "paseo providers: no python3 on PATH (mise.toml pins python 3); skipping"
    return 0
fi

printf '%s\n' "Merging paseo agent providers (gjc, claude-zai)..."

paseo_result=
if (( DEPLOY_DRY_RUN )); then
    paseo_result=$(python3 $paseo_merge $paseo_tmpl --dry-run 2>&1)
else
    paseo_result=$(python3 $paseo_merge $paseo_tmpl 2>&1)
fi

case $paseo_result in
    changed)
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would update ~/.paseo/config.json and reload the daemon"
        else
            printf '%s\n' "  ...updated ~/.paseo/config.json"
            # agents.providers and daemon.agentProfiles are both in paseo's
            # RELOADABLE_PATHS, so this applies without restarting the daemon
            # and without interrupting any running agent.
            if have paseo && paseo daemon reload > /dev/null 2>&1; then
                printf '%s\n' "  ...daemon reloaded"
            else
                printf '%s\n' "  ...could not reload the daemon; run 'paseo daemon reload' when it is up"
            fi
        fi
        ;;
    unchanged)
        printf '%s\n' "  ...already current"
        ;;
    skip:*)
        printf '%s\n' "  ...${paseo_result#skip: }"
        ;;
    *)
        printf '%s\n' "  ...merge failed: $paseo_result"
        ;;
esac
