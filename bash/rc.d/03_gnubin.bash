# GNU userland PATH prepends — bash twin of zsh/rc.d/02b_gnubin_path.zsh
# (see that file for why this lives in rc.d: macOS path_helper rewrites
# PATH between the env layer and here, so prepends only stick now).
# Interactive-shell only — the bootstrap layer (scripts/, deploy.d/) keeps
# assuming raw BSD userland (CLAUDE.md).

if [[ $OSTYPE != darwin* ]] || [[ -z $HOMEBREW_PREFIX ]]; then
    return 0
fi

for _gnuutil in coreutils gnu-sed gnu-tar gawk findutils grep; do
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnubin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnubin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnuman ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$_gnuutil/libexec/gnuman:$MANPATH
    fi
done
unset _gnuutil

# gnu-getopt is keg-only (would shadow BSD /usr/bin/getopt); wired by hand.
if [[ -d $HOMEBREW_PREFIX/opt/gnu-getopt/bin ]]; then
    path_prepend "$HOMEBREW_PREFIX/opt/gnu-getopt/bin"
fi
if [[ -d $HOMEBREW_PREFIX/opt/gnu-getopt/share/man ]]; then
    MANPATH=$HOMEBREW_PREFIX/opt/gnu-getopt/share/man:$MANPATH
fi
# zsh's tied manpath auto-exports; bash needs it explicit to have any effect.
export MANPATH
