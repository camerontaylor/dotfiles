# LiteLLM proxy: lazy singleton with idle watchdog
# Opus → Anthropic (OAuth passthrough), Sonnet/Haiku → MiniMax
if (( ${+commands[litellm]} )); then

  typeset -g _LITELLM_PORT=4123
  typeset -g _LITELLM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/litellm"
  typeset -g _LITELLM_IDLE_TIMEOUT=1800  # 30 minutes in seconds

  # Ensure proxy is running, start if needed
  _litellm_ensure_proxy() {
    local statedir="$_LITELLM_STATE"
    local pidfile="$statedir/proxy.pid"
    local keyfile="$statedir/master-key"
    local logfile="$statedir/proxy.log"
    local activefile="$statedir/last-active"
    local port=$_LITELLM_PORT

    # Create state dir with restrictive perms (holds master key)
    [[ -d $statedir ]] || mkdir -p "$statedir" && chmod 700 "$statedir"

    # Check for existing healthy proxy
    if [[ -f $pidfile ]]; then
      local pid=$(<"$pidfile")
      if kill -0 "$pid" 2>/dev/null \
         && curl -sf "http://localhost:$port/health/liveliness" > /dev/null 2>&1; then
        return 0  # proxy already running and healthy
      fi
      # Stale pidfile — clean up
      kill "$pid" 2>/dev/null
      rm -f "$pidfile"
    fi

    # Generate stable master key if missing
    if [[ ! -f $keyfile ]]; then
      print "sk-litellm-$(head -c 16 /dev/urandom | xxd -p)" > "$keyfile"
      chmod 600 "$keyfile"
    fi
    local master_key=$(<"$keyfile")

    # Start proxy detached from shell
    LITELLM_MASTER_KEY="$master_key" MINIMAX_API_KEY="$MINIMAX_API_KEY" \
      setsid litellm --config ~/.config/litellm/config.yaml --port $port \
      >> "$logfile" 2>&1 &
    local proxy_pid=$!
    disown $proxy_pid 2>/dev/null

    # Wait for health (max 15s)
    local i=0
    while ! curl -sf "http://localhost:$port/health/liveliness" > /dev/null 2>&1; do
      sleep 1
      if (( ++i > 15 )); then
        print "LiteLLM proxy failed to start. Check $logfile" >&2
        kill $proxy_pid 2>/dev/null
        return 1
      fi
    done

    print "$proxy_pid" > "$pidfile"
    touch "$activefile"
    print "LiteLLM proxy started on :$port (PID $proxy_pid)"

    # Launch idle watchdog (detached)
    _litellm_watchdog &
    disown $! 2>/dev/null
    return 0
  }

  # Background watchdog: kills proxy after idle timeout
  _litellm_watchdog() {
    local pidfile="$_LITELLM_STATE/proxy.pid"
    local activefile="$_LITELLM_STATE/last-active"
    local port=$_LITELLM_PORT
    local timeout=$_LITELLM_IDLE_TIMEOUT

    while true; do
      sleep 300  # check every 5 minutes

      # Exit if proxy is gone
      if [[ ! -f $pidfile ]] || ! kill -0 $(<"$pidfile") 2>/dev/null; then
        rm -f "$pidfile"
        return
      fi

      # Check idle time via last-active mtime
      if [[ -f $activefile ]]; then
        local mtime=$(stat -c %Y "$activefile" 2>/dev/null)
        local now=$(date +%s)
        if (( now - mtime > timeout )); then
          local pid=$(<"$pidfile")
          kill "$pid" 2>/dev/null
          rm -f "$pidfile"
          print "LiteLLM proxy stopped (idle ${timeout}s)." >> "$_LITELLM_STATE/proxy.log"
          return
        fi
      fi
    done
  }

  ccl() {
    emulate -L zsh
    _litellm_ensure_proxy || return 1

    local master_key=$(<"$_LITELLM_STATE/master-key")
    touch "$_LITELLM_STATE/last-active"

    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      claude "$@"

    touch "$_LITELLM_STATE/last-active"
  }

  ccl-happy() {
    emulate -L zsh
    _litellm_ensure_proxy || return 1

    local master_key=$(<"$_LITELLM_STATE/master-key")
    touch "$_LITELLM_STATE/last-active"

    ANTHROPIC_BASE_URL="http://localhost:$_LITELLM_PORT" \
    ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key" \
      happy yolo --dangerously-skip-permissions "$@"

    touch "$_LITELLM_STATE/last-active"
  }

  ccl-stop() {
    emulate -L zsh
    local pidfile="$_LITELLM_STATE/proxy.pid"
    if [[ -f $pidfile ]]; then
      local pid=$(<"$pidfile")
      kill "$pid" 2>/dev/null && print "LiteLLM proxy stopped (PID $pid)."
      rm -f "$pidfile"
    else
      print "No LiteLLM proxy running."
    fi
  }

  ccl-status() {
    emulate -L zsh
    local pidfile="$_LITELLM_STATE/proxy.pid"
    if [[ -f $pidfile ]] && kill -0 $(<"$pidfile") 2>/dev/null; then
      local pid=$(<"$pidfile")
      local active="$_LITELLM_STATE/last-active"
      local idle="?"
      if [[ -f $active ]]; then
        local mtime=$(stat -c %Y "$active" 2>/dev/null)
        local now=$(date +%s)
        idle="$(( (now - mtime) / 60 ))m"
      fi
      print "LiteLLM proxy running (PID $pid, port $_LITELLM_PORT, idle $idle)"
    else
      print "LiteLLM proxy not running."
      rm -f "$pidfile" 2>/dev/null
    fi
  }

fi
