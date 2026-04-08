_webfront_wrapper_names=(
    p
    cc
    ccm
    ccz
    ccm-happy
    ccz-happy
    yolo
    w
)

_webfront_wrapper_claude_completion_dir=$ZDOTDIR/plugins/claude-code-zsh-completion/completions

_webfront_wrappers_refresh() {
    local root name

    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    [[ -f "$root/scripts/run-agent-alias.sh" ]] || return 0
    [[ -f "$root/scripts/wt-archive" ]] || return 0

    for name in $_webfront_wrapper_names; do
        unalias "$name" 2>/dev/null || true
    done

    (( ${+functions[compdef]} )) || return 0

    if [[ -d $_webfront_wrapper_claude_completion_dir ]]; then
        (( ${fpath[(I)$_webfront_wrapper_claude_completion_dir]} )) || fpath=($_webfront_wrapper_claude_completion_dir $fpath)
        autoload -Uz _claude
        compdef _claude cc ccm ccz ccm-happy ccz-happy yolo
    fi
}

add-zsh-hook chpwd _webfront_wrappers_refresh
add-zsh-hook precmd _webfront_wrappers_refresh
_webfront_wrappers_refresh
