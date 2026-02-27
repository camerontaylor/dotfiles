# Activate mise for interactive shells (hook-based: auto-switches versions on cd)
if (( ${+commands[mise]} )); then
    eval "$(mise activate zsh)"

    # Register completions (cached since they change only on mise upgrades)
    evalcache mise completion zsh
fi

# pnpm shell completion (plugin sourced after compinit at 15_completion.zsh)
[[ -f $ZDOTDIR/plugins/pnpm-shell-completion/pnpm-shell-completion.plugin.zsh ]] &&
    source $ZDOTDIR/plugins/pnpm-shell-completion/pnpm-shell-completion.plugin.zsh
