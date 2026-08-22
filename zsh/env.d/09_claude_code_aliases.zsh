# Interactive-only: aliases/wrappers are useless in non-interactive shells
# (zsh -c, mise env, script invocations) and parsing them wastes startup time.
# CLAUDE_ALIAS_TEST=1 bypasses the guard so harnesses (e.g. webfront
# scripts/test-alias-sync.zsh) can source this file under `zsh -fc`.
[[ -o interactive || -n "${CLAUDE_ALIAS_TEST:-}" ]] || return 0

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
alias ccc='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ENABLE_TOOL_SEARCH && CLAUDE_CODE_ATTRIBUTION_HEADER=0 claude'

# Plain `claude` against real Anthropic. Mirrors the in-repo `cc` alias
# (scripts/agent-aliases.zsh + scripts/run-agent-alias.sh) so typing `cc`
# interactively does the same thing cq does when invoked with
# --worker-alias=cc. Functionally identical to `ccc`; kept as a separate
# alias name so the two can diverge later if needed.
alias cc='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ENABLE_TOOL_SEARCH && CLAUDE_CODE_ATTRIBUTION_HEADER=0 claude'

# Cheap OpenRouter via CCR (was `cc`; renamed when `cc` was repointed to plain Anthropic).
alias cc-ccr='(unset CLAUDE_CODE_SUBAGENT_MODEL && eval "$(ccr activate)" && CLAUDE_CODE_ATTRIBUTION_HEADER=0 exec claude)'

# MiniMax M2.7 - direct Claude Code (no happy yolo)
alias ccm-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7'

# Backward compatible alias for MiniMax M2.5
alias cc-minimax='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.5 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.5 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.5 CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.5'

# MiniMax M2.7 via happy yolo
alias ccm-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# DeepSeek V4 direct - direct Claude Code (no happy yolo)
alias ccd-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_SMALL_FAST_MODEL=deepseek-v4-flash CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" API_TIMEOUT_MS="3000000" claude --model "deepseek-v4-pro[1m]"'

# DeepSeek V4 direct via happy yolo
alias ccd-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_SMALL_FAST_MODEL=deepseek-v4-flash CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# Fireworks direct (kept as fallback in case proxy-routed `ccfw` misbehaves)
alias ccfw-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=accounts/fireworks/models/minimax-m2p7 ANTHROPIC_DEFAULT_HAIKU_MODEL=accounts/fireworks/models/gpt-oss-120b ANTHROPIC_DEFAULT_OPUS_MODEL=accounts/fireworks/models/kimi-k2p6 ANTHROPIC_MODEL=accounts/fireworks/models/minimax-m2p7 ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/models/gpt-oss-120b CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$FIREWORKS_API_KEY" ANTHROPIC_BASE_URL="https://api.fireworks.ai/inference" API_TIMEOUT_MS="3000000" claude --model accounts/fireworks/models/minimax-m2p7'

# Z.AI direct (kept as fallback in case the proxy-routed `ccz` misbehaves)
alias ccz-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.3'

# Z.AI direct via happy yolo
alias ccz-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# OpenRouter stealth ox-alpha direct via OpenRouter's Anthropic-compat
# /api/v1/messages endpoint (verified 2026-08-21; prompt caching works).
# Free while in stealth trial. Data policy (per OpenRouter, 2026-08-21):
# prompts+completions ARE retained by the anonymous provider, NOT used for
# training. Retention by an unknown lab still means: never point this at
# personal/court/triage data. Single model fills every tier (one-base-URL
# constraint); subagents inherit it and cost nothing.
# CLAUDE_CODE_MAX_CONTEXT_TOKENS: Claude Code doesn't know `stealth/ox-alpha`,
# so it assumes a 200k window and auto-compacts ~5x too early. 1048576 is the
# real context_length straight from GET openrouter.ai/api/v1/models
# (verified 2026-08-21) — it's 2^20, NOT a round 1000000.
# The `[1m]` model-name suffix ccd-direct uses also works here (tested
# 2026-08-21: Claude Code strips it before the wire, OpenRouter still routes
# and answers). Preferred the env var anyway: it pins the exact 1048576
# rather than a generic 1M bucket, and leaves the model id untouched so the
# `--model` string stays copy-pasteable into OpenRouter's own tooling.
# TRIAL WINDOW: listed 2026-08-16; OpenCode announced 2026-08-21 "free for
# the next week" → expect the free window to END ~2026-08-28.
# When `--model stealth/ox-alpha` starts 404ing, the trial is over: delete
# these ccx aliases, the openrouter/stealth/ox-alpha entry in openclaw.json,
# and the `claude_ccx` providerInstances entry in ~/.t3/userdata/settings.json
# (a claudeAgent instance mirroring this route; untracked local app state).
# If a Portkey fleet-ccx route is added later, repoint plain `ccx` there.
alias ccx-direct='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576 ANTHROPIC_DEFAULT_SONNET_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_HAIKU_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_OPUS_MODEL=stealth/ox-alpha ANTHROPIC_SMALL_FAST_MODEL=stealth/ox-alpha CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY" ANTHROPIC_BASE_URL="https://openrouter.ai/api" API_TIMEOUT_MS="3000000" claude --model stealth/ox-alpha'

# OpenRouter stealth ox-alpha via happy yolo
alias ccx-direct-happy='CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576 ANTHROPIC_DEFAULT_SONNET_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_HAIKU_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_OPUS_MODEL=stealth/ox-alpha ANTHROPIC_SMALL_FAST_MODEL=stealth/ox-alpha CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY" ANTHROPIC_BASE_URL="https://openrouter.ai/api" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

# Short name: direct for now; repoint to Portkey if a fleet-ccx route lands.
alias ccx='ccx-direct'

# `happy yolo` against real Anthropic. Unsets every fleet override so a prior
# ccfw/ccz/ccm/cc-fast shell doesn't silently route `yolo` somewhere else.
# Mirrors the in-repo `yolo` alias (scripts/agent-aliases.zsh + scripts/run-agent-alias.sh).
alias yolo='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC && CLAUDE_CODE_ATTRIBUTION_HEADER=0 happy yolo --dangerously-skip-permissions'

# Callable clones for webfront fpath wrappers to fall back on
_cc()        { unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ENABLE_TOOL_SEARCH; CLAUDE_CODE_ATTRIBUTION_HEADER=0 claude "$@" }
_cc-ccr()    { (unset CLAUDE_CODE_SUBAGENT_MODEL && eval "$(ccr activate)" && CLAUDE_CODE_ATTRIBUTION_HEADER=0 exec claude "$@") }
_ccm-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" claude --model MiniMax-M2.7 "$@" }
_ccm-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=MiniMax-M2.7 ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M2.7 ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7 CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_ccfw-direct()      { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=accounts/fireworks/models/minimax-m2p7 ANTHROPIC_DEFAULT_HAIKU_MODEL=accounts/fireworks/models/gpt-oss-120b ANTHROPIC_DEFAULT_OPUS_MODEL=accounts/fireworks/models/kimi-k2p6 ANTHROPIC_MODEL=accounts/fireworks/models/minimax-m2p7 ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/models/gpt-oss-120b CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$FIREWORKS_API_KEY" ANTHROPIC_BASE_URL="https://api.fireworks.ai/inference" API_TIMEOUT_MS="3000000" claude --model accounts/fireworks/models/minimax-m2p7 "$@" }
_ccz-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" claude --model glm-5.3 "$@" }
_ccz-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5-turbo ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 ANTHROPIC_SMALL_FAST_MODEL=glm-5-turbo CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_ccd-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_SMALL_FAST_MODEL=deepseek-v4-flash CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" API_TIMEOUT_MS="3000000" claude --model "deepseek-v4-pro[1m]" "$@" }
_ccx-direct()       { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576 ANTHROPIC_DEFAULT_SONNET_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_HAIKU_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_OPUS_MODEL=stealth/ox-alpha ANTHROPIC_SMALL_FAST_MODEL=stealth/ox-alpha CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY" ANTHROPIC_BASE_URL="https://openrouter.ai/api" API_TIMEOUT_MS="3000000" claude --model stealth/ox-alpha "$@" }
_ccx-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_TOOL_SEARCH=false CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576 ANTHROPIC_DEFAULT_SONNET_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_HAIKU_MODEL=stealth/ox-alpha ANTHROPIC_DEFAULT_OPUS_MODEL=stealth/ox-alpha ANTHROPIC_SMALL_FAST_MODEL=stealth/ox-alpha CLAUDE_CODE_SUBAGENT_MODEL="" ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY" ANTHROPIC_BASE_URL="https://openrouter.ai/api" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_ccd-direct-happy() { CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_MODEL="deepseek-v4-pro[1m]" ANTHROPIC_SMALL_FAST_MODEL=deepseek-v4-flash CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions "$@" }
_yolo()      { unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; CLAUDE_CODE_ATTRIBUTION_HEADER=0 happy yolo --dangerously-skip-permissions "$@" }

_cc_fast_portkey() {
    if (( ! ${+functions[_portkey_run_cc_fast]} )); then
        [[ -r "$ZDOTDIR/rc.d/11_portkey.zsh" ]] || {
            print -u2 -- "cc-fast: missing Portkey wrapper at $ZDOTDIR/rc.d/11_portkey.zsh"
            return 1
        }
        source "$ZDOTDIR/rc.d/11_portkey.zsh" || return $?
    fi

    _portkey_run_cc_fast "$@"
}

# Non-interactive shells source env.d but not rc.d. Define lazy cc-fast wrappers
# here so scripts and Codex command runs use the same Portkey path as terminals.
unalias cc-fast cc-fast-happy cc-fast-pk cc-fast-pk-happy 2>/dev/null || :

cc-fast() {
    _cc_fast_portkey cc-fast claude "$@"
}

cc-fast-happy() {
    _cc_fast_portkey cc-fast-happy happy "$@"
}

cc-fast-pk() {
    _cc_fast_portkey cc-fast-pk claude "$@"
}

cc-fast-pk-happy() {
    _cc_fast_portkey cc-fast-pk-happy happy "$@"
}

#export GEMINI_API_KEY=...  # set in zsh/env.d/90_secrets.zsh
