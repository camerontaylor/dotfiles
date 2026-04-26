# LiteLLM proxy: systemd user service
# Real Opus → use ccc (direct Anthropic OAuth, NOT this proxy)
# Sonnet/Haiku (claude-sonnet-4-6 / claude-haiku-4-5-20251001) → MiniMax via proxy (ccl)
# Eclectic tier (Z.AI bg / Fireworks / Cerebras free+paid) → ccfw, cczbg, role aliases
if (( ${+commands[litellm]} )); then

  typeset -g _LITELLM_PORT=4199
  typeset -g _LITELLM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/litellm"

  # Ensure systemd service is running (idempotent)
  _litellm_ensure_service() {
    local statedir="$_LITELLM_STATE"
    local envfile="$statedir/env"

    [[ -d $statedir ]] || { mkdir -p "$statedir" && chmod 700 "$statedir" }

    # Generate stable master key if missing
    local keyfile="$statedir/master-key"
    if [[ ! -f $keyfile ]]; then
      print "sk-litellm-$(head -c 16 /dev/urandom | xxd -p)" > "$keyfile"
      chmod 600 "$keyfile"
    fi

    # Write env file for systemd (refreshes keys each start).
    # Self-healing: provider keys come from current shell env, so any rotation
    # in zsh/env.d/*secrets* propagates to the proxy on next ccl/ccfw/cczbg call.
    local hashfile="$statedir/env.sha1"
    local prev_hash=""
    [[ -f $hashfile ]] && prev_hash=$(<"$hashfile")
    {
      print "LITELLM_MASTER_KEY=$(<"$keyfile")"
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
    # systemd re-reads the EnvironmentFile. Skip restart on first-write
    # (no prev_hash) — service start path below handles that case.
    if [[ -n $prev_hash && $prev_hash != $new_hash ]] && \
       systemctl --user is-active --quiet litellm-proxy; then
      print "LiteLLM env changed — restarting proxy"
      systemctl --user restart litellm-proxy
    fi

    # Start service if not already active
    if ! systemctl --user is-active --quiet litellm-proxy; then
      systemctl --user start litellm-proxy || {
        print "LiteLLM service failed. Check: ccl-log" >&2
        return 1
      }

      # Wait for health (max 20s)
      local i=0
      while ! curl -sf "http://localhost:$_LITELLM_PORT/health/liveliness" 2>/dev/null | grep -q "alive"; do
        sleep 1
        if (( ++i > 20 )); then
          print "LiteLLM proxy failed health check. Check: ccl-log" >&2
          return 1
        fi
      done
      print "LiteLLM proxy started on :$_LITELLM_PORT"
    fi
    return 0
  }

  ccl() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    # CLAUDE_CODE_ATTRIBUTION_HEADER=0 stops Claude Code 2.1.36+ from emitting
    # the per-request x-anthropic-billing-header that breaks prompt caching.
    # Proxy auth via x-litellm-api-key; Claude Code's x-api-key (OAuth) passes through to Anthropic.
    # ANTHROPIC_SMALL_FAST_MODEL=fleet-haiku routes background sub-agent traffic
    # to the cheap-fast tier (cerebras-free-8b → cerebras-paid-8b → cerebras-paid-oss120
    # → minimax-m2.7) per router_settings.fallbacks in config.yaml.
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
      claude "$@"
  }

  ccl-happy() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # ccfw: Fireworks-fronted fleet via LiteLLM proxy.
  # Routes via role aliases (opus → kimi-k2.6, sonnet → glm-5.1, haiku → cerebras-free-8b)
  # with fallback chains defined in config.yaml. Real Opus is NOT here — use ccc for that.
  ccfw() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="fleet-sonnet" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      claude --model fleet-opus "$@"
  }

  ccfw-happy() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="fleet-sonnet" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # cczbg: Z.AI single-stream background tier via LiteLLM proxy.
  # All roles route to glm-5.1-bg (max_parallel_requests=1). Use for low-priority
  # worktrees. Falls back to glm-5.1-fast (Fireworks) when 429s.
  cczbg() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ENABLE_TOOL_SEARCH=false \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      claude --model glm-5.1-bg "$@"
  }

  cczbg-happy() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ENABLE_TOOL_SEARCH=false \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="glm-5.1-bg" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  # cc-fast: foreground turns hit GLM-4.7 on Cerebras (~3000 t/s wafer-scale).
  # Background sub-agents and tier-coded requests route through the standard
  # fleet (fleet-opus / fleet-sonnet / fleet-haiku) — glm-4.7 is NEVER picked
  # for sub-agent work, only for the interactive thread.
  cc-fast() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="glm-4.7-cerebras" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="fleet-sonnet" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      claude --model glm-4.7-cerebras "$@"
  }

  cc-fast-happy() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_AUTH_TOKEN="" \
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
    ANTHROPIC_MODEL="glm-4.7-cerebras" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="fleet-opus" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="fleet-sonnet" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="fleet-haiku" \
    ANTHROPIC_SMALL_FAST_MODEL="fleet-small-fast" \
    API_TIMEOUT_MS="3000000" \
      happy yolo --dangerously-skip-permissions "$@"
  }

  ccl-health() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    print "=== /health/readiness ==="
    curl -sS "http://localhost:$_LITELLM_PORT/health/readiness" | jq . 2>/dev/null || \
      curl -sS "http://localhost:$_LITELLM_PORT/health/readiness"
    print "\n=== /health (per-deployment) ==="
    # NOTE: LiteLLM auth path requires "Bearer " prefix even on the custom
    # x-litellm-api-key header (hardcoded in litellm.proxy.auth.user_api_key_auth).
    curl -sS "http://localhost:$_LITELLM_PORT/health" \
      -H "x-litellm-api-key: Bearer $master_key" | jq . 2>/dev/null || \
      curl -sS "http://localhost:$_LITELLM_PORT/health" \
      -H "x-litellm-api-key: Bearer $master_key"
  }

  ccl-probe() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local model="${1:?usage: ccl-probe <model_name> [prompt]}"
    local prompt="${2:-reply with the single word ready}"
    local master_key=$(<"$_LITELLM_STATE/master-key")
    curl -sS "http://localhost:$_LITELLM_PORT/v1/messages" \
      -H "x-litellm-api-key: Bearer $master_key" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      -d "{\"model\":\"$model\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}]}" \
      | jq . 2>/dev/null || cat
  }

  ccl-stop() {
    emulate -L zsh
    if systemctl --user is-active --quiet litellm-proxy; then
      systemctl --user stop litellm-proxy
      print "LiteLLM proxy stopped."
    else
      print "LiteLLM proxy not running."
    fi
  }

  ccl-status() {
    emulate -L zsh
    systemctl --user status litellm-proxy --no-pager 2>/dev/null
  }

  ccl-log() {
    emulate -L zsh
    local logfile="$_LITELLM_STATE/proxy.log"
    if [[ ! -f $logfile ]]; then
      print "No log file yet: $logfile" >&2
      return 1
    fi
    tail "${@:--f}" "$logfile"
  }

fi
