# Use fzf for tab completions
source $ZDOTDIR/plugins/fzf-tab/fzf-tab.zsh

zstyle ':fzf-tab:*' prefix ''

if [[ -v TMUX ]]; then
    zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
fi

# Sweep dead-PID leftovers from the fzf-tab tmp dir. The plugin's
# `always { rm ... }` block doesn't run when a shell is killed (SIGKILL,
# tmux pane closed, terminal crash), so the dir accumulates compcap/
# completions/fzf/result files indefinitely. A 49KB stale compcap from
# a previous session can stall future completions by an order of
# magnitude. Defer so it doesn't add to startup latency.
_dotfiles_fzf_tab_sweep() {
    emulate -L zsh -o extended_glob -o nullglob
    local tmp_dir=${TMPPREFIX:-/tmp/zsh}-fzf-tab-$USER
    [[ -d $tmp_dir ]] || return 0
    local f pid
    for f in $tmp_dir/*.<-> $tmp_dir/*-<->; do
        pid=${f##*[.-]}
        # `kill -0` is portable; succeeds iff the PID exists and we can signal it.
        kill -0 $pid 2>/dev/null && continue
        command rm -f -- $f
    done
}
if (( $+functions[zsh-defer] )); then
    zsh-defer _dotfiles_fzf_tab_sweep
else
    _dotfiles_fzf_tab_sweep
fi
