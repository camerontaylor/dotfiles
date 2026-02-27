# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.local/dotfiles/zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.


_ZSHRC_DEBUG=${_ZSHRC_DEBUG:-${_ZSHENV_DEBUG:-0}}
_zshrc_dbg() { (( _ZSHRC_DEBUG )) && echo "[zshrc] $*" >> /tmp/zsh-debug.log; }

_zshrc_dbg "start"

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  _zshrc_dbg "sourcing p10k instant prompt"
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" || echo "Warning: error in p10k instant prompt" >&2
else
  _zshrc_dbg "p10k instant prompt not found, skipping"
fi

# Include interactive rc files
for conffile in $ZDOTDIR/rc.d/*(N); do
  _zshrc_dbg "sourcing $conffile"
  if ! source "$conffile" 2>&1; then
    echo "Warning: error in $conffile" >&2
  fi
done
unset conffile

# To customize prompt, run `p10k configure` or edit ~/.local/dotfiles/zsh/.p10k.zsh.
if [[ -f ~/.local/dotfiles/zsh/.p10k.zsh ]]; then
  _zshrc_dbg "sourcing .p10k.zsh"
  source ~/.local/dotfiles/zsh/.p10k.zsh || echo "Warning: p10k failed" >&2
else
  _zshrc_dbg ".p10k.zsh not found, skipping"
fi

_zshrc_dbg "done"