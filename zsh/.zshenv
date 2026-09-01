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

# Normalize a bare/relative $SHELL to an absolute path. Some harnesses (notably
# the Claude Code Bash tool) export SHELL=zsh with no path. OpenSSH's `Match
# exec` — used by ssh/config's optimistic LAN fast-path — runs the probe under
# $SHELL and FATALLY aborts the whole connection if $SHELL isn't an executable
# absolute path. Fix it for every zsh, including non-interactive `zsh -c`.
if [[ $SHELL != /* ]]; then
    export SHELL=${commands[zsh]:-/usr/bin/zsh}
fi

# Determine own path if ZDOTDIR isn't set or home symlink exists.
# Symlink walk (not ${...:A:h} — those history modifiers are zsh-only, and
# readlink -f is only macOS ≥ 12.3).
if [[ -z $ZDOTDIR || -L $HOME/.zshenv ]]; then
    _homezshenv=$HOME/.zshenv
    while [ -L "$_homezshenv" ]; do
        _homezshenv_link=$(readlink "$_homezshenv")
        case $_homezshenv_link in
            /*) _homezshenv=$_homezshenv_link ;;
            *) _homezshenv=${_homezshenv%/*}/$_homezshenv_link ;;
        esac
    done
    ZDOTDIR=${_homezshenv%/*}
    unset _homezshenv _homezshenv_link
fi

_zshenv_dbg "ZDOTDIR=$ZDOTDIR"

typeset -U path PATH
export DOTFILES=${ZDOTDIR:h}
unsetopt GLOBAL_RCS

_zshenv_dbg "DOTFILES=$DOTFILES"

# Source local env files — skip if dir is empty/missing
if [[ -d $ZDOTDIR/env.d ]]; then
    # Plain glob + [ -e ] guard is the repo's dual-shell iteration template
    # (docs/bash-compatibility.md §C): the `(N)` glob qualifier is a bash parse
    # error, and without it zsh aborts on an empty dir before any guard could
    # run — so null_glob is set for the loop and restored after. bash's default
    # leaves an unmatched pattern literal, which the [ -e ] guard skips.
    setopt null_glob
    for envfile in $ZDOTDIR/env.d/*; do
        [[ -e $envfile ]] || continue
        [[ $envfile == *.enc ]] && continue
        _zshenv_dbg "sourcing $envfile"
        if ! source "$envfile" 2>&1; then
            echo "Warning: error in $envfile" >&2
        fi
    done
    unsetopt null_glob
else
    _zshenv_dbg "env.d not found, skipping"
fi

unset envfile

[[ -d "$HOME/.opencode/bin" ]] && path_prepend "$HOME/.opencode/bin"

# Bash-compatible expansion in agent shells only: agents write bash-flavored
# one-liners, so let unmatched globs pass through literally (no_nomatch) and
# treat `=word` as plain text (no_equals). Last on purpose — nothing in env.d
# may re-enable these behind our back.
[[ -n $CLAUDECODE || -n $CODEX_SESSION_ID ]] && setopt no_nomatch no_equals

_zshenv_dbg "done"
