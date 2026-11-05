# GNU userland PATH prepends — bash twin of zsh/rc.d/02b_gnubin_path.zsh
# (see that file for why this lives in rc.d: macOS path_helper rewrites
# PATH between the env layer and here, so prepends only stick now).
# Interactive-shell only — the bootstrap layer (scripts/, deploy.d/) keeps
# assuming raw BSD userland (CLAUDE.md).

if [[ $OSTYPE != darwin* ]] || [[ -z $HOMEBREW_PREFIX ]]; then
    return 0
fi

# A nested bash inherits _DOTFILES_BASH_ENV, so env.sh returns early and never
# defines path_prepend (functions aren't exported, but ZDOTDIR is). Load it
# here, or every prepend below fails and plain names fall back to BSD.
if ! declare -F path_prepend > /dev/null; then
    . "$ZDOTDIR/env.d/00_path_prepend.zsh"
fi

# Keep in sync with the gnu_formulae list in scripts/deploy.d/75_brew_setup.zsh
# (diffutils, gzip, less are linked unprefixed into $HOMEBREW_PREFIX/bin,
# which already precedes /usr/bin, so they need no entry here).
for _gnuutil in coreutils gnu-sed gnu-tar gawk findutils grep \
    make gnu-which gpatch gnu-time gnu-units gnu-indent ed; do
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnubin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnubin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnuman ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnuman:$MANPATH
    fi
done
unset _gnuutil

# Keg-only formulae: brew won't link them because they'd shadow a macOS
# tool (BSD getopt, Xcode's m4, macOS bc). Wire their bin dirs in by
# hand so e.g. `getopt --long foo,bar` works interactively.
for _gnuutil in gnu-getopt m4 bc; do
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/bin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$_gnuutil/bin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/share/man ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$_gnuutil/share/man:$MANPATH
    fi
done
unset _gnuutil

# zsh's tied manpath auto-exports; bash needs it explicit to have any effect.
export MANPATH
