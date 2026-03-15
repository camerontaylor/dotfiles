# LiteLLM proxy functions: Claude subscription main + MiniMax subagents
# Proxy starts on-demand, stops when Claude Code exits
if (( ${+commands[litellm]} )); then

  ccl() {
    emulate -L zsh
    local port=4123
    local logfile="/tmp/litellm-proxy.log"
    local master_key="sk-litellm-$(head -c 16 /dev/urandom | xxd -p)"

    # Start proxy in background
    LITELLM_MASTER_KEY="$master_key" MINIMAX_API_KEY="$MINIMAX_API_KEY" \
      litellm --config ~/.config/litellm/config.yaml --port $port \
      > "$logfile" 2>&1 &
    local proxy_pid=$!

    # Ensure cleanup on exit/interrupt
    trap "kill $proxy_pid 2>/dev/null; wait $proxy_pid 2>/dev/null" EXIT INT TERM

    # Wait for proxy health (max 15s)
    local i=0
    while ! curl -sf "http://localhost:$port/health/liveliness" > /dev/null 2>&1; do
      sleep 1
      if (( ++i > 15 )); then
        print "LiteLLM proxy failed to start. Check $logfile" >&2
        kill $proxy_pid 2>/dev/null
        trap - EXIT INT TERM
        return 1
      fi
    done
    print "LiteLLM proxy running on :$port (PID $proxy_pid)"

    # Launch Claude Code with dual auth: OAuth in Authorization header, proxy key in custom header
    ANTHROPIC_BASE_URL="http://localhost:$port" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      claude "$@"

    # Cleanup (trap also handles this, but be explicit)
    kill $proxy_pid 2>/dev/null
    wait $proxy_pid 2>/dev/null
    trap - EXIT INT TERM
    print "LiteLLM proxy stopped."
  }

  ccl-happy() {
    emulate -L zsh
    local port=4123
    local logfile="/tmp/litellm-proxy.log"
    local master_key="sk-litellm-$(head -c 16 /dev/urandom | xxd -p)"

    LITELLM_MASTER_KEY="$master_key" MINIMAX_API_KEY="$MINIMAX_API_KEY" \
      litellm --config ~/.config/litellm/config.yaml --port $port \
      > "$logfile" 2>&1 &
    local proxy_pid=$!

    trap "kill $proxy_pid 2>/dev/null; wait $proxy_pid 2>/dev/null" EXIT INT TERM

    local i=0
    while ! curl -sf "http://localhost:$port/health/liveliness" > /dev/null 2>&1; do
      sleep 1
      if (( ++i > 15 )); then
        print "LiteLLM proxy failed to start. Check $logfile" >&2
        kill $proxy_pid 2>/dev/null
        trap - EXIT INT TERM
        return 1
      fi
    done
    print "LiteLLM proxy running on :$port (PID $proxy_pid)"

    ANTHROPIC_BASE_URL="http://localhost:$port" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      happy yolo --dangerously-skip-permissions "$@"

    kill $proxy_pid 2>/dev/null
    wait $proxy_pid 2>/dev/null
    trap - EXIT INT TERM
    print "LiteLLM proxy stopped."
  }

fi
