#!/usr/bin/env bash
# setup-caddy-usage-site.sh — publish the CodexBar quota collector as
# https://usage.wedrifid.dev, tailnet-only. Idempotent; safe to re-run.
#
# Follows the workflow in docs/caddy-ingress.md: configs/caddy/Caddyfile is the
# tracked source of truth, validated, backed up, then installed to /etc and
# reloaded. The usage.wedrifid.dev block already lives in that tracked file.
#
# Mirrors immich.wedrifid.dev: grey-cloud (DNS-only) A record straight at
# ceres's Tailscale IP. DNS-01 is mandatory because Let's Encrypt cannot reach
# 100.64.0.0/10 (CGNAT). The DNS record is NOT an access control -- Caddy binds
# *:443 and ceres has a public IP, so the site block carries a remote_ip guard.
# That guard is the actual boundary.
#
# Run as root (the token lives in /etc/caddy/env, 0600 caddy:caddy -- you never
# handle it):  sudo bash ~/.local/dotfiles/scripts/setup-caddy-usage-site.sh

set -euo pipefail

FQDN="usage.wedrifid.dev"
ZONE="wedrifid.dev"
TS_IP="100.82.17.115"
TRACKED="${TRACKED:-/home/ctaylor/.local/dotfiles/configs/caddy/Caddyfile}"
CADDYFILE=/etc/caddy/Caddyfile
CADDY_ENV=/etc/caddy/env
CADDY_BIN=/usr/local/bin/caddy

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required." >&2; exit 1; }
[ -f "$TRACKED" ] || { echo "ERROR: tracked Caddyfile missing: $TRACKED" >&2; exit 1; }
grep -q "^$FQDN {" "$TRACKED" || {
  echo "ERROR: $TRACKED has no $FQDN block." >&2; exit 1; }

# NOTE: a second token can also edit wedrifid.dev DNS -- hart's wiki-MCP
# provisioner ("hart-wiki-mcp-provisioner", minted 2026-08-16, Zone DNS Edit on
# wedrifid.dev), documented in hart/docs/handover-home-ip-drift.md. It is
# user-readable, so the DNS half of this setup does not strictly need root.
TOKEN=$(sed -n 's/^CF_WEDRIFID_TOKEN=//p' "$CADDY_ENV" | tr -d '"'"'"'')
[ -n "$TOKEN" ] || { echo "ERROR: CF_WEDRIFID_TOKEN not in $CADDY_ENV" >&2; exit 1; }

api() { curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }

# --- 1. DNS: grey-cloud A record -------------------------------------------
ZONE_ID=$(api "https://api.cloudflare.com/client/v4/zones?name=$ZONE" | jq -r '.result[0].id // empty')
[ -n "$ZONE_ID" ] || { echo "ERROR: token cannot see zone $ZONE" >&2; exit 1; }

EXISTING=$(api "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FQDN")
REC_ID=$(printf '%s' "$EXISTING" | jq -r '.result[0].id // empty')
REC_IP=$(printf '%s' "$EXISTING" | jq -r '.result[0].content // empty')
REC_PROXIED=$(printf '%s' "$EXISTING" | jq -r '.result[0].proxied // empty')

BODY=$(jq -nc --arg n "$FQDN" --arg c "$TS_IP" \
  '{type:"A",name:$n,content:$c,ttl:1,proxied:false,
    comment:"CodexBar LLM quota dashboard - tailnet-only, grey cloud"}')

if [ -z "$REC_ID" ]; then
  api -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -d "$BODY" \
    | jq -e '.success' >/dev/null && echo "DNS: created $FQDN -> $TS_IP (grey cloud)"
elif [ "$REC_IP" != "$TS_IP" ] || [ "$REC_PROXIED" != "false" ]; then
  api -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$REC_ID" -d "$BODY" \
    | jq -e '.success' >/dev/null \
    && echo "DNS: corrected $FQDN (was $REC_IP, proxied=$REC_PROXIED)"
else
  echo "DNS: $FQDN already correct ($TS_IP, grey cloud) — unchanged"
fi

# --- 2. Caddyfile: validate BEFORE installing -------------------------------
# caddy resolves {env.*} at validate time and the cloudflare module rejects an
# empty token, so validation without /etc/caddy/env always fails spuriously.
set -a
. "$CADDY_ENV"
set +a

if cmp -s "$TRACKED" "$CADDYFILE"; then
  echo "Caddy: /etc/caddy/Caddyfile already matches tracked file — unchanged"
else
  if ! "$CADDY_BIN" validate --config "$TRACKED" --adapter caddyfile >/tmp/caddy-validate.log 2>&1; then
    echo "ERROR: tracked Caddyfile does not validate — nothing installed." >&2
    tail -5 /tmp/caddy-validate.log >&2
    exit 1
  fi
  echo "Caddy: tracked file validates"
  BACKUP="$CADDYFILE.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CADDYFILE" "$BACKUP"
  install -m 644 -o root -g root "$TRACKED" "$CADDYFILE"
  echo "Caddy: installed (previous saved to $BACKUP)"
  systemctl reload caddy
  echo "Caddy: reloaded"
fi

# --- 3. Verify --------------------------------------------------------------
echo "Waiting for cert issuance (DNS-01 can take ~30-60s on first request)..."
for _ in $(seq 1 24); do
  if body=$(curl -sS -m 10 "https://$FQDN/health" 2>/dev/null) && [ -n "$body" ]; then
    echo "OK: https://$FQDN/health -> $body"
    echo
    echo "Sites served:"
    grep -oE '^[a-z0-9*.-]+\.[a-z]+ \{' "$CADDYFILE" | sed 's/ {//;s/^/  /'
    exit 0
  fi
  sleep 5
done
echo "NOTE: not answering yet. Check: journalctl -u caddy -n 40 --no-pager"
