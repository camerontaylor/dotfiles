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

        # Note: GNU userland gnubin PATH prepends live in
        # zsh/rc.d/02b_gnubin_path.zsh, NOT here. macOS's /etc/zprofile runs
        # `path_helper -s` after .zshenv, which rewrites PATH to put
        # /etc/paths entries (incl. /usr/bin) at the head and demotes any
        # prepends made in env.d to behind them. rc.d runs after that
        # rewrite, so the gnubin/gnu-getopt PATH manipulation has to live
        # there to actually take effect for `sed`, `find`, `awk`, etc.
        # Prefer curl installed via brew
        if [[ -d $HOMEBREW_PREFIX/opt/curl/bin ]]; then
            path=($HOMEBREW_PREFIX/opt/curl/bin $path)
        fi
        if [[ -d $HOMEBREW_PREFIX/opt/libpq/bin ]]; then
            path=($HOMEBREW_PREFIX/opt/libpq/bin $path)
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

# Android SDK. Android Studio's SDK Manager owns the install (do NOT hand it to
# mise — dual management fights the IDE); we only wire PATH and the env vars
# Gradle/NDK read. Location is OS-divergent: macOS ~/Library/Android/sdk, Linux
# ~/Android/Sdk (capital S). A pre-set $ANDROID_HOME wins, for odd installs.
if [[ -z $ANDROID_HOME ]]; then
    local _android_sdk
    for _android_sdk in $HOME/Library/Android/sdk $HOME/Android/Sdk; do
        [[ -d $_android_sdk ]] && break
        _android_sdk=
    done
    [[ -n $_android_sdk ]] && ANDROID_HOME=$_android_sdk
    unset _android_sdk
fi

if [[ -n $ANDROID_HOME && -d $ANDROID_HOME ]]; then
    export ANDROID_HOME
    # ANDROID_SDK_ROOT is deprecated in favour of ANDROID_HOME but is still what
    # older Gradle plugins and the NDK build scripts read. Export both.
    export ANDROID_SDK_ROOT=$ANDROID_HOME

    # APPEND, never prepend: platform-tools ships its own sqlite3 (also mke2fs,
    # make_f2fs) which would shadow /usr/bin/sqlite3. On macOS /etc/zprofile's
    # path_helper happens to demote env.d prepends behind /usr/bin anyway, but
    # Linux has no such backstop — appending makes that guarantee explicit on
    # both. Nothing here needs to win a name collision.
    [[ -d $ANDROID_HOME/platform-tools ]] && path=($path $ANDROID_HOME/platform-tools)

    # build-tools is version-stamped; take the highest so apksigner/zipalign/
    # aapt2 resolve. (/Nn) = dirs only, nullglob, numeric sort → 36.0.0 last.
    local -a _android_bt=($ANDROID_HOME/build-tools/*(/Nn))
    (( $#_android_bt )) && path=($path $_android_bt[-1])
    unset _android_bt
fi
