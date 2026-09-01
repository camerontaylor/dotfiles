# Source the rendered secret exports.
#
# The values themselves live OUTSIDE every git worktree, at
# $XDG_STATE_HOME/secrets/zsh/9x_*.zsh (mode 600), rendered from the private
# repo ~/.local/secrets by ~/.local/dotfiles/scripts/secrets-render.zsh. Only
# this loader is tracked.
#
# Why 89 and not 9x: .gitignore ignores zsh/env.d/9[0-9]_*, so a 9x loader
# could not be committed. 89 also keeps the load order right — the loader runs
# first, then any deliberate local 90-99 override still wins by sorting after
# it. Shadowing by intent is the convention's feature; shadowing by staleness
# was the bug this migration removed.
#
# XDG_STATE_HOME may not be exported yet at this point in .zshenv's env.d loop,
# so the default is expanded here rather than assumed.
#
# Silent no-op when the directory is absent: a box that has not completed the
# two-credential bootstrap must still get a working shell.

# A named function, invoked, then undefined — the dual-shell replacement for
# zsh's anonymous `() { … }` (a bash parse error, under which no credential
# would export). The glob uses the plain-glob + [ -e ] guard template; zsh
# errors on an unmatched glob before the guard could run, so null_glob is on
# for the loop under zsh only (bare `setopt` would be a bash 127; bash leaves
# the literal pattern for the guard to skip).
_dotfiles_load_secrets() {
    local _secrets_dir=${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh
    local _f
    [ -z "${ZSH_VERSION:-}" ] || setopt null_glob
    for _f in "$_secrets_dir"/*.zsh; do
        [ -e "$_f" ] || continue
        # shellcheck disable=SC1090  # rendered files are POSIX single-quoted
        source "$_f"
    done
    [ -z "${ZSH_VERSION:-}" ] || unsetopt null_glob
}
_dotfiles_load_secrets
unset -f _dotfiles_load_secrets
