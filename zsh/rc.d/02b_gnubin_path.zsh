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

# Keep in sync with the gnu_formulae list in scripts/deploy.d/75_brew_setup.zsh
# (diffutils, gzip, less are linked unprefixed into $HOMEBREW_PREFIX/bin,
# which already precedes /usr/bin, so they need no entry here).
for gnuutil in coreutils gnu-sed gnu-tar gawk findutils grep \
    make gnu-which gpatch gnu-time gnu-units gnu-indent ed; do
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman:$MANPATH
    fi
done
unset gnuutil

# Keg-only formulae: brew won't link them because they'd shadow a macOS
# tool (BSD getopt, Xcode's m4, macOS bc). Wire their bin dirs in by
# hand so e.g. `getopt --long foo,bar` works interactively.
for gnuutil in gnu-getopt m4 bc; do
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/bin ]]; then
        path_prepend "$HOMEBREW_PREFIX/opt/$gnuutil/bin"
    fi
    if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/share/man ]]; then
        MANPATH=$HOMEBREW_PREFIX/opt/$gnuutil/share/man:$MANPATH
    fi
done
unset gnuutil
