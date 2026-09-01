# GNU userland PATH prepends for macOS. Lives in rc.d (not env.d) because
# macOS's /etc/zprofile runs `path_helper -s` between .zshenv and .zshrc,
# which rewrites PATH to put /etc/paths entries (/usr/local/bin, /usr/bin,
# /bin, /usr/sbin, /sbin) at the head — demoting anything env.d/03_paths.zsh
# prepended to behind /usr/bin. rc.d runs after path_helper, so prepends
# here actually stick.
#
# Brew's gnubin pattern symlinks each formula's tools without the `g`
# prefix under libexec/gnubin, so prepending those dirs makes plain `sed`,
# `find`, `xargs`, `awk`, `tar` etc. resolve to GNU in this shell.
#
# Interactive-shell only — the bootstrap layer (scripts/, scripts/deploy.d/,
# zsh/, deploy.zsh) must still assume raw BSD userland (see CLAUDE.md):
# git hooks, cron, launchd, and non-interactive `bash -c '…'` invocations
# don't source .zshrc and won't have these dirs on PATH.

if [[ $OSTYPE != darwin* ]] || [[ -z $HOMEBREW_PREFIX ]]; then
    return 0
fi

for gnuutil in coreutils gnu-sed gnu-tar gawk findutils grep; do
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman:$MANPATH
    fi
done
unset gnuutil

# gnu-getopt is keg-only because it would shadow /usr/bin/getopt (BSD's
# short-opt-only version). Wire it in by hand so `getopt --long foo,bar`
# works interactively.
if [[ -d $HOMEBREW_PREFIX/opt/gnu-getopt/bin ]]; then
    path_prepend "$HOMEBREW_PREFIX/opt/gnu-getopt/bin"
fi
if [[ -d $HOMEBREW_PREFIX/opt/gnu-getopt/share/man ]]; then
    MANPATH=$HOMEBREW_PREFIX/opt/gnu-getopt/share/man:$MANPATH
fi
