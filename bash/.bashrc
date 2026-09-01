# Interactive shells. Non-interactive bash never reads this file, but
# scripts may source it defensively — `case $-` is the dual-shell spelling
# of zsh's `[[ -o interactive ]]`.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

# Env layer: shared zsh/env.d + DOTFILES/ZDOTDIR resolution (idempotent —
# env.sh guards itself). Prefer the deployed ~/.config/bash path; fall back
# to this file's own directory when running straight from the repo.
_bashrc_env=$HOME/.config/bash/env.sh
[ -r "$_bashrc_env" ] || _bashrc_env=${BASH_SOURCE[0]%/*}/env.sh
. "$_bashrc_env"
unset _bashrc_env

# Interactive layer — bash-native fragments mirroring zsh/rc.d/*.zsh.
# Sourced in lex order, like every other fragment loop in this repo.
# bash's default glob leaves an unmatched pattern literal, so the plain
# [ -e ] guard suffices.
for _rcfile in "$DOTFILES"/bash/rc.d/*; do
    [ -e "$_rcfile" ] || continue
    [ "${_rcfile##*.}" = enc ] && continue
    if ! . "$_rcfile"; then
        printf 'Warning: error in %s\n' "$_rcfile" >&2
    fi
done
unset _rcfile

# Function ports of the zsh/fpath utilities that must cd the calling shell
# (w, fz, ineachdir) — they cannot be bin/ scripts. Eagerly sourced: there
# are only three, and lazy loading has no bash autoload to build on.
for _fnfile in "$DOTFILES"/bash/fpath.d/*; do
    [ -e "$_fnfile" ] || continue
    . "$_fnfile"
done
unset _fnfile
