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

# Normal Max plan Claude - explicitly unset any CCR vars
alias ccc='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY && claude'

# Cheap OpenRouter via CCR
alias cc='(eval "$(ccr activate)" && exec claude)'

# MiniMax M2.7 - direct Claude Code (no happy yolo)
alias ccm='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7'

# Backward compatible alias for MiniMax M2.5
alias cc-minimax='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.5 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.5'

# MiniMax M2.7 via happy yolo
alias ccm-happy='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# Z.AI - direct Claude Code (no happy yolo)
alias ccz='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.1'

# Z.AI via happy yolo
alias ccz-happy='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

alias yolo="happy yolo --dangerously-skip-permissions"

# Callable clones for webfront fpath wrappers to fall back on
_cc()        { (eval "$(ccr activate)" && exec claude "$@") }
_ccm()       { CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7 "$@" }
_ccm-happy() { CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_ccz()       { CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.1 "$@" }
_ccz-happy() { CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_yolo()      { happy yolo --dangerously-skip-permissions "$@" }

#export GEMINI_API_KEY=...  # set in zsh/env.d/90_secrets.zsh
