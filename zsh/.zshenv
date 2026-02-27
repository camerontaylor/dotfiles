# # Guard against recursive sourcing (e.g. when zsh is invoked from within zsh)
# (( _ZSHENV_DEPTH = ${_ZSHENV_DEPTH:-0} + 1 ))
# (( _ZSHENV_DEPTH > 3 )) && return

# # Determine own path if ZDOTDIR isn't set or home symlink exists
#  if [[ -z $ZDOTDIR || -L $HOME/.zshenv ]]; then
#      local homezshenv=$HOME/.zshenv
#      ZDOTDIR=${homezshenv:A:h}
#  fi
 
#  typeset -U path PATH
#  # DOTFILES dir is parent to ZDOTDIR
#  export DOTFILES=${ZDOTDIR:h}

#  # Disable global zsh configuration
#  # We're doing all configuration ourselves
#  unsetopt GLOBAL_RCS

#  # Source local env files

# for envfile in $ZDOTDIR/env.d/*; do
#     source "$envfile" || echo "Warning: error in $envfile" >&2
# done

#  unset envfile homezshenv
# #  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" 6>&1 || true

# # opencode
# export PATH=/home/ctaylor/.opencode/bin:$PATH

# Guard against recursive sourcing
(( _ZSHENV_DEPTH = ${_ZSHENV_DEPTH:-0} + 1 ))
(( _ZSHENV_DEPTH > 3 )) && return

# Debug mode — set to 1 to trace, 0 to disable
_ZSHENV_DEBUG=${_ZSHENV_DEBUG:-0}
_zshenv_dbg() { (( _ZSHENV_DEBUG )) && echo "[zshenv] $*" >&2; }

_zshenv_dbg "start (depth=$_ZSHENV_DEPTH)"

# Determine own path if ZDOTDIR isn't set or home symlink exists
if [[ -z $ZDOTDIR || -L $HOME/.zshenv ]]; then
    local homezshenv=$HOME/.zshenv
    ZDOTDIR=${homezshenv:A:h}
fi

_zshenv_dbg "ZDOTDIR=$ZDOTDIR"

typeset -U path PATH
export DOTFILES=${ZDOTDIR:h}
unsetopt GLOBAL_RCS

_zshenv_dbg "DOTFILES=$DOTFILES"

# Source local env files — skip if dir is empty/missing
if [[ -d $ZDOTDIR/env.d ]]; then
    for envfile in $ZDOTDIR/env.d/*(N); do
        _zshenv_dbg "sourcing $envfile"
        if ! source "$envfile" 2>&1; then
            echo "Warning: error in $envfile" >&2
        fi
    done
else
    _zshenv_dbg "env.d not found, skipping"
fi

unset envfile homezshenv

[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)

_zshenv_dbg "done"
