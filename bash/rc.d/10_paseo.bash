# Paseo fleet helpers — bash twin of zsh/rc.d/12_paseo.zsh (see that file
# for the fleet/daemon docs). Divergences: `${+commands[x]}` → `command -v`,
# `print` → `printf`, no `emulate -L zsh` (nothing to contain in bash).
_PASEO_PORT="${PASEO_PORT:-6767}"

# Detect the mise SHIM by path, not by absence — the broken shim sits on
# PATH and errors "No version is set" (same trap the zsh twin documents).
if command -v mise >/dev/null 2>&1; then
    _paseo_shim_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
    if ! command -v paseo >/dev/null 2>&1 || [ "$(command -v paseo)" = "$_paseo_shim_dir/paseo" ]; then
        paseo() {
            mise exec npm:@getpaseo/cli@latest -- paseo "$@"
        }
    fi
    unset _paseo_shim_dir
fi

# paseo-at <host> [args...] — run a paseo command against another box's daemon.
paseo-at() {
    local host="${1:?usage: paseo-at <host> [paseo args...]}"
    shift
    PASEO_HOST="${host}.webfront.app:${_PASEO_PORT}" paseo "$@"
}

paseo-ceres()   { paseo-at ceres "$@"; }
paseo-saturn()  { paseo-at saturn "$@"; }
paseo-neptune() { paseo-at neptune "$@"; }

# Which fleet daemons are up? /api/health is the one endpoint exempt from
# password auth.
paseo-hosts() {
    local host url
    for host in ceres saturn neptune; do
        url="http://${host}.webfront.app:${_PASEO_PORT}/api/health"
        if curl -sf --max-time 3 "$url" > /dev/null 2>&1; then
            printf '  up    %s.webfront.app:%s\n' "$host" "$_PASEO_PORT"
        else
            printf '  down  %s.webfront.app:%s\n' "$host" "$_PASEO_PORT"
        fi
    done
    if [ -z "${PASEO_PASSWORD:-}" ]; then
        printf '%s\n' "note: \$PASEO_PASSWORD is unset — everything but health will 401." >&2
    fi
}
