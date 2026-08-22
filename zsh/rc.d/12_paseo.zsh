# Paseo — self-hosted orchestrator for Claude Code / Codex / Copilot / OpenCode
# / Pi agents (github.com/getpaseo/paseo). Each box runs its own daemon on
# :6767; clients (phone app, desktop app, this CLI) connect to whichever box
# should do the work. Per-host install/config: scripts/setup-paseo.sh,
# runbook: docs/paseo.md.
#
# Auth: the CLI reads $PASEO_PASSWORD whenever the target host carries no
# `password=` query of its own, so the encrypted zsh/env.d/90_secrets.zsh export
# is all every helper below needs. A password spelled into a tcp:// URI still
# wins, which is how you'd reach a box that has a different one.
#
# Targeting: $PASEO_HOST selects the daemon for ALL subcommands. Do not reach
# for a bare `paseo --host …` — in the stable CLI (0.4.0) --host is a
# per-subcommand option, not a root one, so `paseo --host X ls` fails with
# "unknown option '--host'". The env var has no such ordering trap.

typeset -g _PASEO_PORT="${PASEO_PORT:-6767}"
# Fleet daemons worth naming. Reached by their .webfront.app names, which
# resolve to the boxes' Tailscale 100.x addresses.
typeset -ga _PASEO_HOSTS=(ceres saturn neptune)

# On Linux the CLI is a mise tool (npm:@getpaseo/cli@latest), not an npm global
# and not a cask, so there is no `paseo` on PATH: the bare mise shim errors
# "No version is set for shim" until the tool is activated in a mise config,
# and ~/.config/mise/config.toml is a symlink into this repo — activating there
# would dirty the working tree. Same reasoning as setup-t3.sh; resolve it with
# `mise exec` instead. On macOS the Paseo.app cask already provides a real
# `paseo` binary, so this never defines anything.
if (( ! ${+commands[paseo]} )) && (( ${+commands[mise]} )); then
    paseo() {
        emulate -L zsh
        mise exec npm:@getpaseo/cli@latest -- paseo "$@"
    }
fi

# paseo-at <host> [args...] — run a paseo command against another box's daemon.
#   paseo-at ceres ls
#   paseo-at saturn run --provider claude/opus-4.6 "fix the failing test"
paseo-at() {
    emulate -L zsh
    local host="${1:?usage: paseo-at <host> [paseo args...]}"
    shift
    PASEO_HOST="${host}.webfront.app:${_PASEO_PORT}" paseo "$@"
}

paseo-ceres()   { paseo-at ceres "$@" }
paseo-saturn()  { paseo-at saturn "$@" }
paseo-neptune() { paseo-at neptune "$@" }

# paseo-hosts — which fleet daemons are up? /api/health is the one endpoint
# exempt from password auth, so this needs no credentials.
paseo-hosts() {
    emulate -L zsh
    local host url
    for host in $_PASEO_HOSTS; do
        url="http://${host}.webfront.app:${_PASEO_PORT}/api/health"
        if curl -sf --max-time 3 "$url" > /dev/null 2>&1; then
            print -r -- "  up    ${host}.webfront.app:${_PASEO_PORT}"
        else
            print -r -- "  down  ${host}.webfront.app:${_PASEO_PORT}"
        fi
    done
    if [[ -z ${PASEO_PASSWORD:-} ]]; then
        print -u2 -- "note: \$PASEO_PASSWORD is unset — everything but health will 401."
    fi
}
