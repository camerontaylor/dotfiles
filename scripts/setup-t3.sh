#!/usr/bin/env bash
set -euo pipefail

# setup-t3.sh - run `t3 serve` (T3 Code GUI for coding agents) as a managed
# daemon bound to loopback, fronted by Caddy.
#
# Topology (mirrors the portless daemon in setup-caddy.sh):
#   t3 binds 127.0.0.1:3773 only. Caddy terminates TLS on :443 and reverse-
#   proxies t3.<host>.webfront.app -> localhost:3773 over the Tailscale mesh.
#   Nothing exposes 3773 directly; add the t3.<host> Caddy block first.
#
#   Linux  -> systemd service (runs as the login user, mise shims on PATH)
#   macOS  -> launchd LaunchDaemon (UserName=<user>)
#
# macOS gotcha (learned the hard way with portless): a LaunchDaemon runs as the
# system, and if StandardOutPath/StandardErrorPath point at /var/log (root-only)
# the non-root job cannot open its own stdio and launchd kills it before exec
# with a MISLEADING `posix_spawn(<program>) error 0xd - Permission denied` +
# EX_CONFIG (78) and zero log output. So t3's daemon logs go under the user's
# home ($T3_LOG_DIR), exactly like the portless fix.
#
# Prereqs: mise (for the t3 CLI), and the t3.<host>.webfront.app Caddy block.

T3_PORT=3773
T3_HOST=127.0.0.1
T3_MODE=web

OS=$(uname -s)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)
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
    echo "ERROR: Unsupported OS: $OS"
    exit 1
    ;;
esac

if [[ -z "${RUN_HOME:-}" ]]; then
  echo "ERROR: cannot resolve home directory for $RUN_USER"
  exit 1
fi

MISE_SHIMS="$RUN_HOME/.local/share/mise/shims"
T3_LOG_DIR="$RUN_HOME/.t3code/logs"
T3_TOOL="npm:t3@latest"

# Resolve a mise binary. t3 is run via `mise exec <tool> -- t3 ...` rather than
# the bare `t3` shim, so the daemon does NOT depend on t3 being activated in a
# mise config file. That matters: the hosts' ~/.config/mise/config.toml is a
# symlink to the git-tracked configs/mise.toml, so activating with `mise use -g`
# would dirty their working tree and collide with a future deploy/pull. The bare
# shim errors "No version is set for shim: t3" until activated; `mise exec`
# resolves the installed tool directly and sidesteps the whole problem.
MISE_BIN=""
for _m in "$RUN_HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
  [[ -x "$_m" ]] && { MISE_BIN="$_m"; break; }
done
[[ -z "$MISE_BIN" ]] && MISE_BIN="$(command -v mise 2>/dev/null || true)"
if [[ -z "$MISE_BIN" ]]; then
  echo "ERROR: mise not found; cannot run the t3 CLI. Install mise first."
  exit 1
fi

# mise install/exec must run as the target user so it uses their mise data dir.
mise_as_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$RUN_USER" HOME="$RUN_HOME" "$MISE_BIN" "$@"
  else
    "$MISE_BIN" "$@"
  fi
}

ensure_t3() {
  echo "Ensuring t3 CLI is installed (via mise)..."
  mise_as_user install "$T3_TOOL"
  local ver
  ver=$(mise_as_user exec "$T3_TOOL" -- t3 --version 2>&1 | grep -oE 't3 v[0-9.]+' | head -1)
  echo "t3 CLI: ${ver:-installed}  (run via: $MISE_BIN exec $T3_TOOL -- t3 ...)"
}

ensure_node_pty() {
  # t3 bundles node-pty (native module for agent terminal sessions). node-pty
  # ships prebuilt binaries for darwin/win32 but NOT linux, and npm 11's
  # allow-scripts gate skips node-pty's build hook during `mise install` — so on
  # Linux the native pty.node is never built and t3 crash-loops at runtime with
  # "Failed to load native module: pty.node". Build it from source when absent.
  # (macOS already has the darwin prebuild, so this is a no-op there.)
  local t3root np plat
  t3root=$(mise_as_user where "$T3_TOOL" 2>/dev/null | tail -1) || return 0
  [[ -n "$t3root" ]] || return 0
  np="$t3root/lib/node_modules/t3/node_modules/node-pty"
  if [[ ! -d "$np" ]]; then
    echo "node-pty dir not found under $t3root (skipping native-module check)."
    return 0
  fi
  if [[ -f "$np/build/Release/pty.node" ]]; then
    echo "node-pty native module already built."
    return 0
  fi
  case "$OS" in Darwin) plat=darwin ;; Linux) plat=linux ;; *) plat="" ;; esac
  if [[ -n "$plat" ]] && ls "$np"/prebuilds/"${plat}"-*/pty.node >/dev/null 2>&1; then
    echo "node-pty prebuilt binary present for $plat."
    return 0
  fi
  echo "Building node-pty native module from source (no $plat prebuild; needs a C/C++ toolchain)..."
  local build_cmd="export PATH='$MISE_SHIMS':\$PATH; cd '$np' && npx --yes node-gyp rebuild"
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$RUN_USER" HOME="$RUN_HOME" bash -c "$build_cmd" 2>&1 | tail -6
  else
    HOME="$RUN_HOME" bash -c "$build_cmd" 2>&1 | tail -6
  fi
  if [[ -f "$np/build/Release/pty.node" ]]; then
    echo "node-pty built: build/Release/pty.node"
  else
    echo "WARNING: node-pty build did not produce build/Release/pty.node; agent terminals may fail."
  fi
}

ensure_log_dir() {
  mkdir -p "$T3_LOG_DIR"
  if [[ "$(id -u)" -eq 0 ]]; then
    chown "$RUN_USER" "$RUN_HOME/.t3code" "$T3_LOG_DIR" 2>/dev/null || true
  fi
}

setup_t3_systemd() {
  echo "Creating t3-serve systemd service..."
  sudo tee /etc/systemd/system/t3-serve.service > /dev/null <<EOF
[Unit]
Description=T3 Code server for $HOSTNAME (loopback :$T3_PORT, fronted by Caddy)
After=network.target

[Service]
Type=simple
User=$RUN_USER
Environment=HOME=$RUN_HOME
Environment=PATH=$MISE_SHIMS:$RUN_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$RUN_HOME
ExecStart=$MISE_BIN exec $T3_TOOL -- t3 serve --mode $T3_MODE --host $T3_HOST --port $T3_PORT --no-browser
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable t3-serve
  sudo systemctl restart t3-serve
  echo "t3-serve started on $T3_HOST:$T3_PORT."
}

setup_t3_launchd() {
  echo "Creating t3-serve launchd service..."
  # Logs MUST be user-writable (see header note): launchd execs the job as
  # UserName=$RUN_USER, so /var/log (root-only) would make it fail to open its
  # stdio. mise + the t3 tool live under the user's home and resolve fine once
  # the job runs as that user with HOME set.
  sudo tee /Library/LaunchDaemons/local.t3-serve.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.t3-serve</string>
  <key>UserName</key>
  <string>$RUN_USER</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$RUN_HOME</string>
    <key>PATH</key>
    <string>$MISE_SHIMS:$RUN_HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>$MISE_BIN</string>
    <string>exec</string>
    <string>$T3_TOOL</string>
    <string>--</string>
    <string>t3</string>
    <string>serve</string>
    <string>--mode</string>
    <string>$T3_MODE</string>
    <string>--host</string>
    <string>$T3_HOST</string>
    <string>--port</string>
    <string>$T3_PORT</string>
    <string>--no-browser</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$RUN_HOME</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$T3_LOG_DIR/serve.log</string>
  <key>StandardErrorPath</key>
  <string>$T3_LOG_DIR/serve.err</string>
</dict>
</plist>
EOF
  sudo chmod 644 /Library/LaunchDaemons/local.t3-serve.plist
  sudo chown root:wheel /Library/LaunchDaemons/local.t3-serve.plist
  sudo launchctl bootout system /Library/LaunchDaemons/local.t3-serve.plist >/dev/null 2>&1 || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/local.t3-serve.plist
  sudo launchctl kickstart -k system/local.t3-serve
  echo "t3-serve started on $T3_HOST:$T3_PORT."
}

verify() {
  echo ""
  echo "Verifying setup..."
  sleep 3

  case "$OS" in
    Linux)
      if sudo systemctl is-active --quiet t3-serve; then
        echo "  OK: t3-serve is running"
      else
        echo "  ERROR: t3-serve failed to start"
        sudo journalctl -u t3-serve --no-pager -n 15
        return 1
      fi
      ;;
    Darwin)
      if sudo launchctl print system/local.t3-serve 2>/dev/null | grep -q 'state = running'; then
        echo "  OK: t3-serve launchd job is running"
      else
        echo "  ERROR: t3-serve launchd job is not running"
        sudo launchctl print system/local.t3-serve 2>/dev/null | grep -E 'state =|last exit code =' || true
        echo "  --- recent log ---"; tail -15 "$T3_LOG_DIR/serve.log" "$T3_LOG_DIR/serve.err" 2>/dev/null
        return 1
      fi
      ;;
  esac

  if command -v lsof &>/dev/null; then
    if sudo lsof -nP -iTCP:"$T3_PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 | grep -q .; then
      echo "  OK: listening on TCP $T3_PORT"
    else
      echo "  NOTE: not yet listening on $T3_PORT (may still be starting)"
    fi
  fi

  echo ""
  echo "t3-serve is up on $T3_HOST:$T3_PORT for $HOSTNAME"
  echo "Reachable via Caddy at: https://t3.$HOSTNAME.webfront.app"
  echo ""
  if [[ "$OS" == "Linux" ]]; then
    echo "  Service:  sudo systemctl status t3-serve"
    echo "  Logs:     sudo journalctl -u t3-serve -f"
  else
    echo "  Service:  sudo launchctl print system/local.t3-serve"
    echo "  Logs:     tail -f $T3_LOG_DIR/serve.log"
  fi
  echo ""
  echo "Note: T3 needs a provider authenticated to be useful (codex login /"
  echo "      claude auth login / opencode auth login). Headless pairing details"
  echo "      are printed in the log above."
}

echo "Machine:  $HOSTNAME"
echo "User:     $RUN_USER (home: $RUN_HOME)"
echo "Bind:     $T3_HOST:$T3_PORT (mode: $T3_MODE)"
echo ""

ensure_t3
ensure_node_pty
ensure_log_dir

case "$OS" in
  Linux)  setup_t3_systemd ;;
  Darwin) setup_t3_launchd ;;
esac

verify
