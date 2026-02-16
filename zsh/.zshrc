# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.local/dotfiles/zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" || echo "Warning: error in p11k instant prompt"
fi

# Include interactive rc files
for conffile in $ZDOTDIR/rc.d/*; do
  source "$conffile" || echo "Warning: error in $conffile" >&2
done
unset conffile

# To customize prompt, run `p10k configure` or edit ~/.local/dotfiles/zsh/.p10k.zsh.
#[[ ! -f ~/.local/dotfiles/zsh/.p10k.zsh ]] || source ~/.local/dotfiles/zsh/.p10k.zsh

# echo "DEBUG: rc.d loop done, about to source p10k" >&2

[[ ! -f ~/.local/dotfiles/zsh/.p10k.zsh ]] || source ~/.local/dotfiles/zsh/.p10k.zsh || echo "Warning: p10k failed" >&2

# echo "DEBUG: zshrc complete" >&2
