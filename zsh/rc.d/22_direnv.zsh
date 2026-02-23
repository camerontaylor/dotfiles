# Install direnv cd-hook AFTER instant prompt. Export happens in 00_direnv_export.zsh.
# See: https://github.com/romkatv/powerlevel10k#how-do-i-initialize-direnv-when-using-instant-prompt
(( ${+commands[direnv]} )) && emulate zsh -c "$(direnv hook zsh)"
