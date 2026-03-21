# LiteLLM proxy: systemd user service
# Opus → Anthropic (OAuth passthrough), Sonnet/Haiku → MiniMax
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

    # Write env file for systemd (refreshes keys each start)
    {
      print "MINIMAX_API_KEY=$MINIMAX_API_KEY"
      print "LITELLM_MASTER_KEY=$(<"$keyfile")"
    } > "$envfile"
    chmod 600 "$envfile"

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
    # Proxy auth via x-litellm-api-key; Claude Code's x-api-key (OAuth) passes through to Anthropic
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      claude "$@"
  }

  ccl-happy() {
    emulate -L zsh
    _litellm_ensure_service || return 1
    local master_key=$(<"$_LITELLM_STATE/master-key")
    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      happy yolo --dangerously-skip-permissions "$@"
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
