# Interactive mise activation — bash twin of zsh/rc.d/22_mise.zsh.
# Non-interactive shells already get the shims via env.d/08_mise.zsh;
# activation adds the cd-hook env eval for prompts and direnv-style flows.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi
