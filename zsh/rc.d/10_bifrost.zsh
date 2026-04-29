# Bifrost AI Gateway: systemd user service (lives on ceres; reachable from LAN
# peers via mDNS). Replaces the LiteLLM proxy + CCR (claude-code-router) two-
# layer stack with a single Go binary speaking Anthropic /v1/messages natively.
#
# Architecture:
#   - real Anthropic Opus → use ccc (direct OAuth, NOT this proxy)
#   - everything else (Z.AI, Fireworks, Cerebras, MiniMax) → ccfw / ccz / cc-fast / ccm
#
# Endpoint convention: Bifrost serves Anthropic-compatible /v1/messages at
# `/anthropic/v1/messages`. Set ANTHROPIC_BASE_URL to `http://host:4242/anthropic`
# (the trailing /anthropic is the integration prefix, NOT a separate path).
#
# Host resolution: defaults to ceres.local (mDNS, works from ceres/pluto/make).
# Override with BIFROST_HOST env var (e.g. BIFROST_HOST=localhost or 192.168.0.74).
# The proxy binds 0.0.0.0:4242; only ceres runs the systemd unit, peers connect.
typeset -g _BIFROST_HOST="${BIFROST_HOST:-ceres.local}"
typeset -g _BIFROST_PORT="${BIFROST_PORT:-4242}"
typeset -g _BIFROST_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/bifrost"
typeset -g _BIFROST_BASE_URL="http://${_BIFROST_HOST}:${_BIFROST_PORT}"
typeset -g _BIFROST_ANTHROPIC_URL="${_BIFROST_BASE_URL}/anthropic"

# True when this machine owns the systemd unit (ceres). On peers, ensure_service
# becomes a remote-reachability probe instead of a systemctl invocation.
_bifrost_is_host() {
  [[ "$(hostname -s 2>/dev/null)" == "ceres" ]]
}

# Resolve the master key. Source of truth is the encrypted secret
# (`zsh/env.d/90_secrets.zsh` exports BIFROST_MASTER_KEY at login). Falls back
# to LITELLM_MASTER_KEY (legacy name during transition) and finally to the
# local key file on ceres for first-run bootstrap.
#
# Bifrost OSS auth is dashboard-driven (Workspace → Config → Security). When
# inference-call auth is OFF (default), the master key is unused for routing —
# but we resolve it anyway so it's available for future auth enablement and for
# helpers like bifrost-probe that may need it.
_bifrost_master_key() {
  if [[ -n "${BIFROST_MASTER_KEY:-}" ]]; then
    print -r -- "$BIFROST_MASTER_KEY"
    return 0
  fi
  if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
    print -r -- "$LITELLM_MASTER_KEY"
    return 0
  fi
  local keyfile="$_BIFROST_STATE/master-key"
  if [[ -r $keyfile ]]; then
    local key
    key="$(<"$keyfile")"
    print -r -- "${key%$'\n'}"
    return 0
  fi
  print -u2 -- "_bifrost_master_key: BIFROST_MASTER_KEY/LITELLM_MASTER_KEY unset and $keyfile unreadable"
  return 1
}

if (( ${+commands[claude]} )); then

  # Ensure Bifrost service is running (idempotent on ceres; remote probe elsewhere).
  # On ceres: writes/refreshes env file, starts service if down.
  # Off ceres: just probes :4242/health for reachability.
  _bifrost_ensure_service() {
    if ! _bifrost_is_host; then
      if ! curl -sf --max-time 3 "${_BIFROST_BASE_URL}/health" >/dev/null 2>&1; then
        print "Bifrost gateway unreachable at ${_BIFROST_BASE_URL}. Is ceres up?" >&2
        return 1
      fi
      return 0
    fi
    local statedir="$_BIFROST_STATE"
    local envfile="$statedir/env"

    [[ -d $statedir ]] || { mkdir -p "$statedir" && chmod 700 "$statedir" }

    # Generate stable master key if missing (first-run bootstrap; normally the
    # secret env var is the source of truth — see _bifrost_master_key).
    local keyfile="$statedir/master-key"
    if [[ -z "${BIFROST_MASTER_KEY:-}" && -z "${LITELLM_MASTER_KEY:-}" && ! -f $keyfile ]]; then
      print "sk-bifrost-$(head -c 16 /dev/urandom | xxd -p)" > "$keyfile"
      chmod 600 "$keyfile"
      print "Bootstrapped new master key at $keyfile — copy into zsh/env.d/90_secrets.zsh as BIFROST_MASTER_KEY then run scripts/save-secrets.zsh" >&2
    fi
    # Mirror the env var into the file so legacy readers stay consistent.
    local resolved_key
    resolved_key="${BIFROST_MASTER_KEY:-${LITELLM_MASTER_KEY:-}}"
    if [[ -n "$resolved_key" && "$resolved_key" != "$(<"$keyfile" 2>/dev/null)" ]]; then
      print -r -- "$resolved_key" > "$keyfile"
      chmod 600 "$keyfile"
    fi

    # Write env file for systemd. Self-healing: provider keys come from current
    # shell env, so any rotation in zsh/env.d/*secrets* propagates to the
    # gateway on next ccfw/ccz/cc-fast call.
    local hashfile="$statedir/env.sha1"
    local prev_hash=""
    [[ -f $hashfile ]] && prev_hash=$(<"$hashfile")
    {
      print "BIFROST_MASTER_KEY=$(_bifrost_master_key)"
      print "MINIMAX_API_KEY=$MINIMAX_API_KEY"
      print "FIREWORKS_API_KEY=$FIREWORKS_API_KEY"
      print "CEREBRAS_API_KEY=$CEREBRAS_API_KEY"
      print "CEREBRAS_FREE_API_KEY=$CEREBRAS_FREE_API_KEY"
      print "Z_AI_API_KEY=$Z_AI_API_KEY"
      print "OPENAI_API_KEY=$OPENAI_API_KEY"
    } > "$envfile"
    chmod 600 "$envfile"
    local new_hash=$(sha1sum "$envfile" | cut -d' ' -f1)
    print "$new_hash" > "$hashfile"
    chmod 600 "$hashfile"

    # If env file content changed AND service is already running, restart so
    # systemd re-reads the EnvironmentFile.
    if [[ -n $prev_hash && $prev_hash != $new_hash ]] && \
       systemctl --user is-active --quiet bifrost-gateway; then
      print "Bifrost env changed — restarting gateway"
      systemctl --user restart bifrost-gateway
    fi

    # Start service if not already active
    if ! systemctl --user is-active --quiet bifrost-gateway; then
      systemctl --user start bifrost-gateway || {
        print "Bifrost gateway failed to start. Check: bifrost-log" >&2
        return 1
      }

      # Wait for health (max 20s)
      local i=0
      while ! curl -sf "${_BIFROST_BASE_URL}/health" >/dev/null 2>&1; do
        sleep 1
        if (( ++i > 20 )); then
          print "Bifrost gateway failed health check. Check: bifrost-log" >&2
          return 1
        fi
      done
      print "Bifrost gateway started on :$_BIFROST_PORT"
    fi
    return 0
  }

  # Convenience: every alias's per-call setup converges through this.
  _bifrost_call_env() {
    local model="$1"; shift
    local sonnet="${1:-$model}"; shift 2>/dev/null
    local haiku="${1:-$model}"; shift 2>/dev/null
    local small_fast="${1:-$haiku}"; shift 2>/dev/null

    # Bifrost OSS inference auth is OFF by default — leave Authorization header
    # blank. When user enables auth via dashboard, replace with Basic-auth
    # username:password Bearer-base64 (see docs/bifrost.md "Auth setup").
    print -r -- \
      "CLAUDE_CODE_ATTRIBUTION_HEADER=0" \
      "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" \
      "ANTHROPIC_API_KEY=" \
      "ANTHROPIC_AUTH_TOKEN=" \
      "ANTHROPIC_BASE_URL=${_BIFROST_ANTHROPIC_URL}" \
      "ANTHROPIC_MODEL=${model}" \
      "ANTHROPIC_DEFAULT_OPUS_MODEL=${model}" \
      "ANTHROPIC_DEFAULT_SONNET_MODEL=${sonnet}" \
      "ANTHROPIC_DEFAULT_HAIKU_MODEL=${haiku}" \
      "ANTHROPIC_SMALL_FAST_MODEL=${small_fast}" \
      "API_TIMEOUT_MS=3000000"
  }

  # ============================================================
  # ALIASES — the working surface for `claude` invocations
  # ============================================================

  # ccl: generic Bifrost-routed Claude. Default models, no role pinning.
  # Use this when you want "claude through the proxy" without picking a tier.
  ccl() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
      claude "$@"
  }

  ccl-happy() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # ccfw: Fireworks-fronted fleet via Bifrost.
  # Routes opus → fleet-opus → Fireworks Kimi-K2.6 (fallbacks Z.AI/MiniMax),
  # sonnet → fleet-sonnet → Fireworks GLM-5.1, haiku → fleet-haiku → Cerebras
  # gpt-oss-120b, small-fast → fleet-small-fast. The fleet-* names are
  # routing_rules in Bifrost config.json (governance.routing_rules[]) that
  # carry the LiteLLM-era fallback chains.
  ccfw() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      claude --model "$opus_model" "$@"
  }

  ccfw-happy() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # ccz: Z.AI single-stream foreground tier via Bifrost.
  # Foreground/opus/sonnet → fleet-ccz routing rule (primary Z.AI GLM-4.6 with
  # concurrency=1 in the zai provider config to enforce single-stream
  # subscription saturation discipline; fallbacks Fireworks/MiniMax).
  # haiku → fleet-haiku, small-fast → fleet-small-fast.
  # Legacy direct-Z.AI alias `ccz-direct` remains in webfront/scripts/agent-aliases.zsh.
  ccz() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local zai_model="fleet-ccz"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ENABLE_TOOL_SEARCH=false \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      claude --model "$zai_model" "$@"
  }

  ccz-happy() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local zai_model="fleet-ccz"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ENABLE_TOOL_SEARCH=false \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$zai_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # cc-fast: foreground GLM-4.7 on Cerebras (~3000 t/s wafer-scale) via
  # fleet-cc-fast routing rule (fallbacks Fireworks GLM-5.1 / Z.AI GLM-4.6).
  # Background sub-agents and tier-coded requests route through fleet-opus /
  # fleet-sonnet / fleet-haiku / fleet-small-fast — the GLM-4.7-on-Cerebras
  # path is NEVER picked for sub-agent work, only for the interactive thread.
  cc-fast() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local glm_model="fleet-cc-fast"
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$glm_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      claude --model "$glm_model" "$@"
  }

  cc-fast-happy() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local glm_model="fleet-cc-fast"
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="$_BIFROST_ANTHROPIC_URL" \
    ANTHROPIC_MODEL="$glm_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
    ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # ============================================================
  # OPERATIONAL HELPERS
  # ============================================================

  bifrost-health() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    print "=== /health ==="
    curl -sS "${_BIFROST_BASE_URL}/health" | jq . 2>/dev/null || \
      curl -sS "${_BIFROST_BASE_URL}/health"
    print "\n=== /api/providers ==="
    curl -sS "${_BIFROST_BASE_URL}/api/providers" | jq '.providers[] | {name, key_count: (.keys|length), status: .provider_status}' 2>/dev/null
  }

  bifrost-probe() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local model="${1:?usage: bifrost-probe <provider/model> [prompt]}"
    local prompt="${2:-reply with the single word ready}"
    curl -sS "${_BIFROST_BASE_URL}/anthropic/v1/messages" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      -d "{\"model\":\"$model\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}]}" \
      | jq . 2>/dev/null || cat
  }

  bifrost-probe-stream() {
    emulate -L zsh
    _bifrost_ensure_service || return 1
    local model="${1:?usage: bifrost-probe-stream <provider/model>}"
    curl -sSN "${_BIFROST_BASE_URL}/anthropic/v1/messages" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      -d "{\"model\":\"$model\",\"max_tokens\":256,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"count from 1 to 10\"}]}"
  }

  bifrost-stop() {
    emulate -L zsh
    if ! _bifrost_is_host; then
      print "bifrost-stop: service runs on ceres; ssh ceres bifrost-stop" >&2
      return 1
    fi
    if systemctl --user is-active --quiet bifrost-gateway; then
      systemctl --user stop bifrost-gateway
      print "Bifrost gateway stopped."
    else
      print "Bifrost gateway not running."
    fi
  }

  bifrost-status() {
    emulate -L zsh
    if ! _bifrost_is_host; then
      print "bifrost-status: service runs on ceres; ssh ceres bifrost-status" >&2
      return 1
    fi
    systemctl --user status bifrost-gateway --no-pager 2>/dev/null
  }

  bifrost-log() {
    emulate -L zsh
    if ! _bifrost_is_host; then
      print "bifrost-log: log file is on ceres; ssh ceres bifrost-log" >&2
      return 1
    fi
    local logfile="$_BIFROST_STATE/proxy.log"
    if [[ ! -f $logfile ]]; then
      print "No log file yet: $logfile" >&2
      return 1
    fi
    tail "${@:--f}" "$logfile"
  }

  bifrost-restart() {
    emulate -L zsh
    _bifrost_is_host || { print "bifrost-restart: runs on ceres" >&2; return 1; }
    systemctl --user restart bifrost-gateway
    _bifrost_ensure_service
  }

  # bifrost-ui: open the dashboard in default browser. Use to enable inference
  # auth (Workspace → Config → Security) which is OFF by default in OSS.
  bifrost-ui() {
    emulate -L zsh
    local url="${_BIFROST_BASE_URL}"
    if (( ${+commands[xdg-open]} )); then
      xdg-open "$url" >/dev/null 2>&1
    elif (( ${+commands[open]} )); then
      open "$url"
    else
      print "Bifrost UI: $url"
    fi
  }

fi
