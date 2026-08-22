#!/usr/bin/env bash
set -euo pipefail

# setup-paseo.sh - install and configure Paseo (https://github.com/getpaseo/paseo),
# the self-hosted orchestrator for Claude Code / Codex / Copilot / OpenCode / Pi
# agents, on a fleet box. Idempotent; safe to re-run.
#
# Topology (deliberately NOT the t3/portless shape - see below):
#   Paseo daemon binds [::]:6767 (dual-stack) and authenticates every HTTP/WS
#   client with a bcrypt password. The phone app reaches it over Tailscale by
#   the box's 100.x address; a terminal on any fleet box reaches it through the
#   `paseo-at <box>` helper in zsh/rc.d/12_paseo.zsh.
#
#   Linux (ceres, headless) -> systemd service, User=<login user>, plus the
#                              daemon-served web UI on the same port so a
#                              browser is a first-class client.
#   macOS (saturn, neptune) -> Paseo.app (brew cask) normally owns the daemon,
#                              but the app has no launch-at-login support and
#                              the daemon dies with it, so a one-shot user
#                              LaunchAgent starts one at login too. See
#                              setup_launchagent for why it is one-shot.
#
# WHY NOT LOOPBACK-BEHIND-CADDY, like setup-t3.sh / setup-caddy.sh:
#   Paseo's phone clients speak WebSocket to /ws and its own docs' Tailscale
#   path is a direct host:port connection. Fronting it with Caddy would add a
#   Host-header allowlist (daemon.hostnames) plus daemon.trustedProxies to get
#   X-Forwarded-* right, for TLS that Tailscale's WireGuard already provides.
#   Direct bind + password is fewer moving parts and one less thing to be down.
#   (If you later want https://paseo.<host>.webfront.app anyway, add a carve-out
#   block to setup-caddy.sh mirroring the t3 one and set daemon.hostnames.)
#
# Auth: a bcrypt hash in ~/.paseo/config.json - the one mechanism that works
#   for BOTH a systemd-managed daemon and a GUI-launched one. PASEO_PASSWORD as
#   an env var only reaches the daemon on Linux; the macOS desktop app is
#   launched by the GUI and never sees your shell environment. Set
#   PASEO_PASSWORD (or a precomputed PASEO_PASSWORD_HASH) in the encrypted
#   secrets file zsh/env.d/90_secrets.zsh, which zsh/rc.d/12_paseo.zsh also
#   sources so CLI clients authenticate without a flag.
#
# WITHOUT a password this script refuses to widen the bind past 127.0.0.1:
#   an unauthenticated Paseo daemon on the office LAN is remote code execution
#   as you, by design.
#
# Prereqs: mise (Linux, for the CLI), Homebrew (macOS, for the cask), Tailscale
#   joined (scripts/deploy.d/73_tailscale.zsh), and at least one agent CLI
#   authenticated - claude / codex / opencode / copilot. Paseo drives those
#   binaries; it does not carry its own model credentials.

PASEO_PORT=${PASEO_PORT:-6767}
PASEO_TOOL="npm:@getpaseo/cli@latest"
BCRYPT_COST=12   # matches DAEMON_PASSWORD_BCRYPT_COST in paseo's server package

OS=$(uname -s)

# Resolve the box's FLEET name. On macOS `hostname -s` is only trustworthy once
# HostName is explicitly set: with it unset, hostname(1) DERIVES a name from the
# network, and on neptune that derivation returned "iMac" — which would have put
# "iMac" in the Host allowlist and in the printed instructions. (Both Macs had
# HostName unset; saturn merely derived "saturn.local" by luck. Fixed on
# 2026-08-22 with `sudo scutil --set HostName <name>`, which has no GUI —
# System Settings only edits ComputerName and LocalHostName.)
# Prefer scutil's LocalHostName anyway, so a freshly imaged Mac is right before
# anyone remembers to set HostName. setup-caddy.sh and setup-t3.sh still use
# bare `hostname -s` and would have had the same blind spot.
resolve_hostname() {
  local name=""
  if [[ "$(uname -s)" == "Darwin" ]] && command -v scutil &>/dev/null; then
    name=$(scutil --get LocalHostName 2>/dev/null) || name=""
    [[ -z "$name" ]] && { name=$(scutil --get HostName 2>/dev/null) || name=""; }
    # HostName may be an FQDN; take the first label.
    name=${name%%.*}
  fi
  [[ -z "$name" ]] && name=$(hostname -s 2>/dev/null || hostname)
  printf '%s' "$name"
}
HOSTNAME_SHORT=$(resolve_hostname)
RUN_USER=${SUDO_USER:-$(id -un)}
if [[ ! "$RUN_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: unsafe user name: $RUN_USER"
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
CONFIG_TOOL="$SCRIPT_DIR/paseo-config.mjs"
if [[ ! -r "$CONFIG_TOOL" ]]; then
  echo "ERROR: missing $CONFIG_TOOL"
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
PASEO_HOME_DIR="$RUN_HOME/.paseo"

# Resolve a mise binary the same way setup-t3.sh does: mise may not be on the
# PATH of a sudo/cron/non-interactive caller.
MISE_BIN=""
for _m in "$RUN_HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
  [[ -x "$_m" ]] && { MISE_BIN="$_m"; break; }
done
[[ -z "$MISE_BIN" ]] && MISE_BIN="$(command -v mise 2>/dev/null || true)"

mise_as_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$RUN_USER" HOME="$RUN_HOME" "$MISE_BIN" "$@"
  else
    "$MISE_BIN" "$@"
  fi
}

# Resolve a node to run paseo-config.mjs with. mise shims first (the ONE node on
# every fleet box, per configs/mise.toml), then whatever is on PATH.
NODE_BIN=""
for _n in "$MISE_SHIMS/node" "$(command -v node 2>/dev/null || true)"; do
  [[ -n "$_n" && -x "$_n" ]] && { NODE_BIN="$_n"; break; }
done
if [[ -z "$NODE_BIN" ]]; then
  echo "ERROR: node not found (expected the mise-managed node). Run ./deploy.zsh first."
  exit 1
fi

# --- install -----------------------------------------------------------------

install_macos() {
  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found; needed for the Paseo cask."
    exit 1
  fi
  if brew list --cask paseo &>/dev/null; then
    echo "Paseo.app already installed (brew upgrade --cask paseo to update)."
  else
    echo "Installing Paseo.app (brew cask)..."
    brew install --cask paseo
  fi
  # The cask ships its own `paseo` CLI symlinked into the brew prefix, kept in
  # lockstep with the app. Do NOT also install @getpaseo/cli as an npm global
  # here: two `paseo` binaries of drifting versions on one PATH is the kind of
  # split-brain that took a week to spot with Vite+ (see 70_runtime_installs.zsh).
  if ! command -v paseo &>/dev/null; then
    echo "WARNING: \`paseo\` is not on PATH yet. Open a new shell, or check"
    echo "         $(brew --prefix)/bin/paseo"
  fi
}

install_linux() {
  if [[ -z "$MISE_BIN" ]]; then
    echo "ERROR: mise not found; cannot install the Paseo CLI. Run ./deploy.zsh first."
    exit 1
  fi
  echo "Ensuring the Paseo CLI is installed (via mise)..."
  # Installed as a mise tool rather than an entry in .default-npm-packages so
  # the macOS boxes, where the cask owns the `paseo` name, do not get a second
  # copy from the fleet-wide npm globals list.
  mise_as_user install "$PASEO_TOOL"
  local ver
  ver=$(mise_as_user exec "$PASEO_TOOL" -- paseo --version 2>&1 | head -1)
  echo "Paseo CLI: ${ver:-installed}  (run via: $MISE_BIN exec $PASEO_TOOL -- paseo ...)"
}

check_node_pty() {
  # Paseo's daemon uses node-pty for agent terminals. t3 crash-looped on Linux
  # for exactly this reason (see ensure_node_pty in setup-t3.sh): no linux
  # prebuild, and npm 11's allow-scripts gate skips the build hook. Paseo pins
  # node-pty 1.2.0-beta.15, which DOES ship prebuilds/linux-x64 - so this is a
  # verification, not a workaround. It stays because the failure is invisible
  # until someone opens a terminal in the app.
  local root np
  root=$(mise_as_user where "$PASEO_TOOL" 2>/dev/null | tail -1) || return 0
  [[ -n "$root" ]] || return 0
  np=$(find "$root/lib/node_modules" -maxdepth 4 -type d -name node-pty -print 2>/dev/null | head -1)
  if [[ -z "$np" ]]; then
    echo "NOTE: node-pty not found under $root (skipping native-module check)."
    return 0
  fi
  if [[ -f "$np/build/Release/pty.node" ]] || ls "$np"/prebuilds/linux-*/pty.node >/dev/null 2>&1; then
    echo "node-pty native module OK."
  else
    echo "WARNING: no node-pty binary for this platform under $np."
    echo "         Agent terminals will fail. Build it with:"
    echo "           cd '$np' && npx --yes node-gyp rebuild"
  fi
}

# --- password ----------------------------------------------------------------

# Prints a bcrypt hash on stdout, or nothing if no password is configured.
#
# Re-uses the hash already in config.json when it verifies against the current
# password. bcrypt re-salts on every call, so hashing unconditionally would
# produce a different string each run - the config would churn and the daemon
# would restart on every re-run of this script, for no change at all.
resolve_password_hash() {
  if [[ -n "${PASEO_PASSWORD_HASH:-}" ]]; then
    printf '%s' "$PASEO_PASSWORD_HASH"
    return 0
  fi
  [[ -n "${PASEO_PASSWORD:-}" ]] || return 0

  # `paseo daemon set-password` is the documented route but prompts
  # interactively (@clack/prompts, no --password flag), so it cannot be driven
  # from a setup script. It just bcrypts at cost 12 and writes config.json, so
  # do the same thing here with bcryptjs - which is pure JS, no native build.
  local bcrypt_dir root tmpdir
  bcrypt_dir=""
  if [[ -n "$MISE_BIN" ]]; then
    root=$(mise_as_user where "$PASEO_TOOL" 2>/dev/null | tail -1) || true
    if [[ -n "${root:-}" ]]; then
      bcrypt_dir=$(find "$root/lib/node_modules" -maxdepth 5 -type d -name bcryptjs -print 2>/dev/null | head -1)
    fi
  fi
  if [[ -z "$bcrypt_dir" ]]; then
    # macOS: the cask's node_modules live inside the app's asar archive and are
    # not resolvable from here. Fetch bcryptjs into a throwaway prefix.
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/paseo-bcrypt.XXXXXX")
    trap 'rm -rf "$tmpdir"' RETURN
    if ! npm install --no-save --no-audit --no-fund --loglevel=error --prefix "$tmpdir" bcryptjs@3 >/dev/null 2>&1; then
      echo "ERROR: could not obtain bcryptjs to hash PASEO_PASSWORD." >&2
      echo "       Either run \`paseo daemon set-password\` by hand, or set" >&2
      echo "       PASEO_PASSWORD_HASH to a precomputed bcrypt hash." >&2
      return 1
    fi
    bcrypt_dir="$tmpdir/node_modules/bcryptjs"
  fi

  PASEO_PASSWORD="$PASEO_PASSWORD" "$NODE_BIN" \
    -e '
      const bcrypt = require(process.argv[1]);
      const cost = Number(process.argv[2]);
      const configPath = process.argv[3];
      const pw = process.env.PASEO_PASSWORD;
      let current = null;
      try {
        current = JSON.parse(require("node:fs").readFileSync(configPath, "utf8"))?.daemon?.auth?.password ?? null;
      } catch { /* absent or unparseable - fall through to a fresh hash */ }
      if (current && bcrypt.compareSync(pw, current)) {
        process.stdout.write(current);   // unchanged: keep the config stable
      } else {
        process.stdout.write(bcrypt.hashSync(pw, cost));
      }
    ' \
    "$bcrypt_dir" "$BCRYPT_COST" "$PASEO_HOME_DIR/config.json"
}

# --- service -----------------------------------------------------------------

setup_systemd() {
  local listen="$1" config_changed="$2"
  local unit=/etc/systemd/system/paseo-daemon.service
  local staged
  staged=$(mktemp "${TMPDIR:-/tmp}/paseo-unit.XXXXXX")
  echo "Installing paseo-daemon systemd service..."
  # No --listen/--web-ui/--relay flags on ExecStart on purpose: per Paseo's
  # configuration docs, start flags are LAUNCH OVERRIDES that outrank
  # config.json and make later edits to those keys silently ineffective
  # (reload reports them under overrideControlledPaths). config.json stays the
  # single source of truth; the unit only says where home is.
  cat > "$staged" <<EOF
[Unit]
Description=Paseo daemon for $HOSTNAME_SHORT (agent orchestrator, listen $listen)
Documentation=https://paseo.sh/docs
After=network-online.target
Wants=network-online.target
# Fail visibly instead of restart-looping forever - same guard as t3-serve,
# which once crash-looped for a week unnoticed. systemctl reset-failed to retry.
StartLimitIntervalSec=600
StartLimitBurst=20

[Service]
Type=simple
User=$RUN_USER
Environment=HOME=$RUN_HOME
# Agents spawned by the daemon inherit this PATH, so it needs the mise shims:
# claude/codex/opencode and every tool they shell out to resolve through them.
Environment=PATH=$MISE_SHIMS:$RUN_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=PASEO_HOME=$PASEO_HOME_DIR
WorkingDirectory=$RUN_HOME
ExecStart=$MISE_BIN exec $PASEO_TOOL -- paseo daemon start --foreground --home $PASEO_HOME_DIR
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  # Only bounce the daemon when something actually changed. A re-run that finds
  # the unit and config identical should not interrupt running agents.
  local unit_changed=0
  if ! sudo cmp -s "$staged" "$unit" 2>/dev/null; then
    unit_changed=1
    sudo cp "$staged" "$unit"
    sudo chmod 644 "$unit"
    sudo chown root:root "$unit"
    sudo systemctl daemon-reload
  fi
  rm -f "$staged"
  sudo systemctl enable paseo-daemon > /dev/null 2>&1 || true

  if (( unit_changed )) || [[ "$config_changed" == "1" ]] || ! sudo systemctl is-active --quiet paseo-daemon; then
    sudo systemctl restart paseo-daemon
    echo "paseo-daemon (re)started on $listen."
  else
    echo "paseo-daemon already running with this unit and config; left alone."
  fi
}

setup_launchagent() {
  # Paseo.app has NO launch-at-login support (no such setting in the desktop
  # package, none in the docs), and the daemon dies with it. Without this, the
  # phone silently loses saturn/neptune after every reboot until someone walks
  # over and opens the app.
  #
  # A *user* LaunchAgent, not a system LaunchDaemon like t3-serve: the daemon
  # spawns claude/codex/opencode, which need this user's login session, keychain
  # and credentials.
  #
  # One-shot (RunAtLoad, no KeepAlive) on purpose. `paseo daemon start` exits 1
  # when a daemon already holds the port - it leaves the running one alone, but
  # under KeepAlive that non-zero exit would become a restart loop every time
  # the app got there first. One-shot means: at login, start it if nothing else
  # has; otherwise fail harmlessly into the log.
  #
  # AbandonProcessGroup is the load-bearing key. `paseo daemon start` forks and
  # returns; without it launchd reaps the whole process group when the job
  # exits and kills the daemon it just started.
  local plist="$RUN_HOME/Library/LaunchAgents/local.paseo-daemon.plist"
  local paseo_bin
  paseo_bin=$(command -v paseo 2>/dev/null || true)
  if [[ -z "$paseo_bin" ]]; then
    for _p in /opt/homebrew/bin/paseo /usr/local/bin/paseo; do
      [[ -x "$_p" ]] && { paseo_bin="$_p"; break; }
    done
  fi
  if [[ -z "$paseo_bin" ]]; then
    echo "NOTE: no \`paseo\` binary found; skipping the login job."
    return 0
  fi

  echo "Installing the login job (~/Library/LaunchAgents/local.paseo-daemon.plist)..."
  mkdir -p "$RUN_HOME/Library/LaunchAgents"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.paseo-daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>$paseo_bin</string>
    <string>daemon</string>
    <string>start</string>
    <string>--home</string>
    <string>$PASEO_HOME_DIR</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$RUN_HOME</string>
    <!-- Agents spawned by the daemon inherit this PATH. launchd's default has
         no mise shims, so a GUI-launched daemon cannot even find claude. -->
    <key>PATH</key>
    <string>$MISE_SHIMS:$RUN_HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>$RUN_HOME</string>
  <key>RunAtLoad</key>
  <true/>
  <key>AbandonProcessGroup</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$PASEO_HOME_DIR/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$PASEO_HOME_DIR/launchd.err</string>
</dict>
</plist>
EOF
  chmod 644 "$plist"
  local uid
  uid=$(id -u "$RUN_USER")
  launchctl bootout "gui/$uid/local.paseo-daemon" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1; then
    echo "  ...loaded (starts the daemon at every login)"
  else
    echo "  ...could not bootstrap the login job; load it by hand with:"
    echo "       launchctl bootstrap gui/$uid $plist"
  fi
}

restart_macos_daemon() {
  local config_changed="$1"
  # daemon.listen and auth are STARTUP settings - `paseo reload` cannot apply
  # them - so a changed config needs a bounce. An unchanged one does not, and
  # bouncing anyway would kill whatever agents are mid-task.
  if ! command -v paseo &>/dev/null; then
    echo "No \`paseo\` binary yet - open Paseo.app once to start the daemon."
    return 0
  fi
  if ! paseo daemon status >/dev/null 2>&1; then
    echo "Starting the daemon..."
    paseo daemon start --home "$PASEO_HOME_DIR" >/dev/null 2>&1 \
      || echo "  ...could not start it from the CLI; open Paseo.app."
    return 0
  fi
  if [[ "$config_changed" == "1" ]]; then
    echo "Restarting the daemon to pick up config.json..."
    paseo daemon restart >/dev/null 2>&1 \
      || echo "  ...could not restart from the CLI; use Settings -> your host -> Restart daemon."
  else
    echo "Daemon already running with this config; left alone."
  fi
}

# --- run ---------------------------------------------------------------------

echo "Machine:  $HOSTNAME_SHORT ($OS)"
echo "User:     $RUN_USER (home: $RUN_HOME)"
echo ""

case "$OS" in
  Darwin) install_macos ;;
  Linux)  install_linux; check_node_pty ;;
esac
echo ""

PASSWORD_HASH=$(resolve_password_hash)

if [[ -n "$PASSWORD_HASH" ]]; then
  # [::] and NOT 0.0.0.0. The IPv4 wildcard does not cover IPv6 loopback, and
  # `localhost` on macOS resolves to ::1 FIRST - so a 0.0.0.0 bind leaves any
  # client that connects by name, and does not fall back fast, hanging on a
  # dead ::1. That is exactly how Paseo.app failed on saturn: curl worked
  # (it retries IPv4), the desktop app timed out.
  # `::` gives a dual-stack socket - it accepts IPv4-mapped connections too, so
  # 127.0.0.1 and the Tailscale 100.x IPv4 address still answer. Verified on
  # saturn: 127.0.0.1, [::1], localhost and 100.104.76.127 all return 200.
  LISTEN="[::]:$PASEO_PORT"
  echo "Auth:     bcrypt password hash -> daemon.auth.password"
else
  # Fail safe rather than fail open. Loopback-only has no dual-stack option -
  # binding [::1] accepts no IPv4, and 127.0.0.1 accepts no IPv6 (v4-mapped
  # works on the :: WILDCARD only). IPv4 is the better single choice here; this
  # is a deliberately degraded state you are meant to leave by setting a
  # password, so the localhost/::1 asymmetry above can bite until you do.
  LISTEN="127.0.0.1:$PASEO_PORT"
  echo "Auth:     NONE - binding loopback only."
  echo "          Set PASEO_PASSWORD in zsh/env.d/90_secrets.zsh (then"
  echo "          ./scripts/save-secrets.zsh) and re-run to expose this daemon"
  echo "          to the tailnet."
fi
echo "Bind:     $LISTEN"
echo ""

echo "Writing $PASEO_HOME_DIR/config.json..."
CONFIG_ARGS=(--home "$PASEO_HOME_DIR" --listen "$LISTEN" --relay false)
# Named access for the fleet's own DNS. IP literals - including every Tailscale
# 100.x address - are allowed by Paseo's hostname check unconditionally, so the
# phone connecting by `tailscale ip -4` needs nothing here.
CONFIG_ARGS+=(--hostname ".webfront.app" --hostname ".local" --hostname "$HOSTNAME_SHORT")
# The bundled web UI turns the daemon's own port into a browser client. Worth it
# on a headless box; on macOS the desktop app is the GUI, so leave the upstream
# default alone.
[[ "$OS" == "Linux" ]] && CONFIG_ARGS+=(--web-ui true)
[[ -n "$PASSWORD_HASH" ]] && CONFIG_ARGS+=(--password-hash "$PASSWORD_HASH")

if [[ "$(id -u)" -eq 0 ]]; then
  CONFIG_OUT=$(sudo -u "$RUN_USER" HOME="$RUN_HOME" "$NODE_BIN" "$CONFIG_TOOL" "${CONFIG_ARGS[@]}")
else
  CONFIG_OUT=$("$NODE_BIN" "$CONFIG_TOOL" "${CONFIG_ARGS[@]}")
fi
printf '%s\n' "$CONFIG_OUT"
# The patcher says "config already current" when it wrote nothing. Use that to
# avoid bouncing a daemon - and interrupting live agents - for no change.
CONFIG_CHANGED=1
case "$CONFIG_OUT" in *"already current"*) CONFIG_CHANGED=0 ;; esac
echo ""

case "$OS" in
  Linux)  setup_systemd "$LISTEN" "$CONFIG_CHANGED" ;;
  Darwin) setup_launchagent; restart_macos_daemon "$CONFIG_CHANGED" ;;
esac

# --- verify ------------------------------------------------------------------

echo ""
echo "Verifying..."
sleep 3

if [[ "$OS" == "Linux" ]]; then
  if sudo systemctl is-active --quiet paseo-daemon; then
    echo "  OK: paseo-daemon is running"
  else
    echo "  ERROR: paseo-daemon failed to start"
    sudo journalctl -u paseo-daemon --no-pager -n 20
    exit 1
  fi
fi

# /api/health is the one endpoint exempt from password auth, precisely so
# supervisors can probe it. Curl it rather than trusting "the unit is active".
if command -v curl &>/dev/null; then
  if curl -sf --max-time 5 "http://127.0.0.1:$PASEO_PORT/api/health" >/dev/null 2>&1; then
    echo "  OK: daemon answering on 127.0.0.1:$PASEO_PORT"
  else
    echo "  NOTE: no answer on 127.0.0.1:$PASEO_PORT yet (may still be starting)"
  fi
fi

TS_IP=""
for _ts in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale /usr/local/bin/tailscale; do
  if command -v "$_ts" &>/dev/null || [[ -x "$_ts" ]]; then
    TS_IP=$("$_ts" ip -4 2>/dev/null | head -1) || true
    [[ -n "$TS_IP" ]] && break
  fi
done

echo ""
echo "Paseo is up on $HOSTNAME_SHORT."
echo ""
if [[ -n "$TS_IP" ]]; then
  echo "  Phone:  Paseo -> Settings -> Add host -> Direct connection"
  echo "            Host: $TS_IP     Port: $PASEO_PORT     Use SSL: off"
  echo "          (Tailscale must be connected on the phone.)"
else
  echo "  Phone:  could not read a Tailscale IP here - run \`tailscale ip -4\`"
  echo "          and use that address with port $PASEO_PORT in the app."
fi
# NOT `paseo --host … ls`: in the stable CLI --host is a per-subcommand option,
# not a root one, so that form dies with "unknown option '--host'". (The README
# on main shows the root form because it documents the 0.5 beta.) $PASEO_HOST
# works for every subcommand, and is what zsh/rc.d/12_paseo.zsh's helpers set.
echo "  CLI:    paseo-at $HOSTNAME_SHORT ls        (or: PASEO_HOST=$HOSTNAME_SHORT.webfront.app:$PASEO_PORT paseo ls)"
[[ "$OS" == "Linux" ]] && echo "  Web:    http://$HOSTNAME_SHORT.webfront.app:$PASEO_PORT/"
echo ""
if [[ "$OS" == "Linux" ]]; then
  echo "  Service:  sudo systemctl status paseo-daemon"
  echo "  Logs:     sudo journalctl -u paseo-daemon -f   (also $PASEO_HOME_DIR/daemon.log)"
else
  echo "  Daemon:   managed by Paseo.app (Settings -> your host -> Overview)"
  echo "  Logs:     $PASEO_HOME_DIR/daemon.log"
fi
echo ""
echo "Paseo drives the agent CLIs you already have - it carries no model"
echo "credentials of its own. Make sure claude / codex / opencode are logged in"
echo "as $RUN_USER on this box, or agents will fail at launch."
