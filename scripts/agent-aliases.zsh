#!/usr/bin/env zsh

emulate -L zsh

typeset -ga AGENT_ALIAS_ENV_NAMES
typeset -gA AGENT_ALIAS_ENV

# Bifrost proxy lives on ceres.local:4242, with CCR on ceres:3456 as the
# legacy rollback path when USE_CCR=1. Default hostname is ceres.local so
# background tasks on pluto/make/ceres all share the same proxy via mDNS.
# Override with LITELLM_HOST / CCR_HOST or the AGENT_ALIAS_* variants.
typeset -g AGENT_ALIAS_LITELLM_HOST="${AGENT_ALIAS_LITELLM_HOST:-${LITELLM_HOST:-ceres.local}}"
typeset -g AGENT_ALIAS_LITELLM_PORT="${AGENT_ALIAS_LITELLM_PORT:-${LITELLM_PORT:-4242}}"
typeset -g AGENT_ALIAS_LITELLM_BASE_URL="http://${AGENT_ALIAS_LITELLM_HOST}:${AGENT_ALIAS_LITELLM_PORT}/anthropic"
typeset -g AGENT_ALIAS_CCR_HOST="${AGENT_ALIAS_CCR_HOST:-${CCR_HOST:-ceres.local}}"
typeset -g AGENT_ALIAS_CCR_PORT="${AGENT_ALIAS_CCR_PORT:-${CCR_PORT:-3456}}"
typeset -g AGENT_ALIAS_CCR_BASE_URL="http://${AGENT_ALIAS_CCR_HOST}:${AGENT_ALIAS_CCR_PORT}"

# Resolve the proxy master key once. Prefers env var (e.g., set by
# mise via .env.agent during background tasks), falls back to the
# self-managed file written by _litellm_ensure_service. Returns "" if neither
# is available — caller decides whether that's a hard error.
agent_alias_litellm_master_key() {
    emulate -L zsh
    if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
        print -r -- "$LITELLM_MASTER_KEY"
        return 0
    fi
    local key_file="${XDG_STATE_HOME:-$HOME/.local/state}/litellm/master-key"
    if [[ -r "$key_file" ]]; then
        # Strip any trailing newline; print -r preserves the rest verbatim
        local key
        key="$(< "$key_file")"
        print -r -- "${key%$'\n'}"
        return 0
    fi
    print -u2 -- "agent-aliases: LITELLM_MASTER_KEY env unset and $key_file unreadable; ccfw/ccz auth will fail"
    print -r -- ""
    return 0
}

agent_alias_use_ccr() {
    emulate -L zsh
    local alias_name="$1"
    local value

    case "$alias_name" in
        ccfw)
            value="${USE_CCR_CCFW:-${USE_CCR:-0}}"
            ;;
        ccz)
            value="${USE_CCR_CCZ:-${USE_CCR:-0}}"
            ;;
        cc-fast)
            value="${USE_CCR_CC_FAST:-${USE_CCR:-0}}"
            ;;
        *)
            value="${USE_CCR:-0}"
            ;;
    esac

    [[ "$value" == "1" ]]
}

agent_alias_proxy_base_url() {
    emulate -L zsh
    local alias_name="$1"

    if agent_alias_use_ccr "$alias_name"; then
        print -r -- "$AGENT_ALIAS_CCR_BASE_URL"
    else
        print -r -- "$AGENT_ALIAS_LITELLM_BASE_URL"
    fi
}

agent_alias_proxy_model() {
    emulate -L zsh
    print -r -- "$2"
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
        ccm)
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
        ccm-happy)
            agent_alias_define_env ccm
            ;;
        ccz-direct)
            AGENT_ALIAS_ENV_NAMES=(
                CLAUDE_CODE_ATTRIBUTION_HEADER
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                ANTHROPIC_DEFAULT_SONNET_MODEL
                ANTHROPIC_DEFAULT_HAIKU_MODEL
                ANTHROPIC_DEFAULT_OPUS_MODEL
                ANTHROPIC_SMALL_FAST_MODEL
                ENABLE_TOOL_SEARCH
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
                ENABLE_TOOL_SEARCH "false"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "${Z_AI_API_KEY:-}"
                ANTHROPIC_BASE_URL https://api.z.ai/api/anthropic
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccz-direct-happy)
            agent_alias_define_env ccz-direct
            ;;
        cc|yolo)
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
        ccfw)
            # Fireworks-fronted fleet via Bifrost proxy.
            # Routes via fleet-* role aliases (Claude Code's client-side
            # subscription gate rejects bare opus/sonnet/haiku).
            local _ccfw_master_key _ccfw_opus_model
            _ccfw_master_key="$(agent_alias_litellm_master_key)"
            _ccfw_opus_model="$(agent_alias_proxy_model ccfw fleet-opus)"
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
                ANTHROPIC_DEFAULT_SONNET_MODEL "$(agent_alias_proxy_model ccfw fleet-sonnet)"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$(agent_alias_proxy_model ccfw fleet-haiku)"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccfw_opus_model"
                ANTHROPIC_MODEL "$_ccfw_opus_model"
                ANTHROPIC_SMALL_FAST_MODEL "$(agent_alias_proxy_model ccfw fleet-small-fast)"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "$_ccfw_master_key"
                ANTHROPIC_BASE_URL "$(agent_alias_proxy_base_url ccfw)"
                ANTHROPIC_CUSTOM_HEADERS ""
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccfw-happy)
            agent_alias_define_env ccfw
            ;;
        ccz)
            # Z.AI single-stream foreground tier via Bifrost proxy.
            # Foreground/opus/sonnet pin to glm-5.1-bg (max_parallel_requests=1)
            # for subscription-saturation discipline; haiku-level work routes to
            # fleet-haiku and small-fast routes to fleet-small-fast.
            local _ccz_master_key _ccz_zai_model
            _ccz_master_key="$(agent_alias_litellm_master_key)"
            _ccz_zai_model="$(agent_alias_proxy_model ccz glm-5.1-bg)"
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
                ANTHROPIC_CUSTOM_HEADERS
                API_TIMEOUT_MS
            )
            AGENT_ALIAS_ENV=(
                CLAUDE_CODE_ATTRIBUTION_HEADER 0
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
                ENABLE_TOOL_SEARCH "false"
                ANTHROPIC_DEFAULT_SONNET_MODEL "$_ccz_zai_model"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$(agent_alias_proxy_model ccz fleet-haiku)"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$_ccz_zai_model"
                ANTHROPIC_MODEL "$_ccz_zai_model"
                ANTHROPIC_SMALL_FAST_MODEL "$(agent_alias_proxy_model ccz fleet-small-fast)"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "$_ccz_master_key"
                ANTHROPIC_BASE_URL "$(agent_alias_proxy_base_url ccz)"
                ANTHROPIC_CUSTOM_HEADERS ""
                API_TIMEOUT_MS 3000000
            )
            ;;
        ccz-happy)
            agent_alias_define_env ccz
            ;;
        cc-fast)
            # Foreground hits cerebras-paid-glm-4.7 (~3000 t/s GLM 4.7 on
            # Cerebras's wafer-scale silicon). Sub-agents and tier-coded
            # requests stay on the regular fleet — glm-4.7 is NEVER selected
            # for background work, only the interactive thread.
            local _ccfast_master_key _ccfast_glm_model
            _ccfast_master_key="$(agent_alias_litellm_master_key)"
            _ccfast_glm_model="$(agent_alias_proxy_model cc-fast glm-4.7-cerebras)"
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
                ANTHROPIC_DEFAULT_SONNET_MODEL "$(agent_alias_proxy_model cc-fast fleet-sonnet)"
                ANTHROPIC_DEFAULT_HAIKU_MODEL "$(agent_alias_proxy_model cc-fast fleet-haiku)"
                ANTHROPIC_DEFAULT_OPUS_MODEL "$(agent_alias_proxy_model cc-fast fleet-opus)"
                ANTHROPIC_MODEL "$_ccfast_glm_model"
                ANTHROPIC_SMALL_FAST_MODEL "$(agent_alias_proxy_model cc-fast fleet-small-fast)"
                ANTHROPIC_API_KEY ""
                ANTHROPIC_AUTH_TOKEN "$_ccfast_master_key"
                ANTHROPIC_BASE_URL "$(agent_alias_proxy_base_url cc-fast)"
                ANTHROPIC_CUSTOM_HEADERS ""
                API_TIMEOUT_MS 3000000
            )
            ;;
        cc-fast-happy)
            agent_alias_define_env cc-fast
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
