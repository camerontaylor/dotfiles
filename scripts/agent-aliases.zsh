#!/usr/bin/env zsh

emulate -L zsh

typeset -ga AGENT_ALIAS_ENV_NAMES
typeset -gA AGENT_ALIAS_ENV

# Portkey gateway lives on ceres.webfront.app:8787 and serves Anthropic-compatible
# /v1/messages at the gateway root. The real provider secrets stay on the
# gateway host; aliases send only local control headers.
typeset -g AGENT_ALIAS_PORTKEY_HOST="${AGENT_ALIAS_PORTKEY_HOST:-${PORTKEY_HOST:-ceres.webfront.app}}"
typeset -g AGENT_ALIAS_PORTKEY_PORT="${AGENT_ALIAS_PORTKEY_PORT:-${PORTKEY_PORT:-8787}}"
typeset -g AGENT_ALIAS_PORTKEY_BASE_URL="http://${AGENT_ALIAS_PORTKEY_HOST}:${AGENT_ALIAS_PORTKEY_PORT}"
typeset -g AGENT_ALIAS_PORTKEY_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/portkey"
typeset -g AGENT_ALIAS_PORTKEY_CONFIG_FILE="${PORTKEY_CONFIG_FILE:-$HOME/.local/dotfiles/configs/ai/portkey/config.json}"
typeset -g AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE="${PORTKEY_LOCAL_TOKEN_FILE:-$AGENT_ALIAS_PORTKEY_STATE/local-api-key}"

agent_alias_portkey_is_host() {
    emulate -L zsh
    [[ "$(hostname -s 2>/dev/null)" == "${AGENT_ALIAS_PORTKEY_HOST%%.*}" ]]
}

agent_alias_portkey_remote_token_host() {
    emulate -L zsh
    print -r -- "${PORTKEY_SSH_HOST:-$AGENT_ALIAS_PORTKEY_HOST}"
}

agent_alias_portkey_fetch_remote_token_file() {
    emulate -L zsh
    ! agent_alias_portkey_is_host || return 1
    (( ${+commands[ssh]} )) || return 1

    local ssh_host token tmp
    ssh_host="$(agent_alias_portkey_remote_token_host)" || return $?
    token="$(
        ssh -o BatchMode=yes -o ConnectTimeout="${PORTKEY_SSH_CONNECT_TIMEOUT:-5}" \
            "$ssh_host" 'cat ~/.local/state/portkey/local-api-key' 2>/dev/null
    )" || return $?
    [[ -n "$token" ]] || return 1

    [[ -d "$AGENT_ALIAS_PORTKEY_STATE" ]] || mkdir -p "$AGENT_ALIAS_PORTKEY_STATE"
    tmp="$(mktemp "$AGENT_ALIAS_PORTKEY_STATE/local-api-key.tmp.XXXXXX")" || return $?
    umask 077
    print -rn -- "$token" >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE"
}

agent_alias_portkey_config_version() {
    emulate -L zsh
    (( $# > 0 )) || {
        print -u2 -- "usage: agent_alias_portkey_config_version <route> [route...]"
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
        ' "$AGENT_ALIAS_PORTKEY_CONFIG_FILE" | sha256sum | awk '{print $1}'
    )" || return $?

    print -r -- "local-sha256:${hash[1,16]}"
}

agent_alias_portkey_config_slug() {
    emulate -L zsh
    local alias_name="${1:?usage: agent_alias_portkey_config_slug <alias> <route> [route...]}"
    shift
    (( $# > 0 )) || {
        print -u2 -- "usage: agent_alias_portkey_config_slug <alias> <route> [route...]"
        return 1
    }

    local version slug_hash safe_alias
    version="$(agent_alias_portkey_config_version "$@")" || return $?
    slug_hash="$(printf '%s:%s\n' "$alias_name" "$version" | sha256sum | awk '{print substr($1,1,12)}')" || return $?
    safe_alias="${alias_name//[^A-Za-z0-9-]/-}"
    print -r -- "pc-local-${safe_alias}-${slug_hash}"
}

agent_alias_portkey_local_token() {
    emulate -L zsh
    if [[ -n "${PORTKEY_LOCAL_API_KEY:-}" ]]; then
        print -r -- "$PORTKEY_LOCAL_API_KEY"
        return 0
    fi

    if [[ -r "$AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE" ]]; then
        <"$AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE"
        return 0
    fi

    if ! agent_alias_portkey_is_host; then
        agent_alias_portkey_fetch_remote_token_file || {
            print -u2 -- "Portkey local token missing at $AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE and could not be fetched from $(agent_alias_portkey_remote_token_host). Set PORTKEY_LOCAL_API_KEY or run portkey-sync-token on a trusted LAN."
            return 1
        }
        <"$AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE"
        return 0
    fi

    [[ -d "$AGENT_ALIAS_PORTKEY_STATE" ]] || mkdir -p "$AGENT_ALIAS_PORTKEY_STATE"
    local token
    if (( ${+commands[openssl]} )); then
        token="$(openssl rand -hex 32)" || return $?
    elif (( ${+commands[uuidgen]} )); then
        token="$(uuidgen)$(uuidgen)" || return $?
    else
        token="$(printf '%s-%s-%s\n' "$(date +%s)" "$RANDOM" "$RANDOM")"
    fi
    umask 077
    print -rn -- "$token" >"$AGENT_ALIAS_PORTKEY_LOCAL_TOKEN_FILE"
    print -r -- "$token"
    return 0
}

agent_alias_portkey_session_id() {
    emulate -L zsh
    local session="${PORTKEY_STICKY_SESSION:-${OMX_SESSION_ID:-${CODEX_SESSION_ID:-${TMUX_PANE:-}}}}"
    if [[ -n "$session" ]]; then
        print -r -- "$session"
        return 0
    fi

    [[ -d "$AGENT_ALIAS_PORTKEY_STATE" ]] || mkdir -p "$AGENT_ALIAS_PORTKEY_STATE"
    local session_file="$AGENT_ALIAS_PORTKEY_STATE/sticky-session-id"
    if [[ ! -r "$session_file" ]]; then
        umask 077
        if (( ${+commands[uuidgen]} )); then
            uuidgen >"$session_file"
        else
            printf '%s-%s\n' "$(date +%s)" "$RANDOM" >"$session_file"
        fi
    fi
    <"$session_file"
}

agent_alias_portkey_headers() {
    emulate -L zsh
    local alias_name="${1:?usage: agent_alias_portkey_headers <alias> <route> [route...]}"
    shift
    (( $# > 0 )) || {
        print -u2 -- "usage: agent_alias_portkey_headers <alias> <route> [route...]"
        return 1
    }

    local token config_slug config_version session_id metadata
    token="$(agent_alias_portkey_local_token)" || return $?
    config_slug="$(agent_alias_portkey_config_slug "$alias_name" "$@")" || return $?
    config_version="$(agent_alias_portkey_config_version "$@")" || return $?
    session_id="$(agent_alias_portkey_session_id)" || return $?
    metadata="$(jq -cn --arg portkey_session "${alias_name}:${session_id}" '{portkey_session: $portkey_session}')" || return $?

    print -r -- "x-portkey-api-key: ${token}"
    print -r -- "x-portkey-config: ${config_slug}"
    print -r -- "x-portkey-config-version: ${config_version}"
    print -r -- "x-portkey-metadata: ${metadata}"
}

agent_alias_normalize_args() {
    local -a args
    args=("$@")

    if (( ${#args[@]} > 0 )) && [[ "${args[1]}" == "--" ]]; then
        args=("${(@)args[2,-1]}")
    fi

    print -r -- "${(@q)args}"
}

agent_alias_define_env() {
    local alias_name="$1"

    AGENT_ALIAS_ENV_NAMES=()
    AGENT_ALIAS_ENV=()

    case "$alias_name" in
        cc)
            # Plain `claude` against real Anthropic. Clears every override so
            # the binary uses its default Anthropic endpoint and default model.
            # Useful when you want first-party Claude without any
            # MiniMax/Portkey/Z.AI/Fireworks routing.
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ""
                ANTHROPIC_DEFAULT_SONNET_MODEL ""
                ANTHROPIC_DEFAULT_HAIKU_MODEL ""
                ANTHROPIC_DEFAULT_OPUS_MODEL ""
                ANTHROPIC_MODEL ""
                ANTHROPIC_SMALL_FAST_MODEL ""
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL ""
                ANTHROPIC_CUSTOM_HEADERS ""
                API_TIMEOUT_MS ""
            )
            ;;
        ccm-direct|ccm-direct-happy)
            # Direct MiniMax via their Anthropic-compat endpoint. Bypasses Portkey.
            # Direct aliases must keep small-fast on the same backend because
            # Claude Code uses one base URL for all tiers.
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL MiniMax-M2.7
                ANTHROPIC_DEFAULT_HAIKU_MODEL MiniMax-M2.7
                ANTHROPIC_DEFAULT_OPUS_MODEL MiniMax-M2.7
                ANTHROPIC_SMALL_FAST_MODEL MiniMax-M2.7
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "${MINIMAX_API_KEY:-}"
                ANTHROPIC_BASE_URL https://api.minimax.io/anthropic
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccd-direct|ccd-direct-happy)
            # Direct DeepSeek V4 via their Anthropic-compat endpoint. Bypasses Portkey.
            # Same base URL serves both deepseek-v4-pro (opus/sonnet/main) and
            # deepseek-v4-flash (haiku/subagent), so we can split tiers across two
            # models without breaking the "one base URL" constraint that forces
            # ccm-direct/ccz-direct onto a single model.
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                CLAUDE_CODE_SUBAGENT_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "deepseek-v4-pro[1m]"
                ANTHROPIC_DEFAULT_HAIKU_MODEL deepseek-v4-flash
                ANTHROPIC_DEFAULT_OPUS_MODEL "deepseek-v4-pro[1m]"
                ANTHROPIC_MODEL "deepseek-v4-pro[1m]"
                ANTHROPIC_SMALL_FAST_MODEL deepseek-v4-flash
                CLAUDE_CODE_SUBAGENT_MODEL deepseek-v4-flash
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "${DEEPSEEK_API_KEY:-}"
                ANTHROPIC_BASE_URL https://api.deepseek.com/anthropic
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccm|ccm-happy)
            # MiniMax foreground tier via Portkey. The fleet-ccm config uses
            # Fireworks MiniMax primary with OpenRouter MiniMax fallback.
            local _ccm_minimax_model="fleet-ccm"
            local _ccm_haiku_model="fleet-haiku"
            local _ccm_small_fast_model="fleet-small-fast"
            local _ccm_headers
            _ccm_headers="$(agent_alias_portkey_headers "$alias_name" "$_ccm_minimax_model" "$_ccm_haiku_model" "$_ccm_small_fast_model")" || return $?
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccm_minimax_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccm_haiku_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccm_minimax_model"
                ANTHROPIC_MODEL "$_ccm_minimax_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccm_small_fast_model"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL "$AGENT_ALIAS_PORTKEY_BASE_URL"
                ANTHROPIC_CUSTOM_HEADERS "$_ccm_headers"
                API_TIMEOUT_MS 75000
            )
            ;;
        ccz-direct|ccz-direct-happy)
            # Direct Z.AI via their Anthropic-compat endpoint. Bypasses Portkey.
            # Kept as fallback in case proxy-routed `ccz` misbehaves.
            # Since this bypasses Portkey, small-fast must be a Z.AI model.
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL glm-5-turbo
                ANTHROPIC_DEFAULT_HAIKU_MODEL glm-5-turbo
                ANTHROPIC_DEFAULT_OPUS_MODEL glm-5.1
                ANTHROPIC_SMALL_FAST_MODEL glm-5-turbo
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "${Z_AI_API_KEY:-}"
                ANTHROPIC_BASE_URL https://api.z.ai/api/anthropic
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccfw-direct)
            # Direct Fireworks via their Anthropic-compat endpoint. Bypasses Portkey.
            local _ccfw_direct_opus_model="accounts/fireworks/models/kimi-k2p6"
            local _ccfw_direct_sonnet_model="accounts/fireworks/models/minimax-m2p7"
            local _ccfw_direct_haiku_model="accounts/fireworks/models/gpt-oss-120b"
            local _ccfw_direct_small_fast_model="accounts/fireworks/models/gpt-oss-120b"
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ENABLE_TOOL_SEARCH
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ENABLE_TOOL_SEARCH "false"
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccfw_direct_sonnet_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccfw_direct_haiku_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccfw_direct_opus_model"
                ANTHROPIC_MODEL "$_ccfw_direct_sonnet_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccfw_direct_small_fast_model"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "${FIREWORKS_API_KEY:-}"
                ANTHROPIC_BASE_URL https://api.fireworks.ai/inference
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccfw|ccfw-happy)
            # Portkey fleet with fallback chains encoded in
            # ~/.local/dotfiles/configs/ai/portkey/config.json:
            #   fleet-opus       → Fireworks Kimi-K2.6 [→ Z.AI → MiniMax]
            #   fleet-sonnet     → Fireworks GLM-5.1   [→ Kimi → MiniMax M2.7]
            #   fleet-haiku      → OpenRouter BYOK → Cerebras openai/gpt-oss-120b
            #   fleet-small-fast → OpenRouter BYOK → Cerebras openai/gpt-oss-120b
            local _ccfw_opus_model="fleet-opus"
            local _ccfw_sonnet_model="fleet-sonnet"
            local _ccfw_haiku_model="fleet-haiku"
            local _ccfw_small_fast_model="fleet-small-fast"
            local _ccfw_headers
            _ccfw_headers="$(agent_alias_portkey_headers "$alias_name" "$_ccfw_opus_model" "$_ccfw_sonnet_model" "$_ccfw_haiku_model" "$_ccfw_small_fast_model")" || return $?
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccfw_sonnet_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccfw_haiku_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccfw_opus_model"
                ANTHROPIC_MODEL "$_ccfw_opus_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccfw_small_fast_model"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL "$AGENT_ALIAS_PORTKEY_BASE_URL"
                ANTHROPIC_CUSTOM_HEADERS "$_ccfw_headers"
                API_TIMEOUT_MS 75000
            )
            ;;
        ccd|ccd-happy)
            # DeepSeek V4 foreground tier via Portkey. Both routes pin OpenRouter
            # to `provider.only=["DeepSeek"]` with `allow_fallbacks=false` — no
            # cross-provider fallback. ccd will fail when DeepSeek upstream is
            # unavailable; this is intentional (provider isolation > resilience).
            local _ccd_pro_model="fleet-ccd"
            local _ccd_flash_model="fleet-ccd-haiku"
            local _ccd_headers
            _ccd_headers="$(agent_alias_portkey_headers "$alias_name" "$_ccd_pro_model" "$_ccd_flash_model")" || return $?
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccd_pro_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccd_flash_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccd_pro_model"
                ANTHROPIC_MODEL "$_ccd_pro_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccd_flash_model"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL "$AGENT_ALIAS_PORTKEY_BASE_URL"
                ANTHROPIC_CUSTOM_HEADERS "$_ccd_headers"
                API_TIMEOUT_MS 75000
            )
            ;;
        ccz|ccz-happy)
            # Z.AI foreground tier via Portkey. The fleet-ccz config keeps Z.AI
            # primary and preserves Fireworks/MiniMax fallback capacity.
            local _ccz_zai_model="fleet-ccz"
            local _ccz_haiku_model="fleet-haiku"
            local _ccz_small_fast_model="fleet-small-fast"
            local _ccz_headers
            _ccz_headers="$(agent_alias_portkey_headers "$alias_name" "$_ccz_zai_model" "$_ccz_haiku_model" "$_ccz_small_fast_model")" || return $?
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccz_zai_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccz_haiku_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccz_zai_model"
                ANTHROPIC_MODEL "$_ccz_zai_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccz_small_fast_model"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL "$AGENT_ALIAS_PORTKEY_BASE_URL"
                ANTHROPIC_CUSTOM_HEADERS "$_ccz_headers"
                API_TIMEOUT_MS 75000
            )
            ;;
        cc-fast|cc-fast-happy)
            # Portkey fast foreground route. The route pins Cerebras GLM-4.7
            # primary and falls back to Fireworks GPT-OSS-120B reasoning.
            # Sub-agents and tier-coded requests stay on the regular fleet-* rules.
            local _ccfast_glm_model="fleet-cc-fast"
            local _ccfast_opus_model="fleet-opus"
            local _ccfast_sonnet_model="fleet-sonnet"
            local _ccfast_haiku_model="fleet-haiku"
            local _ccfast_small_fast_model="fleet-small-fast"
            local _ccfast_api_key=""
            [[ "$alias_name" == "cc-fast" ]] && _ccfast_api_key="portkey-local"
            local _ccfast_headers
            _ccfast_headers="$(agent_alias_portkey_headers "$alias_name" "$_ccfast_glm_model" "$_ccfast_opus_model" "$_ccfast_sonnet_model" "$_ccfast_haiku_model" "$_ccfast_small_fast_model")" || return $?
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccfast_sonnet_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$_ccfast_haiku_model"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccfast_opus_model"
                ANTHROPIC_MODEL "$_ccfast_glm_model"
                ANTHROPIC_SMALL_FAST_MODEL "$_ccfast_small_fast_model"
                ANTHROPIC_API_KEY "$_ccfast_api_key"
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL "$AGENT_ALIAS_PORTKEY_BASE_URL"
                ANTHROPIC_CUSTOM_HEADERS "$_ccfast_headers"
                API_TIMEOUT_MS 75000
            )
            ;;
        yolo)
            # Plain `happy yolo` with no Anthropic env overrides. Useful when
            # you want happy's permissive mode but real Anthropic auth.
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_API_KEY
                ANTHROPIC_AUTH_TOKEN
                ANTHROPIC_BASE_URL
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ""
                ANTHROPIC_DEFAULT_SONNET_MODEL ""
                ANTHROPIC_DEFAULT_HAIKU_MODEL ""
                ANTHROPIC_DEFAULT_OPUS_MODEL ""
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN ""
                ANTHROPIC_BASE_URL ""
                API_TIMEOUT_MS ""
            )
            ;;
        *)
            print -u2 -- "Unsupported agent alias: $alias_name"
            return 1
            ;;
    esac
}

agent_alias_export_env() {
    local alias_name="$1"
    agent_alias_define_env "$alias_name" || return $?

    local name
    for name in "${AGENT_ALIAS_ENV_NAMES[@]}"; do
        export "$name=${AGENT_ALIAS_ENV[$name]}"
    done
}

agent_alias_escape_dotenv() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    print -- "$value"
}
