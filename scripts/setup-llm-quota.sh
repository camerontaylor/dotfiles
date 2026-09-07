#!/usr/bin/env bash
# setup-llm-quota.sh — LLM plan-quota collector, pacing cues and ntfy delivery.
#
# Idempotent, user-space, no sudo. Provisions everything except the Caddy sites
# and DNS, which are scripts/setup-caddy-usage-site.sh (root) — see
# docs/llm-quota.md.
#
#   sh ~/.local/dotfiles/scripts/setup-llm-quota.sh
#
# Installs to ~/.local/share, config to ~/.config, secrets to ~/.local/state.
# Units are symlinked by scripts/deploy.d/20_symlinks.zsh; this script only
# enables them, so running deploy first is fine but not required.

set -euo pipefail

CODEXBAR_VERSION="${CODEXBAR_VERSION:-0.56.4}"
NTFY_VERSION="${NTFY_VERSION:-2.28.0}"
DOTFILES="${DOTFILES:-$HOME/.local/dotfiles}"
UNITS_SRC="$DOTFILES/configs/ai/codexbar"

command -v gh >/dev/null || { echo "ERROR: gh required (release downloads)." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required." >&2; exit 1; }

say() { printf '  %s\n' "$*"; }

# --- CodexBar: collector -----------------------------------------------------
# NOT a single binary: CodexBar_CodexBarCore.bundle holds the per-provider JS
# plugins and must sit beside the executable, so install the whole tree.
if [ "$(cat "$HOME/.local/share/codexbar/VERSION" 2>/dev/null || true)" = "$CODEXBAR_VERSION" ]; then
  say "codexbar $CODEXBAR_VERSION already installed"
else
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  tar="CodexBarCLI-v$CODEXBAR_VERSION-linux-x86_64.tar.gz"
  gh release download "v$CODEXBAR_VERSION" --repo steipete/CodexBar -p "$tar" -p "$tar.sha256" -D "$tmp" >/dev/null
  ( cd "$tmp" && sha256sum -c "$tar.sha256" >/dev/null ) || { echo "ERROR: checksum mismatch" >&2; exit 1; }
  ( cd "$tmp" && tar xzf "$tar" )
  mkdir -p "$HOME/.local/share/codexbar"
  cp -a "$tmp"/CodexBarCLI "$tmp"/codexbar "$tmp"/VERSION "$tmp"/CodexBar_CodexBarCore.bundle \
        "$HOME/.local/share/codexbar/"
  ln -sfn "$HOME/.local/share/codexbar/codexbar" "$HOME/.local/bin/codexbar"
  say "codexbar $CODEXBAR_VERSION installed (sha256 verified)"
fi

# --- CodexBar: providers -----------------------------------------------------
# Providers are opt-in and default to codex only; without this the collector
# serves a single provider and gives no hint that the others are missing.
export PATH="$HOME/.local/bin:$PATH"
codexbar config enable --provider claude >/dev/null
codexbar config enable --provider codex  >/dev/null
if ! codexbar config providers --json 2>/dev/null | jq -e '.[]|select(.provider=="zai" and .enabled)' >/dev/null 2>&1; then
  zk=$(sed -n 's/^Z\?_\?AI_API_KEY=//p' "$HOME/.openclaw/.env" 2>/dev/null | head -1 | tr -d '"'"'"'')
  [ -n "$zk" ] || zk="${ZAI_API_KEY:-}"
  if [ -n "$zk" ]; then
    printf '%s' "$zk" | codexbar config set-api-key --provider zai --stdin >/dev/null
  else
    say "WARNING: no z.ai key found; run: codexbar config set-api-key --provider zai --stdin"
  fi
fi
say "providers enabled: $(codexbar config providers --json 2>/dev/null | jq -r '[.[]|select(.enabled)|.provider]|join(", ")' 2>/dev/null || echo '?')"

# --- CodexBar: dashboard token ----------------------------------------------
install -d -m 700 "$HOME/.local/state/codexbar" "$HOME/.local/state/codexbar-alerts"
if [ ! -s "$HOME/.local/state/codexbar/dashboard-token" ]; then
  ( umask 077; openssl rand -hex 32 > "$HOME/.local/state/codexbar/dashboard-token" )
  say "generated dashboard token"
fi
( umask 077
  printf 'CODEXBAR_DASHBOARD_TOKEN=%s\n' "$(cat "$HOME/.local/state/codexbar/dashboard-token")" \
    > "$HOME/.local/state/codexbar/env" )

# --- ntfy --------------------------------------------------------------------
if [ "$("$HOME/.local/share/ntfy/ntfy" --version 2>/dev/null | awk '{print $3}')" = "$NTFY_VERSION" ]; then
  say "ntfy $NTFY_VERSION already installed"
else
  tmp2=$(mktemp -d)
  gh release download "v$NTFY_VERSION" --repo binwiederhier/ntfy \
     -p "ntfy_${NTFY_VERSION}_linux_amd64.tar.gz" -D "$tmp2" >/dev/null
  ( cd "$tmp2" && tar xzf "ntfy_${NTFY_VERSION}_linux_amd64.tar.gz" )
  install -D -m 755 "$(find "$tmp2" -name ntfy -type f -perm -u+x | head -1)" "$HOME/.local/share/ntfy/ntfy"
  ln -sfn "$HOME/.local/share/ntfy/ntfy" "$HOME/.local/bin/ntfy"
  rm -rf "$tmp2"
  say "ntfy $NTFY_VERSION installed"
fi
install -d -m 700 "$HOME/.config/ntfy" "$HOME/.local/share/ntfy/cache" "$HOME/.local/share/ntfy/attachments"
if [ ! -f "$HOME/.config/ntfy/server.yml" ]; then
  cat > "$HOME/.config/ntfy/server.yml" <<EOF
listen-http: "127.0.0.1:2586"
base-url: "https://ntfy.wedrifid.dev"
cache-file: "$HOME/.local/share/ntfy/cache/cache.db"
cache-duration: "24h"
attachment-cache-dir: "$HOME/.local/share/ntfy/attachments"
attachment-expiry-duration: "24h"
behind-proxy: true
EOF
  chmod 600 "$HOME/.config/ntfy/server.yml"
  say "wrote ntfy server.yml"
fi

# --- units -------------------------------------------------------------------
mkdir -p "$HOME/.config/systemd/user"
for u in codexbar-serve.service ntfy-server.service codexbar-quota-cues.service codexbar-quota-cues.timer; do
  ln -sfn "$UNITS_SRC/$u" "$HOME/.config/systemd/user/$u"
done
systemctl --user daemon-reload
systemctl --user enable --now codexbar-serve.service ntfy-server.service >/dev/null
systemctl --user enable --now codexbar-quota-cues.timer >/dev/null
say "units enabled"

# --- verify ------------------------------------------------------------------
sleep 3
printf '  collector: '; curl -sS -m 20 http://127.0.0.1:8791/health || echo FAILED
printf '\n  ntfy:      '; curl -sS -m 10 http://127.0.0.1:2586/v1/health || echo FAILED
echo
printf '  providers: '
curl -sS -m 120 'http://127.0.0.1:8791/usage' | jq -r '[.[].provider]|join(", ")' || echo FAILED
echo
echo "Next (root, once): sh $DOTFILES/scripts/setup-caddy-usage-site.sh"
echo "Then subscribe the ntfy Android app to https://ntfy.wedrifid.dev topic 'quota'."
