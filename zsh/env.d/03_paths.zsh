# Add custom functions and completions
fpath=($ZDOTDIR/fpath $fpath)

if [[ $OSTYPE = darwin* ]]; then
    # Locate brew at a known prefix WITHOUT prepending its sbin dir to PATH.
    # Homebrew 5.x's `brew shellenv` has an idempotency check: it emits
    # nothing when ${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin is already
    # at the head of PATH. Prepending both ourselves silences shellenv and
    # leaves evalcache refusing to cache empty output every shell start.
    # Adding only the bin dir keeps brew findable as a bare command for
    # evalcache (which uses ${+commands[brew]}) while letting shellenv add
    # sbin and the rest of the brew env via path_helper.
    local _brew
    for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x $_brew ]] && break
        _brew=
    done

    if [[ -n $_brew ]]; then
        path=(${_brew:h} $path)
        autoload -z evalcache
        evalcache brew shellenv

        # Enable gnu version of utilities on macOS, if installed
        for gnuutil in coreutils gnu-sed gnu-tar grep; do
            if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin ]]; then
                path=($HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnubin $path)
            fi
            if [[ -d $HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman ]]; then
                MANPATH=$HOMEBREW_PREFIX/opt/$gnuutil/libexec/gnuman:$MANPATH
            fi
        done
        unset gnuutil
        # Prefer curl installed via brew
        if [[ -d $HOMEBREW_PREFIX/opt/curl/bin ]]; then
            path=($HOMEBREW_PREFIX/opt/curl/bin $path)
        fi
    fi
    unset _brew
else
    # Non-macOS: keep /usr/local/{bin,sbin} on PATH for locally installed tools
    path=(/usr/local/bin /usr/local/sbin $path)
fi

# Enable local binaries and man pages
path=($HOME/.local/bin $HOME/.cargo/bin $path)
MANPATH=$XDG_DATA_HOME/man:$MANPATH

# Add go binaries to paths
path=($GOPATH/bin $path)

export PNPM_STORE_DIR="$XDG_DATA_HOME/pnpm/store"
