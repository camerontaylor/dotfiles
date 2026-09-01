# Add custom functions and completions
# fpath is zsh-only; bash's loader exports ZDOTDIR but has no fpath machinery.
[ -n "${ZSH_VERSION:-}" ] && fpath=($ZDOTDIR/fpath $fpath)

if [[ $OSTYPE = darwin* ]]; then
    # Locate brew at a known prefix WITHOUT prepending its sbin dir to PATH.
    # Homebrew 5.x's `brew shellenv` has an idempotency check: it emits
    # nothing when ${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin is already
    # at the head of PATH. Prepending both ourselves silences shellenv and
    # leaves evalcache refusing to cache empty output every shell start.
    # Adding only the bin dir keeps brew findable as a bare command for
    # evalcache (which uses ${+commands[brew]}) while letting shellenv add
    # sbin and the rest of the brew env via path_helper.
    # (No `local` — this runs at the top level of .zshenv/env.sh where bash
    # rejects it; `${_brew%/*}` replaces the zsh-only `${_brew:h}`.)
    _brew=
    for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x $_brew ]] && break
        _brew=
    done

    if [[ -n $_brew ]]; then
        if [ -n "${ZSH_VERSION:-}" ]; then
            path_prepend "${_brew%/*}"
            autoload -z evalcache
            evalcache brew shellenv
        else
            # bash: no evalcache. shellenv's own PATH prepend puts
            # bin:sbin at the head — do NOT pre-prepend bin as zsh does,
            # because bash has no unique tied array to dedup the copy back
            # off afterwards.
            eval "$("$_brew" shellenv)"
        fi

        # Note: GNU userland gnubin PATH prepends live in
        # zsh/rc.d/02b_gnubin_path.zsh, NOT here. macOS's /etc/zprofile runs
        # `path_helper -s` after .zshenv, which rewrites PATH to put
        # /etc/paths entries (incl. /usr/bin) at the head and demotes any
        # prepends made in env.d to behind them. rc.d runs after that
        # rewrite, so the gnubin/gnu-getopt PATH manipulation has to live
        # there to actually take effect for `sed`, `find`, `awk`, etc.
        # Prefer curl installed via brew
        # (two sequential path_prepend calls, like the two sequential
        # path=() prepends they replace: final order libpq:curl:<rest>;
        # the [[ -d ]] guards stay at the call site — path_prepend itself
        # deliberately does no existence check)
        if [[ -d $HOMEBREW_PREFIX/opt/curl/bin ]]; then
            path_prepend "$HOMEBREW_PREFIX/opt/curl/bin"
        fi
        if [[ -d $HOMEBREW_PREFIX/opt/libpq/bin ]]; then
            path_prepend "$HOMEBREW_PREFIX/opt/libpq/bin"
        fi
    fi
    unset _brew
else
    # Non-macOS: keep /usr/local/{bin,sbin} on PATH for locally installed tools
    path_prepend /usr/local/bin /usr/local/sbin
fi

# Enable local binaries and man pages
path_prepend "$HOME/.local/bin" "$HOME/.cargo/bin"
MANPATH=$XDG_DATA_HOME/man:$MANPATH

# Add go binaries to paths
path_prepend "$GOPATH/bin"

export PNPM_STORE_DIR="$XDG_DATA_HOME/pnpm/store"
