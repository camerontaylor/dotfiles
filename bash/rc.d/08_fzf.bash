# fzf keybindings/completion — bash twin of zsh/rc.d/16_fzf.zsh.
# fzf ≥ 0.48 ships its shell integration through `fzf --bash`; older
# installs had discrete key-completion.bash / key-bindings.bash files, which
# are not wired here (upgrade fzf instead).
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash 2>/dev/null)" || true
fi
