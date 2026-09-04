#!/usr/bin/env bash
set -euo pipefail

# setup-caddy.sh - HTTPS dev proxy with wildcard certs
#
# SOURCE OF TRUTH for the Caddy config is configs/caddy/Caddyfile in this repo,
# not this script. The script INSTALLS the tracked file; it no longer generates
# one. Until 2026-08-22 it generated a three-site config inline that had
# silently diverged from the five-site config live on ceres, so re-running it
# would have deleted the telemetry.webfront.app and mcp.ceres.webfront.app
# routes without a word. Read docs/caddy-ingress.md before running this on a
# machine that is already serving, and use --dry-run first.
#
# Usage: setup-caddy.sh [--dry-run] [-y|--yes]
#
# Linux path:
#   - Installs Caddy with apt (Debian/Ubuntu) or pacman (Arch/CachyOS)
#   - Configures Caddy and Portless with systemd
#
# macOS path:
#   - Installs Caddy with Homebrew
#   - Configures Caddy and Portless with launchd LaunchDaemons
#
# Prerequisites:
#   1. Set the machine's hostname.
#   2. CF_API_TOKEN: exported by any new shell (89_secrets_loader), or
#      source "$XDG_STATE_HOME"/secrets/zsh/91_cloudflare_secrets.zsh
#   3. Install portless: mise use -g npm:portless
#   4. Create Cloudflare DNS records for {hostname}.webfront.app and wildcard.

OS=$(uname -s)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help)
      echo "Usage: setup-caddy.sh [--dry-run] [-y|--yes]"
      echo "  --dry-run  show what would change; touch nothing"
      echo "  -y         skip the 'this restarts your only ingress' prompt"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg (try --help)"
      exit 1
      ;;
  esac
done
DOMAIN="${HOSTNAME}.webfront.app"
RUN_USER=${SUDO_USER:-$(id -un)}
if [[ ! "$RUN_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: unsafe user name: $RUN_USER"
  exit 1
fi

case "$OS" in
  Linux)
    if command -v getent &>/dev/null; then
      RUN_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
    else
      RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6; exit }' /etc/passwd)
    fi
    ;;
  Darwin)
    RUN_HOME=$(dscl . -read "/Users/$RUN_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')
    ;;
  *)
    RUN_HOME=
    ;;
esac

if [[ -z "${RUN_HOME:-}" ]]; then
  echo "ERROR: cannot resolve home directory for $RUN_USER"
  exit 1
fi

CADDY_BIN=
CADDY_CONFIG_DIR=/etc/caddy
CADDYFILE_PATH=$CADDY_CONFIG_DIR/Caddyfile
CADDY_ENV_PATH=$CADDY_CONFIG_DIR/env

# Per-host override wins if present, so a second machine can carry its own
# routes without forking this script.
if [[ -f "$REPO_ROOT/configs/caddy/Caddyfile.$HOSTNAME" ]]; then
  TRACKED_CADDYFILE="$REPO_ROOT/configs/caddy/Caddyfile.$HOSTNAME"
else
  TRACKED_CADDYFILE="$REPO_ROOT/configs/caddy/Caddyfile"
fi
TRACKED_CADDY_UNIT="$REPO_ROOT/configs/caddy/caddy.service"
UNIT_CHANGED=0

# /usr/local/bin, not /usr/bin: the distro package ships no DNS-provider
# modules, so every machine here runs a custom build from the Caddy download
# API (see install_caddy_linux). /etc/systemd/system/caddy.service points at
# this path — keep the two in step.
LINUX_CADDY_BIN=/usr/local/bin/caddy
MACOS_CADDY_BIN=/usr/local/sbin/caddy-dotfiles

if [[ "$OS" == "Darwin" ]]; then
  if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_PREFIX=$(/opt/homebrew/bin/brew --prefix)
    export PATH="/opt/homebrew/bin:$PATH"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_PREFIX=$(/usr/local/bin/brew --prefix)
    export PATH="/usr/local/bin:$PATH"
  else
    BREW_PREFIX=
  fi

  if [[ -n "${BREW_PREFIX:-}" ]]; then
    CADDY_CONFIG_DIR="/Library/Application Support/Caddy"
    CADDYFILE_PATH=$CADDY_CONFIG_DIR/Caddyfile
    CADDY_ENV_PATH=$CADDY_CONFIG_DIR/env
  fi
fi

require_command() {
  local cmd=$1
  local hint=$2

  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd not found. $hint"
    exit 1
  fi
}

detect_caddy_bin() {
  case "$OS" in
    Linux) CADDY_BIN=$LINUX_CADDY_BIN ;;
    Darwin) CADDY_BIN=$MACOS_CADDY_BIN ;;
  esac
}

is_root_owned_executable() {
  local path=$1
  local owner mode group_digit other_digit

  [[ -x "$path" ]] || return 1

  case "$OS" in
    Linux)
      owner=$(stat -c '%U:%G' "$path")
      mode=$(stat -c '%a' "$path")
      [[ "$owner" == "root:root" ]] || return 1
      ;;
    Darwin)
      owner=$(/usr/bin/stat -f '%Su:%Sg' "$path")
      mode=$(/usr/bin/stat -f '%Lp' "$path")
      [[ "$owner" == "root:wheel" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  group_digit=${mode: -2:1}
  other_digit=${mode: -1}
  (( (10#$group_digit & 2) == 0 && (10#$other_digit & 2) == 0 ))
}

require_trusted_caddy_bin() {
  detect_caddy_bin
  if ! is_root_owned_executable "$CADDY_BIN"; then
    echo "ERROR: trusted Caddy binary is missing or has unsafe permissions: $CADDY_BIN"
    exit 1
  fi
}

ensure_caddy_config_dir() {
  if [[ "$OS" == "Darwin" ]]; then
    sudo install -d -o root -g wheel -m 755 "$CADDY_CONFIG_DIR"
  else
    sudo mkdir -p "$CADDY_CONFIG_DIR"
  fi
}

port_443_holder() {
  case "$OS" in
    Linux)
      sudo ss -tlnp 'sport = :443' 2>/dev/null | tail -n +2 || true
      ;;
    Darwin)
      sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | tail -n +2 || true
      ;;
  esac
}

port_holder_pid() {
  case "$OS" in
    Linux)
      grep -oP 'pid=\K[0-9]+' | head -1
      ;;
    Darwin)
      awk 'NR == 1 { print $2 }'
      ;;
  esac
}

get_lan_ip() {
  case "$OS" in
    Linux)
      hostname -I 2>/dev/null | awk '{print $1}'
      ;;
    Darwin)
      local iface
      iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
      if [[ -n "$iface" ]]; then
        ipconfig getifaddr "$iface" 2>/dev/null || true
      fi
      ;;
  esac
}

launchd_job_running() {
  local label=$1
  local port=$2
  local output

  if ! output=$(sudo launchctl print "system/$label" 2>/dev/null); then
    echo "  ERROR: $label launchd job is not loaded"
    return 1
  fi

  if ! grep -q 'state = running' <<<"$output"; then
    echo "  ERROR: $label launchd job is not running"
    echo "$output" | grep -E 'state =|last exit code =|pid =' || true
    return 1
  fi

  if ! sudo lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tail -n +2 | grep -q .; then
    echo "  ERROR: $label is not listening on TCP $port"
    return 1
  fi

  echo "  OK: $label is running and listening on TCP $port"
}

preflight() {
  if [[ -z "${CF_API_TOKEN:-}" ]]; then
    echo "ERROR: CF_API_TOKEN not set. Open a new shell, or run:"
    echo "  source \"\${XDG_STATE_HOME:-\$HOME/.local/state}\"/secrets/zsh/91_cloudflare_secrets.zsh"
    exit 1
  fi
  if [[ ! "$CF_API_TOKEN" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: CF_API_TOKEN contains unsupported characters for the service env file."
    exit 1
  fi

  require_command portless "Install with: mise use -g npm:portless"

  if [[ "$OS" == "Linux" ]]; then
    require_command ss "Install iproute2."
  elif [[ "$OS" == "Darwin" ]]; then
    require_command lsof "Install Xcode command line tools or use the system lsof."
    if [[ -z "${BREW_PREFIX:-}" ]]; then
      echo "ERROR: Homebrew not found. Install Homebrew first: https://brew.sh/"
      exit 1
    fi
  else
    echo "ERROR: Unsupported OS: $OS"
    exit 1
  fi

  local holder holder_pid holder_cmd
  holder=$(port_443_holder)
  if [[ -n "$holder" ]]; then
    holder_pid=$(echo "$holder" | port_holder_pid)
    if [[ -n "$holder_pid" ]]; then
      holder_cmd=$(ps -p "$holder_pid" -o args= 2>/dev/null || echo "unknown")
      if [[ "$holder_cmd" != *caddy* ]]; then
        echo "ERROR: Port 443 is already in use by PID $holder_pid:"
        echo "  $holder_cmd"
        echo ""
        echo "Kill it first: sudo kill $holder_pid"
        exit 1
      fi
    fi
  fi

  PORTLESS_BIN=$(command -v portless)
  echo "Machine:   $HOSTNAME"
  echo "Domain:    *.$DOMAIN"
  echo "Portless:  $PORTLESS_BIN"
  echo ""
}

# Reality on ceres (verified 2026-08-22): /usr/local/bin/caddy is a 51 MB
# root-owned custom build, not a packaged one — `pacman -Qo` knows nothing
# about it. That is deliberate: the wildcard certs need the DNS-01 challenge,
# which needs the caddy-dns/cloudflare module, which the distro packages do not
# carry. `caddy add-package` on a package-manager binary tries to replace a
# file the package manager owns; the download API is the supported path.
install_caddy_linux() {
  if [[ -x "$LINUX_CADDY_BIN" ]]; then
    echo "Caddy already installed: $("$LINUX_CADDY_BIN" version)"
    CADDY_BIN=$LINUX_CADDY_BIN
    require_trusted_caddy_bin
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *)
      echo "ERROR: unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac

  local url="https://caddyserver.com/api/download?os=linux&arch=${arch}&p=github.com/caddy-dns/cloudflare"

  if (( DRY_RUN )); then
    echo "  [dry-run] would download a custom Caddy build to $LINUX_CADDY_BIN"
    echo "  [dry-run]   $url"
    CADDY_BIN=$LINUX_CADDY_BIN
    return 0
  fi

  echo "Downloading Caddy with the caddy-dns/cloudflare module..."
  local tmp
  tmp=$(mktemp)
  if ! curl -fsSL --max-time 300 -o "$tmp" "$url"; then
    rm -f "$tmp"
    echo "ERROR: download failed: $url"
    exit 1
  fi
  chmod 755 "$tmp"
  if ! "$tmp" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
    rm -f "$tmp"
    echo "ERROR: downloaded binary lacks dns.providers.cloudflare; refusing to install."
    exit 1
  fi
  sudo install -o root -g root -m 755 "$tmp" "$LINUX_CADDY_BIN"
  rm -f "$tmp"

  # The unit runs as User=caddy; the account must exist before first start.
  if ! id caddy &>/dev/null; then
    echo "Creating the caddy system user..."
    sudo useradd --system --home-dir /var/lib/caddy --create-home \
      --shell /usr/sbin/nologin caddy
  fi

  CADDY_BIN=$LINUX_CADDY_BIN
  require_trusted_caddy_bin
}

install_caddy_macos() {
  local brew_caddy="$BREW_PREFIX/bin/caddy"

  if [[ -x "$brew_caddy" ]]; then
    echo "Caddy already installed: $("$brew_caddy" version)"
  else
    echo "Installing Caddy with Homebrew..."
    brew install caddy
  fi

  if [[ ! -x "$brew_caddy" ]]; then
    echo "ERROR: expected Homebrew Caddy at $brew_caddy"
    exit 1
  fi

  if ! [[ -x "$MACOS_CADDY_BIN" ]] || ! "$MACOS_CADDY_BIN" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
    if ! "$brew_caddy" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
      echo "Adding Cloudflare DNS plugin to Homebrew Caddy..."
      "$brew_caddy" add-package github.com/caddy-dns/cloudflare
    fi

    echo "Installing root-owned Caddy service binary..."
    sudo install -d -o root -g wheel -m 755 "$(dirname "$MACOS_CADDY_BIN")"
    sudo install -o root -g wheel -m 755 "$brew_caddy" "$MACOS_CADDY_BIN"
  fi

  CADDY_BIN=$MACOS_CADDY_BIN
  require_trusted_caddy_bin
}

install_caddy() {
  case "$OS" in
    Linux) install_caddy_linux ;;
    Darwin) install_caddy_macos ;;
  esac

  if (( DRY_RUN )) && [[ ! -x "$CADDY_BIN" ]]; then
    return 0
  fi

  require_trusted_caddy_bin

  # Hard requirement, not a nice-to-have: without this module every `tls { dns
  # cloudflare ... }` block fails to load and the whole config is rejected.
  if "$CADDY_BIN" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
    echo "Cloudflare DNS plugin present."
  else
    echo "ERROR: $CADDY_BIN has no dns.providers.cloudflare module."
    echo "       Replace it with a custom build:"
    echo "       https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/caddy-dns/cloudflare"
    exit 1
  fi
}

write_caddyfile() {
  echo "Writing $CADDYFILE_PATH for $DOMAIN..."
  ensure_caddy_config_dir
  sudo tee "$CADDYFILE_PATH" > /dev/null <<EOF
# Auto-generated by setup-caddy.sh for $HOSTNAME
# TLS termination for *.$DOMAIN via Cloudflare DNS-01 challenge
# Proxies to portless on localhost:8080, rewriting Host to match portless TLD
# t3.$DOMAIN is carved out to reach the T3 Code server on localhost:3773

t3.$DOMAIN {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}

	# T3 Code web GUI — WebSocket server bound to localhost:3773 (\`t3 serve\`).
	# This specific site address wins over the *.$DOMAIN wildcard below, so T3
	# traffic reaches 3773 instead of portless on 8080. reverse_proxy upgrades
	# WebSocket connections automatically, and TLS here satisfies the browser
	# mixed-content rule that blocks an HTTPS page from talking to plain-HTTP.
	reverse_proxy localhost:3773
}

*.$DOMAIN {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}

	reverse_proxy localhost:8080 {
		header_up Host {http.request.host.labels.3}.$HOSTNAME
	}
}

$DOMAIN {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}

	respond "$HOSTNAME dev server" 200
}
EOF
}

write_caddy_env() {
  ensure_caddy_config_dir
  sudo tee "$CADDY_ENV_PATH" > /dev/null <<EOF
CF_API_TOKEN=${CF_API_TOKEN}
EOF
  sudo chmod 600 "$CADDY_ENV_PATH"
}

setup_caddy_systemd() {
  echo "Configuring Caddy systemd service..."
  write_caddy_env
  sudo chown caddy:caddy "$CADDY_ENV_PATH"

  sudo mkdir -p /etc/systemd/system/caddy.service.d
  sudo tee /etc/systemd/system/caddy.service.d/override.conf > /dev/null <<EOF
[Service]
EnvironmentFile=$CADDY_ENV_PATH
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable caddy
  sudo systemctl restart caddy
  echo "Caddy started."
}

setup_caddy_launchd() {
  echo "Configuring Caddy launchd service..."
  write_caddy_env
  sudo chown root:wheel "$CADDY_ENV_PATH"
  sudo install -d -o root -g wheel -m 700 "$CADDY_CONFIG_DIR/data" "$CADDY_CONFIG_DIR/config"

  local runner="$CADDY_CONFIG_DIR/run-caddy.sh"
  sudo tee "$runner" > /dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -a
source "$CADDY_ENV_PATH"
set +a
export HOME="/var/root"
export XDG_DATA_HOME="$CADDY_CONFIG_DIR/data"
export XDG_CONFIG_HOME="$CADDY_CONFIG_DIR/config"
exec "$CADDY_BIN" run --config "$CADDYFILE_PATH" --adapter caddyfile
EOF
  sudo chmod 700 "$runner"
  sudo chown root:wheel "$runner"

  sudo tee /Library/LaunchDaemons/local.caddy.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.caddy</string>
  <key>ProgramArguments</key>
  <array>
    <string>$runner</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/local.caddy.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/local.caddy.err</string>
</dict>
</plist>
EOF
  sudo chmod 644 /Library/LaunchDaemons/local.caddy.plist
  sudo chown root:wheel /Library/LaunchDaemons/local.caddy.plist
  sudo launchctl bootout system /Library/LaunchDaemons/local.caddy.plist >/dev/null 2>&1 || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/local.caddy.plist
  sudo launchctl kickstart -k system/local.caddy
  echo "Caddy started."
}

setup_portless_systemd() {
  echo "Creating portless-proxy systemd service..."

  portless proxy stop -p 8080 2>/dev/null || true
  rm -f "$RUN_HOME/.portless/proxy.tld" "$RUN_HOME/.portless/proxy.pid" \
        "$RUN_HOME/.portless/proxy.port" "$RUN_HOME/.portless/proxy.lan"

  local mise_shims="$RUN_HOME/.local/share/mise/shims"

  sudo tee /etc/systemd/system/portless-proxy.service > /dev/null <<EOF
[Unit]
Description=Portless HTTP proxy for $DOMAIN
After=network.target
# Fail visibly instead of restart-looping forever (see t3-serve for the war
# story); systemctl reset-failed to retry after fixing the cause.
StartLimitIntervalSec=600
StartLimitBurst=20

[Service]
Type=simple
User=$RUN_USER
Environment=HOME=$RUN_HOME
Environment=PATH=$mise_shims:/usr/local/bin:/usr/bin:/bin
Environment=PORTLESS_LAN=0
ExecStart=$mise_shims/portless proxy start --foreground --no-tls --tld $HOSTNAME -p 8080
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable portless-proxy
  sudo systemctl restart portless-proxy
  echo "Portless proxy started on port 8080 (TLD: $HOSTNAME)."
}

setup_portless_launchd() {
  echo "Creating portless-proxy launchd service..."

  portless proxy stop -p 8080 2>/dev/null || true
  rm -f "$RUN_HOME/.portless/proxy.tld" "$RUN_HOME/.portless/proxy.pid" \
        "$RUN_HOME/.portless/proxy.port" "$RUN_HOME/.portless/proxy.lan"

  # The service runs as UserName=$RUN_USER, so its stdout/stderr files must be
  # in a path that user can write. /var/log is root-only: launchd cannot open
  # the job's stdio there and the job dies before exec with a *misleading*
  # "posix_spawn(<program>) error 0xd - Permission denied" + EX_CONFIG (78) and
  # zero log output (it can't create the log to log to). Caddy's daemon escapes
  # this only because it runs as root. Keep portless logs under the user's home.
  local portless_log_dir="$RUN_HOME/.portless/logs"
  mkdir -p "$portless_log_dir"
  if [[ "$(id -u)" -eq 0 ]]; then
    chown "$RUN_USER" "$RUN_HOME/.portless" "$portless_log_dir" 2>/dev/null || true
  fi

  local portless_dir portless_path
  portless_path=$(command -v portless)
  portless_dir=$(dirname "$portless_path")

  sudo tee /Library/LaunchDaemons/local.portless-proxy.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.portless-proxy</string>
  <key>UserName</key>
  <string>$RUN_USER</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$RUN_HOME</string>
    <key>PATH</key>
    <string>$portless_dir:$RUN_HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>PORTLESS_LAN</key>
    <string>0</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>$portless_path</string>
    <string>proxy</string>
    <string>start</string>
    <string>--foreground</string>
    <string>--no-tls</string>
    <string>--tld</string>
    <string>$HOSTNAME</string>
    <string>-p</string>
    <string>8080</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$portless_log_dir/proxy.log</string>
  <key>StandardErrorPath</key>
  <string>$portless_log_dir/proxy.err</string>
</dict>
</plist>
EOF
  sudo chmod 644 /Library/LaunchDaemons/local.portless-proxy.plist
  sudo chown root:wheel /Library/LaunchDaemons/local.portless-proxy.plist
  sudo launchctl bootout system /Library/LaunchDaemons/local.portless-proxy.plist >/dev/null 2>&1 || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/local.portless-proxy.plist
  sudo launchctl kickstart -k system/local.portless-proxy
  echo "Portless proxy started on port 8080 (TLD: $HOSTNAME)."
}

setup_services() {
  case "$OS" in
    Linux)
      setup_caddy_systemd
      setup_portless_systemd
      ;;
    Darwin)
      setup_caddy_launchd
      setup_portless_launchd
      ;;
  esac
}

verify() {
  echo ""
  echo "Verifying setup..."
  sleep 2

  case "$OS" in
    Linux)
      if sudo systemctl is-active --quiet caddy; then
        echo "  OK: Caddy is running"
      else
        echo "  ERROR: Caddy failed to start"
        sudo journalctl -u caddy --no-pager -n 10
        return 1
      fi

      if sudo systemctl is-active --quiet portless-proxy; then
        echo "  OK: Portless proxy is running"
      else
        echo "  ERROR: Portless proxy failed to start"
        sudo journalctl -u portless-proxy --no-pager -n 10
        return 1
      fi
      ;;
    Darwin)
      launchd_job_running local.caddy 443
      launchd_job_running local.portless-proxy 8080
      ;;
  esac

  if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" 2>/dev/null | grep -q 200; then
    echo "  OK: https://$DOMAIN responds with valid TLS"
  else
    echo "  NOTE: https://$DOMAIN not yet responding (cert may still be issuing)"
  fi

  local LAN_IP
  LAN_IP=$(get_lan_ip)
  LAN_IP=${LAN_IP:-"<this machine's LAN IP>"}

  echo ""
  echo "Setup complete for $DOMAIN"
  echo ""
  echo "Services:"
  if [[ "$OS" == "Linux" ]]; then
    echo "  Caddy:      sudo systemctl status caddy"
    echo "  Portless:   sudo systemctl status portless-proxy"
    echo "  Caddy logs: sudo journalctl -u caddy -f"
    echo "  PL logs:    sudo journalctl -u portless-proxy -f"
  else
    echo "  Caddy:      sudo launchctl print system/local.caddy"
    echo "  Portless:   sudo launchctl print system/local.portless-proxy"
    echo "  Caddy logs: tail -f /var/log/local.caddy.err"
    echo "  PL logs:    tail -f $RUN_HOME/.portless/logs/proxy.err"
  fi
  echo ""
  echo "Usage:"
  echo "  portless myapp pnpm dev -> https://myapp.$DOMAIN"
  echo ""
  echo "Next steps for a new machine:"
  echo "  Cloudflare DNS A records:"
  echo "    $DOMAIN   -> $LAN_IP"
  echo "    *.$DOMAIN -> $LAN_IP"
  echo "  Ensure ports 443 and 80 are open on this machine."
}

preflight
install_caddy
write_caddyfile
setup_services
verify
