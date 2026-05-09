# Restore terminal state after TUIs that leave enhanced keyboard modes enabled.
_restore_terminal_input_modes() {
    [[ -t 1 ]] || return 0

    printf '\e[=0u'     # kitty/Ghostty: disable all progressive enhancement flags
    printf '\e[<u'      # kitty/Ghostty: pop one saved keyboard mode from the stack
    printf '\e[>4;0m'   # xterm/tmux/Ghostty: disable modifyOtherKeys
    printf '\e[>4n'     # xterm: fully disable modifyOtherKeys resource state
    printf '\e[?2004l'  # disable bracketed paste mode
}

_run_with_terminal_restore() {
    local saved_stty="" ret=0

    if [[ -t 0 ]]; then
        saved_stty=$(command stty -g 2>/dev/null)
    fi

    {
        command "$@"
        ret=$?
    } always {
        if [[ -n $saved_stty ]]; then
            command stty "$saved_stty" 2>/dev/null
        fi
        _restore_terminal_input_modes
    }

    return $ret
}

# Wrap claude/happy to restore terminal settings on exit.
claude() {
    _run_with_terminal_restore claude "$@"
}

happy() {
    _run_with_terminal_restore happy "$@"
}

# Default ToolSearch for Claude Code (overridden to false by ccz-direct aliases)
export ENABLE_TOOL_SEARCH="auto:5"

# Normal Max plan Claude - explicitly unset any CCR vars.
# CLAUDE_CODE_ATTRIBUTION_HEADER=0 stops Claude Code 2.1.36+ from emitting the
# per-request x-anthropic-billing-header that breaks Anthropic prompt caching
# (cc_version/cc_entrypoint/cch=... change every request → cache miss every
# turn). See anthropics/claude-code#24168.
#
# Unset every model-pinning env var so Claude Code launches against the user's
# plan default. Critical: a leftover ANTHROPIC_MODEL or ANTHROPIC_DEFAULT_*
# from a prior fleet-routed shell (ccfw / ccz / cc-fast / ccm / ccz-direct) would
# pin a generic "opus" or fleet-* name and lose the 1M-context Opus 4.7
# variant the Max plan otherwise selects automatically. Don't pass --model.
alias ccc='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ENABLE_TOOL_SEARCH && CLAUDE_CODE_ATTRIBUTION_HEADER=0 claude'

# Cheap OpenRouter via CCR
alias cc='(eval "$(ccr activate)" && CLAUDE_CODE_ATTRIBUTION_HEADER=0 exec claude)'

# MiniMax M2.7 - direct Claude Code (no happy yolo)
alias ccm-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7'

# Backward compatible alias for MiniMax M2.5
alias cc-minimax='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.5 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.5 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.5'

# MiniMax M2.7 via happy yolo
alias ccm-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# Z.AI direct (kept as fallback in case the proxy-routed `ccz` misbehaves)
alias ccz-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.1'

# Z.AI direct via happy yolo
alias ccz-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

alias yolo="happy yolo --dangerously-skip-permissions"

# Callable clones for webfront fpath wrappers to fall back on
_cc()        { (eval "$(ccr activate)" && CLAUDE_CODE_ATTRIBUTION_HEADER=0 exec claude "$@") }
_ccm-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7 "$@" }
_ccm-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_ccz-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.1 "$@" }
_ccz-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_yolo()      { happy yolo --dangerously-skip-permissions "$@" }

#export GEMINI_API_KEY=...  # set in zsh/env.d/90_secrets.zsh
