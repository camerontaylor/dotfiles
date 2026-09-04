# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.local/dotfiles/zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.


_ZSHRC_DEBUG=${_ZSHRC_DEBUG:-${_ZSHENV_DEBUG:-0}}
_zshrc_dbg() { (( _ZSHRC_DEBUG )) && echo "[zshrc] $*" >> /tmp/zsh-debug.log; }

_zshrc_dbg "start"

# Source the agents.slice handoff before p10k/tmux for local terminals. The
# hook deliberately skips bare SSH login shells; those should stay focused on
# attaching or creating tmux, and pane shells can join the slice afterward.
if [[ -r "$ZDOTDIR/rc.d/00b_agents_slice.zsh" ]]; then
  _zshrc_dbg "sourcing early cgroup handoff"
  source "$ZDOTDIR/rc.d/00b_agents_slice.zsh" 2>&1 || \
    echo "Warning: error in $ZDOTDIR/rc.d/00b_agents_slice.zsh" >&2
fi

# Auto-attach to tmux for SSH sessions (must run before p10k instant prompt)
# Reattach to first unattached session, or create a new one
if (( ${+commands[tmux]} )) && [[ ! -v TMUX && -v SSH_TTY && $EUID != 0 && -z "${ZSH_EXECUTION_STRING:-}" ]]; then
    _tmux_args=()
    # iTerm2 forwards LC_TERMINAL over SSH, which lets the remote shell opt into
    # tmux control mode for native iTerm2 integration.
    if [[ ${LC_TERMINAL-} == iTerm2 ]]; then
        _tmux_args=(-CC)
    fi
    _free_session=$(tmux ls -F '#{session_name} #{session_attached}' 2>/dev/null \
        | awk '$2 == "0" { print $1; exit }')
    if [[ -n $_free_session ]]; then
        exec tmux "${_tmux_args[@]}" attach -t "$_free_session"
    else
        exec tmux "${_tmux_args[@]}" new-session
    fi
    unset _tmux_args
    unset _free_session
fi

# p10k instant prompt is sourced in rc.d/01_instant_prompt.zsh
# (after clear-screen-soft-bottom, so the clear doesn't trigger the
# "console output during initialization" warning)

# Include interactive rc files. Plain glob + [ -e ] guard + null_glob sandwich
# is the dual-shell iteration template (see .zshenv's env.d loop).
setopt null_glob
for conffile in $ZDOTDIR/rc.d/*; do
  [[ -e $conffile ]] || continue
  _zshrc_dbg "sourcing $conffile"
  if ! source "$conffile" 2>&1; then
    echo "Warning: error in $conffile" >&2
  fi
done
unsetopt null_glob
unset conffile

# To customize prompt, run `p10k configure` or edit ~/.local/dotfiles/zsh/.p10k.zsh.
if [[ -f ~/.local/dotfiles/zsh/.p10k.zsh ]]; then
  _zshrc_dbg "sourcing .p10k.zsh"
  source ~/.local/dotfiles/zsh/.p10k.zsh || echo "Warning: p10k failed" >&2
else
  _zshrc_dbg ".p10k.zsh not found, skipping"
fi

_zshrc_dbg "done"
