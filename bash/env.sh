# bash env entrypoint — the .zshenv analogue.
#
# Reached from three places:
#   * ~/.bash_profile (login shells)        → bash/.bash_profile
#   * ~/.bashrc (interactive non-login)     → bash/.bashrc
#   * $BASH_ENV (non-interactive children — `bash -c '…'`, scripts), the
#     parallel of zsh always sourcing .zshenv
# 21_bash_symlinks.zsh installs ~/.config/bash → this repo directory, so
# "$HOME/.config/bash/env.sh" below is stable. DOTFILES resolves from
# BASH_SOURCE through a symlink walk (readlink -f is GNU/macOS≥12.3 only —
# the scripts/generate-commit-msg pattern).

# Idempotent. Children of a shell that already ran env.sh inherit every
# export, so the guard makes re-sourcing a no-op instead of a re-run.
if [ -n "${_DOTFILES_BASH_ENV:-}" ]; then
    return 0
fi
_DOTFILES_BASH_ENV=1
export _DOTFILES_BASH_ENV

_envsh=${BASH_SOURCE[0]}
# Two-stage resolution: env.sh may be reached as a plain file inside a
# symlinked DIRECTORY (~/.config/bash → repo/bash), or as a file symlink
# itself. Walk the file's symlink chain first, then the directory's — either
# shape must land on the real repo path.
while [ -L "$_envsh" ]; do
    _envsh_link=$(readlink "$_envsh")
    case $_envsh_link in
        /*) _envsh=$_envsh_link ;;
        *) _envsh=${_envsh%/*}/$_envsh_link ;;
    esac
done
_envdir=${_envsh%/*}
while [ -L "$_envdir" ]; do
    _envdir_link=$(readlink "$_envdir")
    case $_envdir_link in
        /*) _envdir=$_envdir_link ;;
        *) _envdir=${_envdir%/*}/$_envdir_link ;;
    esac
done
export DOTFILES=${_envdir%/*}

# The shared layer keys off ZDOTDIR exactly like zsh does (.zshenv sets it
# before its env.d loop): 03_paths' fpath guard, 09's portkey probe, and the
# rc.d paths all read it.
export ZDOTDIR=$DOTFILES/zsh

# Non-interactive bash reads $BASH_ENV before anything else — pointing it
# here gives `bash -c` children the same env (the .zshenv parallel; without
# it, scripts under bash see a different world than scripts under zsh).
export BASH_ENV=$HOME/.config/bash/env.sh
# readline config without ~/.inputrc home presence (zero-home-presence rule).
export INPUTRC=$HOME/.config/bash/inputrc

# Source the SHARED env.d — the whole point of the port: one env layer,
# two shells. Every zsh/env.d/*.zsh file is dual-parseable and dual-runnable
# (docs/bash-compatibility.md §C); genuinely zsh-only behavior branches on
# ZSH_VERSION inside the files. The skip-list is therefore empty; if a file
# ever needs forking, add it here rather than editing around it.
# bash's default glob leaves an unmatched pattern literal, so a plain [ -e ]
# guard suffices (zsh additionally needs the null_glob sandwich — see
# zsh/.zshenv).
for _envfile in "$ZDOTDIR"/env.d/*; do
    [ -e "$_envfile" ] || continue
    [ "${_envfile##*.}" = enc ] && continue
    if ! . "$_envfile" 2>&1; then
        printf 'Warning: error in %s\n' "$_envfile" >&2
    fi
done
unset _envfile _envsh _envsh_link _envdir _envdir_link
