# Add this as the VERY FIRST line of ~/.zshenv (before the ZDOTDIR block):
echo "zshenv depth: ${_ZSHENV_DEPTH:-0}" >> /tmp/zshenv-debug.log
(( _ZSHENV_DEPTH = ${_ZSHENV_DEPTH:-0} + 1 ))
(( _ZSHENV_DEPTH > 3 )) && return



 # Determine own path if ZDOTDIR isn't set or home symlink exists
 if [[ -z $ZDOTDIR || -L $HOME/.zshenv ]]; then
     local homezshenv=$HOME/.zshenv
     ZDOTDIR=${homezshenv:A:h}
 fi
 
 typeset -U path PATH
 # DOTFILES dir is parent to ZDOTDIR
 export DOTFILES=${ZDOTDIR:h}

 # Disable global zsh configuration
 # We're doing all configuration ourselves
 unsetopt GLOBAL_RCS

 # Source local env files

for envfile in $ZDOTDIR/env.d/*; do
    source "$envfile" || echo "Warning: error in $envfile" >&2
done

 unset envfile homezshenv
#  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" 2>&1 || true
