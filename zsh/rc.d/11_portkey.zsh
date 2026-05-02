# Portkey AI Gateway: self-hosted OSS gateway helpers.
# Portkey backs the ccfw/ccz/cc-fast alias families. The cc-fast-pk names are
# kept as compatibility wrappers over the same Portkey route.

# Endpoint convention: Portkey serves Anthropic-compatible /v1/messages at the
# gateway root. Set ANTHROPIC_BASE_URL to http://host:8787 (no /anthropic suffix).
typeset -g _PORTKEY_HOST="${PORTKEY_HOST:-ceres.local}"
typeset -g _PORTKEY_PORT="${PORTKEY_PORT:-8787}"
typeset -g _PORTKEY_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/portkey"
typeset -g _PORTKEY_BASE_URL="http://${_PORTKEY_HOST}:${_PORTKEY_PORT}"
typeset -g _PORTKEY_CONFIG_FILE="${PORTKEY_CONFIG_FILE:-$HOME/.local/dotfiles/configs/portkey/config.json}"
typeset -g _PORTKEY_CONFIG_DIR="${_PORTKEY_CONFIG_FILE:h}"
typeset -g _PORTKEY_FORK_DIR="${PORTKEY_FORK_DIR:-/home/ctaylor/repos/worktrees/portkey-gateway-2.0.0}"
typeset -g _PORTKEY_LOCAL_TOKEN_FILE="${PORTKEY_LOCAL_TOKEN_FILE:-$_PORTKEY_STATE/local-api-key}"
typeset -g _PORTKEY_TIMEOUT_MS="${PORTKEY_TIMEOUT_MS:-75000}"

_portkey_is_host() {
  [[ "$(hostname -s 2>/dev/null)" == "ceres" ]]
}

_portkey_config_version() {
  emulate -L zsh
  (( $# > 0 )) || {
    print -u2 -- "usage: _portkey_config_version <route> [route...]"
    return 1
  }

  local routes_json hash
  routes_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)" || return $?
  hash="$(
    jq -S -c --argjson route_names "$routes_json" '
      def strip_secrets:
        if type == "object" then
          del(.api_key, .apiKey, .credentials, .key)
          | with_entries(select(.key | test("(?i)(secret|token|password|authorization)$") | not))
          | with_entries(.value |= strip_secrets)
        elif type == "array" then map(strip_secrets)
        else . end;
      {
        routes: (
          .routes as $routes
          | $route_names
          | map({key: ., value: ($routes[.].portkey_config // error("unknown route: " + .))})
          | from_entries
        )
      }
      | strip_secrets
    ' "$_PORTKEY_CONFIG_FILE" | sha256sum | awk '{print $1}'
  )" || return $?

  print -r -- "local-sha256:${hash[1,16]}"
}

_portkey_config_slug() {
  emulate -L zsh
  local alias_name="${1:?usage: _portkey_config_slug <alias> <route> [route...]}"
  shift
  (( $# > 0 )) || {
    print -u2 -- "usage: _portkey_config_slug <alias> <route> [route...]"
    return 1
  }

  local version slug_hash safe_alias
  version="$(_portkey_config_version "$@")" || return $?
  slug_hash="$(printf '%s:%s\n' "$alias_name" "$version" | sha256sum | awk '{print substr($1,1,12)}')" || return $?
  safe_alias="${alias_name//[^A-Za-z0-9-]/-}"
  print -r -- "pc-local-${safe_alias}-${slug_hash}"
}

_portkey_local_token() {
  emulate -L zsh
  if [[ -n ${PORTKEY_LOCAL_API_KEY:-} ]]; then
    print -r -- "$PORTKEY_LOCAL_API_KEY"
    return 0
  fi

  if [[ -r $_PORTKEY_LOCAL_TOKEN_FILE ]]; then
    <"$_PORTKEY_LOCAL_TOKEN_FILE"
    return 0
  fi

  _portkey_ensure_local_token_file || return $?
  <"$_PORTKEY_LOCAL_TOKEN_FILE"
}

_portkey_session_id() {
  emulate -L zsh
  local session="${PORTKEY_STICKY_SESSION:-${OMX_SESSION_ID:-${CODEX_SESSION_ID:-${TMUX_PANE:-}}}}"
  if [[ -n $session ]]; then
    print -r -- "$session"
    return 0
  fi

  [[ -d $_PORTKEY_STATE ]] || mkdir -p "$_PORTKEY_STATE"
  local session_file="$_PORTKEY_STATE/sticky-session-id"
  if [[ ! -r $session_file ]]; then
    umask 077
    if (( ${+commands[uuidgen]} )); then
      uuidgen >"$session_file"
    else
      printf '%s-%s\n' "$(date +%s)" "$RANDOM" >"$session_file"
    fi
  fi
  <"$session_file"
}

_portkey_headers() {
  emulate -L zsh
  local alias_name="${1:?usage: _portkey_headers <alias> <route> [route...]}"
  shift
  (( $# > 0 )) || {
    print -u2 -- "usage: _portkey_headers <alias> <route> [route...]"
    return 1
  }

  local token config_slug config_version session_id metadata
  token="$(_portkey_local_token)" || return $?
  config_slug="$(_portkey_config_slug "$alias_name" "$@")" || return $?
  config_version="$(_portkey_config_version "$@")" || return $?
  session_id="$(_portkey_session_id)" || return $?
  metadata="$(jq -cn --arg portkey_session "${alias_name}:${session_id}" '{portkey_session: $portkey_session}')" || return $?

  print -r -- "x-portkey-api-key: ${token}"
  print -r -- "x-portkey-config: ${config_slug}"
  print -r -- "x-portkey-config-version: ${config_version}"
  print -r -- "x-portkey-metadata: ${metadata}"
}

_portkey_header_args() {
  emulate -L zsh
  local headers="${1:?usage: _portkey_header_args <headers>}"
  local header
  for header in "${(@f)headers}"; do
    print -r -- "-H"
    print -r -- "$header"
  done
}

_portkey_prepare_local_conf() {
  emulate -L zsh
  [[ -d $_PORTKEY_CONFIG_DIR ]] || mkdir -p "$_PORTKEY_CONFIG_DIR"
  if [[ ! -e "$_PORTKEY_CONFIG_DIR/conf.json" ]]; then
    ln -s "$_PORTKEY_CONFIG_FILE" "$_PORTKEY_CONFIG_DIR/conf.json"
  fi
}

_portkey_ensure_local_token_file() {
  emulate -L zsh
  [[ -d $_PORTKEY_STATE ]] || mkdir -p "$_PORTKEY_STATE"
  if [[ -n ${PORTKEY_LOCAL_API_KEY:-} ]]; then
    umask 077
    print -rn -- "$PORTKEY_LOCAL_API_KEY" >"$_PORTKEY_LOCAL_TOKEN_FILE"
  elif [[ ! -r $_PORTKEY_LOCAL_TOKEN_FILE ]]; then
    local token
    if (( ${+commands[openssl]} )); then
      token="$(openssl rand -hex 32)" || return $?
    elif (( ${+commands[uuidgen]} )); then
      token="$(uuidgen)$(uuidgen)" || return $?
    else
      token="$(printf '%s-%s-%s\n' "$(date +%s)" "$RANDOM" "$RANDOM")"
    fi
    umask 077
    print -rn -- "$token" >"$_PORTKEY_LOCAL_TOKEN_FILE"
  fi
}

_portkey_gateway_env() {
  emulate -L zsh
  PORT="$_PORTKEY_PORT" \
  PORTKEY_API_KEY="$_PORTKEY_LOCAL_TOKEN_FILE" \
  PORTKEY_LOCAL_API_KEY="$_PORTKEY_LOCAL_TOKEN_FILE" \
  FETCH_SETTINGS_FROM_FILE=true \
  PORTKEY_LOCAL_MODE=true \
  PORTKEY_TELEMETRY=false \
  DISABLE_ANALYTICS=true \
  ENABLE_TRACING=false \
  MONITOR_METRICS=false \
  CACHE_STORE=memory \
  GATEWAY_CACHE_MODE=memory \
    "$@"
}

_portkey_ensure_service() {
  emulate -L zsh
  if ! _portkey_is_host; then
    curl -sf --max-time 3 "$_PORTKEY_BASE_URL/v1/health" >/dev/null 2>&1 || {
      print "Portkey gateway unreachable at $_PORTKEY_BASE_URL. Is ceres up?" >&2
      return 1
    }
    return 0
  fi

  _portkey_ensure_local_token_file || return $?
  _portkey_prepare_local_conf || return $?

  local start_script="$_PORTKEY_FORK_DIR/build/start-server.js"
  [[ -r $start_script ]] || {
    print "Portkey 2.0.0 fork build is missing: $start_script" >&2
    return 1
  }

  curl -sf --max-time 3 "$_PORTKEY_BASE_URL/v1/health" >/dev/null 2>&1 && return 0

  local pidfile="$_PORTKEY_STATE/gateway.pid"
  local unit="portkey-gateway.service"
  if (( ${+commands[systemctl]} )) && [[ -r "$HOME/.config/systemd/user/$unit" ]]; then
    print "Starting Portkey 2.0.0 fork gateway on :$_PORTKEY_PORT via systemd" >&2
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if systemctl --user start "$unit" >/dev/null 2>&1; then
      local i=0
      while ! curl -sf --max-time 2 "$_PORTKEY_BASE_URL/v1/health" >/dev/null 2>&1; do
        sleep 1
        if (( ++i > 20 )); then
          print "Portkey gateway failed readiness check. Check: systemctl --user status $unit" >&2
          return 1
        fi
      done
      local main_pid
      main_pid="$(systemctl --user show "$unit" -p MainPID --value 2>/dev/null || true)"
      [[ $main_pid == <-> && $main_pid != 0 ]] && print "$main_pid" >"$pidfile"
      print "Portkey gateway started on :$_PORTKEY_PORT" >&2
      return 0
    fi
    print "systemd start failed for $unit; falling back to direct node launch" >&2
  fi

  if [[ -r $pidfile ]]; then
    local pid
    pid="$(<"$pidfile")"
    if [[ -n $pid ]] && kill -0 "$pid" >/dev/null 2>&1; then
      curl -sf --max-time 3 "$_PORTKEY_BASE_URL/v1/health" >/dev/null 2>&1 && return 0
    fi
    rm -f "$pidfile"
  fi

  print "Starting Portkey 2.0.0 fork gateway on :$_PORTKEY_PORT" >&2
  (
    cd "$_PORTKEY_CONFIG_DIR" || exit 1
    if (( ${+commands[nohup]} )); then
      _portkey_gateway_env nohup node "$start_script" --llm-node --port="$_PORTKEY_PORT" >"$_PORTKEY_STATE/gateway.log" 2>&1 </dev/null &!
    else
      _portkey_gateway_env node "$start_script" --llm-node --port="$_PORTKEY_PORT" >"$_PORTKEY_STATE/gateway.log" 2>&1 </dev/null &!
    fi
    print $! >"$pidfile"
  )

  local i=0
  while ! curl -sf --max-time 2 "$_PORTKEY_BASE_URL/v1/health" >/dev/null 2>&1; do
    sleep 1
    if (( ++i > 20 )); then
      print "Portkey gateway failed readiness check. Check: portkey-log" >&2
      return 1
    fi
  done
  print "Portkey gateway started on :$_PORTKEY_PORT" >&2
}

if (( ${+commands[claude]} )); then

  _portkey_run_ccfw() {
    emulate -L zsh
    local alias_name="${1:?usage: _portkey_run_ccfw <alias> <claude|happy> [args...]}"
    local runner="${2:?usage: _portkey_run_ccfw <alias> <claude|happy> [args...]}"
    shift 2
    _portkey_ensure_service || return 1
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    local headers
    headers="$(_portkey_headers "$alias_name" "$opus_model" "$sonnet_model" "$haiku_model" "$small_fast_model")" || return $?

    case "$runner" in
      claude)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          claude --model "$opus_model" "$@"
        ;;
      happy)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          happy yolo --dangerously-skip-permissions "$@"
        ;;
      *)
        print -u2 -- "unsupported Portkey runner: $runner"
        return 1
        ;;
    esac
  }

  _portkey_run_ccz() {
    emulate -L zsh
    local alias_name="${1:?usage: _portkey_run_ccz <alias> <claude|happy> [args...]}"
    local runner="${2:?usage: _portkey_run_ccz <alias> <claude|happy> [args...]}"
    shift 2
    _portkey_ensure_service || return 1
    local zai_model="fleet-ccz"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    local headers
    headers="$(_portkey_headers "$alias_name" "$zai_model" "$haiku_model" "$small_fast_model")" || return $?

    case "$runner" in
      claude)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ENABLE_TOOL_SEARCH=false \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          claude --model "$zai_model" "$@"
        ;;
      happy)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ENABLE_TOOL_SEARCH=false \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$zai_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          happy yolo --dangerously-skip-permissions "$@"
        ;;
      *)
        print -u2 -- "unsupported Portkey runner: $runner"
        return 1
        ;;
    esac
  }

  _portkey_run_cc_fast() {
    emulate -L zsh
    local alias_name="${1:?usage: _portkey_run_cc_fast <alias> <claude|happy> [args...]}"
    local runner="${2:?usage: _portkey_run_cc_fast <alias> <claude|happy> [args...]}"
    shift 2
    _portkey_ensure_service || return 1
    local glm_model="fleet-cc-fast"
    local opus_model="fleet-opus"
    local sonnet_model="fleet-sonnet"
    local haiku_model="fleet-haiku"
    local small_fast_model="fleet-small-fast"
    local headers
    headers="$(_portkey_headers "$alias_name" "$glm_model" "$opus_model" "$sonnet_model" "$haiku_model" "$small_fast_model")" || return $?

    case "$runner" in
      claude)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$glm_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          claude --model "$glm_model" "$@"
        ;;
      happy)
        CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_AUTH_TOKEN="" \
        ANTHROPIC_BASE_URL="$_PORTKEY_BASE_URL" \
        ANTHROPIC_CUSTOM_HEADERS="$headers" \
        ANTHROPIC_MODEL="$glm_model" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
        ANTHROPIC_SMALL_FAST_MODEL="$small_fast_model" \
        API_TIMEOUT_MS="$_PORTKEY_TIMEOUT_MS" \
          happy yolo --dangerously-skip-permissions "$@"
        ;;
      *)
        print -u2 -- "unsupported Portkey runner: $runner"
        return 1
        ;;
    esac
  }

  ccfw() {
    _portkey_run_ccfw ccfw claude "$@"
  }

  ccfw-happy() {
    _portkey_run_ccfw ccfw-happy happy "$@"
  }

  ccfw-pk() {
    _portkey_run_ccfw ccfw-pk claude "$@"
  }

  ccfw-pk-happy() {
    _portkey_run_ccfw ccfw-pk-happy happy "$@"
  }

  ccz() {
    _portkey_run_ccz ccz claude "$@"
  }

  ccz-happy() {
    _portkey_run_ccz ccz-happy happy "$@"
  }

  ccz-pk() {
    _portkey_run_ccz ccz-pk claude "$@"
  }

  ccz-pk-happy() {
    _portkey_run_ccz ccz-pk-happy happy "$@"
  }

  cc-fast() {
    _portkey_run_cc_fast cc-fast claude "$@"
  }

  cc-fast-happy() {
    _portkey_run_cc_fast cc-fast-happy happy "$@"
  }

  cc-fast-pk() {
    _portkey_run_cc_fast cc-fast-pk claude "$@"
  }

  cc-fast-pk-happy() {
    _portkey_run_cc_fast cc-fast-pk-happy happy "$@"
  }

  portkey-health() {
    emulate -L zsh
    _portkey_ensure_service || return 1
    curl -sS "$_PORTKEY_BASE_URL/v1/health"
  }

  portkey-probe() {
    emulate -L zsh
    _portkey_ensure_service || return 1
    local route="${1:-fleet-opus}"
    local prompt="${2:-reply with the single word ready}"
    local max_tokens="${PORTKEY_PROBE_MAX_TOKENS:-256}"
    local headers
    headers="$(_portkey_headers "portkey-probe-${route}" "$route")" || return $?
    local -a header_args
    header_args=("${(@f)$(_portkey_header_args "$headers")}")
    local body
    body="$(jq -cn --arg model "$route" --arg prompt "$prompt" --argjson max_tokens "$max_tokens" '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: $prompt}]}')" || return $?
    curl -sS "$_PORTKEY_BASE_URL/v1/messages" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      "${header_args[@]}" \
      -d "$body" \
      | jq . 2>/dev/null || cat
  }

  portkey-probe-stream() {
    emulate -L zsh
    _portkey_ensure_service || return 1
    local route="${1:-fleet-opus}"
    local headers
    headers="$(_portkey_headers "portkey-probe-stream-${route}" "$route")" || return $?
    local -a header_args
    header_args=("${(@f)$(_portkey_header_args "$headers")}")
    curl -sSN "$_PORTKEY_BASE_URL/v1/messages" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      "${header_args[@]}" \
      -d "{\"model\":\"$route\",\"max_tokens\":256,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"count from 1 to 10\"}]}"
  }

  portkey-stop() {
    emulate -L zsh
    _portkey_is_host || { print "portkey-stop: runs on ceres" >&2; return 1; }
    local pidfile="$_PORTKEY_STATE/gateway.pid"
    local unit="portkey-gateway.service"
    if (( ${+commands[systemctl]} )) && [[ -r "$HOME/.config/systemd/user/$unit" ]]; then
      if systemctl --user is-active --quiet "$unit" >/dev/null 2>&1; then
        systemctl --user stop "$unit" >/dev/null 2>&1 || return $?
        rm -f "$pidfile"
        print "Portkey gateway stopped."
        return 0
      fi
    fi
    [[ -r $pidfile ]] || { print "Portkey gateway not running."; return 0; }
    local pid
    pid="$(<"$pidfile")"
    if [[ -n $pid ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid"
      print "Portkey gateway stopped."
    else
      print "Portkey gateway not running."
    fi
  }

  portkey-log() {
    emulate -L zsh
    tail "${@:--f}" "$_PORTKEY_STATE/gateway.log"
  }

fi
