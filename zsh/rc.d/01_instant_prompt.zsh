# clear screen, move cursor to the bottom
# but don't do this under ssh or sudo sessions, as prompt already at the bottom
autoload -Uz clear-screen-soft-bottom
if ! [[ -v SSH_TTY || -v SUDO_USER ]]; then
    clear-screen-soft-bottom
fi

# Prevent git from acquiring optional locks during background prompt updates
export GIT_OPTIONAL_LOCKS=0

# powerlevel10k instant prompt stanza
if [[ -r ${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh ]]; then
  source ${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh
fi
