#!/usr/bin/env bash
# render-caddy-env.sh — compose /etc/caddy/env from the secrets store.
#
# WHY THIS EXISTS
# ---------------
# /etc/caddy/env holds the Cloudflare DNS-01 credentials that issue certs for
# every *.wedrifid.dev vhost, plus the CodexBar dashboard token. Until now it
# was the ORIGIN of those values, not a copy of them: scripts/setup-caddy-usage-
# site.sh reads CF_WEDRIFID_TOKEN *out* of it, and nothing could put it back.
# Losing the file meant re-minting a Cloudflare token before any cert could
# renew. The values were backed up to the store on 2026-09-21 (secrets 453759c),
# which closed the loss risk but not the restore path — there was still no way
# to turn the ciphertext back into this file. This script is that way, and it
# reverses the direction of truth to match the store's governing principle:
# ciphertext is canonical, plaintext is a derived artifact.
#
# WHY IT IS SEPARATE FROM secrets-render.zsh
# ------------------------------------------
# Every row in that renderer targets a USER-owned path ($XDG_STATE_HOME,
# $XDG_CONFIG_HOME, ~/repos/deploy, $DOTFILES). Not one writes under /etc, and
# that is structural, not an oversight: the renderer runs unattended as part of
# the normal deploy, and H7 forbids sudo in anything that runs again without
# someone looking. /etc/caddy/env is 0600 caddy:caddy, so placing it is
# necessarily privileged and therefore necessarily a human step — exactly like
# /etc/caddy/Caddyfile, whose bytes dotfiles owns and whose installation is
# scripts/setup-caddy.sh. This script is the same seam for the env file.
#
# H7 COMPLIANCE: run by a person, deliberately, once per change. NEVER wire it
# into a timer, a hook, deploy, or converge-check-run.
#
#   sudo bash ~/.local/dotfiles/scripts/render-caddy-env.sh --check     # drift only
#   sudo bash ~/.local/dotfiles/scripts/render-caddy-env.sh --dry-run
#   sudo bash ~/.local/dotfiles/scripts/render-caddy-env.sh
#
# No value is ever printed, in any mode — only variable NAMES and a verdict.

set -euo pipefail

CADDY_ENV=/etc/caddy/env
CADDYFILE=/etc/caddy/Caddyfile
MODE=apply
RESTART=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE=check ;;
    --dry-run) MODE=dry ;;
    # Applying an env change needs a RESTART, not a reload: EnvironmentFile= is
    # read at unit start. That is a SURFACE action (it interrupts TLS
    # termination for every vhost), so it is opt-in and never implied.
    --restart) RESTART=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root — $CADDY_ENV is 0600 caddy:caddy." >&2
  echo "       sudo bash $0 ${MODE:+--$MODE}" >&2
  exit 2
fi

# The invoking human's home, not root's: the rendered secrets are theirs.
RUN_USER="${SUDO_USER:-}"
[ -n "$RUN_USER" ] || { echo "ERROR: SUDO_USER unset — run via sudo, not as a root login." >&2; exit 2; }
RUN_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
[ -n "$RUN_HOME" ] || { echo "ERROR: no home directory for $RUN_USER" >&2; exit 2; }

STATE_HOME="${XDG_STATE_HOME:-$RUN_HOME/.local/state}"
CF_SRC="$STATE_HOME/secrets/zsh/91_cloudflare_secrets.zsh"
CB_SRC="$STATE_HOME/codexbar/env"

for f in "$CF_SRC" "$CB_SRC"; do
  [ -r "$f" ] && continue
  echo "ERROR: $f is missing." >&2
  echo "       Render it first, AS $RUN_USER (not root):" >&2
  echo "         zsh $RUN_HOME/.local/dotfiles/scripts/secrets-render.zsh" >&2
  exit 2
done

# Which variables does the live Caddyfile actually need? Deriving the set from
# {env.*} references keeps this script correct when a vhost adds a new one,
# instead of silently rendering a stale list.
if [ -r "$CADDYFILE" ]; then
  REQUIRED=$(grep -oE '\{env\.[A-Za-z_][A-Za-z0-9_]*\}' "$CADDYFILE" \
             | sed 's/{env\.//; s/}//' | sort -u)
else
  REQUIRED=$'CF_API_TOKEN\nCF_WEDRIFID_TOKEN\nCODEXBAR_DASHBOARD_TOKEN'
fi

# Collect values WITHOUT sourcing: 91_cloudflare_secrets.zsh is a zsh file and
# this is bash, and sourcing secret material into this shell would expose it to
# anything that reads /proc/self/environ.
val_of() {
  local name=$1 v=
  v=$(sed -n "s/^[[:space:]]*export[[:space:]]\+${name}=//p" "$CF_SRC" | tail -1)
  [ -n "$v" ] || v=$(sed -n "s/^${name}=//p" "$CF_SRC" | tail -1)
  [ -n "$v" ] || v=$(sed -n "s/^${name}=//p" "$CB_SRC" | tail -1)
  # strip one layer of surrounding quotes
  v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
  printf '%s' "$v"
}

TMP=$(mktemp); chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT

missing=""
{
  echo "# /etc/caddy/env — rendered by dotfiles scripts/render-caddy-env.sh."
  echo "# Canonical source: the secrets store (~/.local/secrets). DO NOT hand-edit:"
  echo "# the next render overwrites it. Add the value to the store instead."
  for name in $REQUIRED; do
    v=$(val_of "$name")
    if [ -z "$v" ]; then
      missing="$missing $name"
      continue
    fi
    printf '%s=%s\n' "$name" "$v"
  done
} > "$TMP"

if [ -n "$missing" ]; then
  echo "ERROR: no value in the secrets store for:$missing" >&2
  echo "       The live Caddyfile references these as {env.*}. Add them to" >&2
  echo "       ~/.local/secrets and re-render before installing." >&2
  exit 2
fi

echo "variables composed: $(echo "$REQUIRED" | tr '\n' ' ')"

if [ -e "$CADDY_ENV" ] && cmp -s "$TMP" "$CADDY_ENV"; then
  echo "ok  $CADDY_ENV already matches the store — unchanged"
  exit 0
fi

case "$MODE" in
  check)
    echo "DRIFT  $CADDY_ENV differs from the secrets store (values not shown)"
    exit 1
    ;;
  dry)
    echo "would rewrite $CADDY_ENV (0600 caddy:caddy, inode preserved)"
    exit 0
    ;;
esac

if [ -e "$CADDY_ENV" ]; then
  # `cat >` rather than `mv`: it keeps the inode, so the existing
  # 0600 caddy:caddy ownership and mode survive without being re-applied.
  cat "$TMP" > "$CADDY_ENV"
else
  install -m 0600 -o caddy -g caddy "$TMP" "$CADDY_ENV"
fi
echo "wrote $CADDY_ENV  ($(stat -c '%A %U:%G' "$CADDY_ENV"))"

if [ "$RESTART" -eq 1 ]; then
  echo "SURFACE: restarting caddy (EnvironmentFile is read at start, not reload)"
  systemctl restart caddy && systemctl --no-pager --lines=0 status caddy | head -3
else
  echo
  echo "NOT restarted. EnvironmentFile= is read at unit START, so the new values"
  echo "are not live until you run — this interrupts TLS for every vhost:"
  echo "    sudo systemctl restart caddy"
fi
