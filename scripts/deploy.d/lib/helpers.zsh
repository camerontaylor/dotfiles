# Sourced by deploy.zsh before any fragment runs. Provides shared helpers used
# across multiple fragments. Not designed for standalone invocation.

# Shell-agnostic probe helpers (bash 3.2 + zsh). `have` replaces zsh's
# `(( ${+commands[x]} ))`; `isfunc` replaces `(( ${+functions[x]} ))` —
# `typeset -f` exits 0 for a defined function and 1 otherwise in both shells.
have() { command -v -- "$1" >/dev/null 2>&1; }
isfunc() { typeset -f -- "$1" >/dev/null 2>&1; }

# Absolute, symlink-resolved path of $1 — zsh's ${var:A} in portable form
# (the same walker as scripts/generate-commit-msg; `readlink -f` only exists
# on macOS >= 12.3 and `realpath` is not universal). Callers comparing an
# not-yet-existing path should tolerate failure: pipe stderr to /dev/null and
# treat an empty result as "differs from any existing path".
abspath() {
    local p=$1 d
    while [[ -L $p ]]; do
        d=$(cd -P -- "$(dirname -- "$p")" && pwd)
        p=$(readlink "$p")
        [[ $p != /* ]] && p=$d/$p
    done
    printf '%s\n' "$(cd -P -- "$(dirname -- "$p")" && pwd)/$(basename -- "$p")"
}

# POSIX single-quote a value so it re-parses as exactly one shell word
# ('it'\''s') — zsh's ${(qq)} in portable form; byte-identical output from
# both shells, safe inside eval/sh -c/unit files/plists. Built from
# ${var%%pat}/${var#pat} only: the ${var//pat/rep} replacement has
# shell-specific backslash rules and mis-quotes the '\'' splice.
sh_quote() {
    local s=$1 out=\' piece=
    while :; do
        piece=${s%%\'*}
        out=$out$piece
        [[ $s == "$piece" ]] && break
        out=$out"'\''"
        s=${s#*\'}
    done
    printf '%s' "$out'"
}

# Display form of a path with $HOME collapsed to ~ — zsh's ${(D)} in
# portable form; paths outside $HOME pass through unchanged.
tilde_collapse() {
    local p=$1
    case $p in
        "$HOME")   printf '~' ;;
        "$HOME"/*) printf '~%s' "${p#"$HOME"}" ;;
        *)         printf '%s' "$p" ;;
    esac
}

# version_ge HAVE WANT — 0 when dotted-numeric HAVE >= WANT ("1.4" counts as
# >= "1.4.0"; missing fields are 0). Replaces zsh's `autoload -Uz is-at-least`
# (bash has no autoload). A field's leading digits are its value, so a
# prerelease tail field-truncates ("1.4.1-beta" == "1.4.1") — the call sites
# only compare clean release versions.
version_ge() {
    local have=$1 want=$2 h w
    while :; do
        h=${have%%.*}; w=${want%%.*}
        h=${h%%[!0-9]*}; w=${w%%[!0-9]*}
        h=${h:-0}; w=${w:-0}
        (( h > w )) && return 0
        (( h < w )) && return 1
        [[ $have == *.* || $want == *.* ]] || return 0
        case $have in *.*) have=${have#*.} ;; *) have=0 ;; esac
        case $want in *.*) want=${want#*.} ;; *) want=0 ;; esac
    done
}

# Dry-run-aware wrappers over the mutating coreutils. A real run passes
# straight through to the command (preserving its exit status, and so
# err_exit behavior); under --dry-run (DEPLOY_DRY_RUN=1) they print the
# intended command instead of mutating. Plain ln/mkdir/chmod/rm — not the
# zsh/files zf_* builtins — so fragments stay shell-agnostic (bash has no
# zmodload; deploy.zsh's own zmodload covers only its internal use).
deploy_ln() {
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would ln $*"
    else
        ln "$@"
    fi
}

deploy_mkdir() {
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would mkdir $*"
    else
        mkdir "$@"
    fi
}

deploy_chmod() {
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would chmod $*"
    else
        chmod "$@"
    fi
}

deploy_rm() {
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would rm $*"
    else
        rm "$@"
    fi
}

ensure_homebrew_path() {
    if have brew; then
        return 0
    fi

    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x $brew_bin ]]; then
            eval "$($brew_bin shellenv zsh)"
            hash -r
            return 0
        fi
    done

    return 1
}

# Homebrew's tap-trust gate (HOMEBREW_REQUIRE_TAP_TRUST) makes brew ignore
# formulae/casks/commands from non-official taps until each is explicitly
# trusted — otherwise `brew install`/`brew list` silently skip them. We trust
# the *specific* items we install rather than whole taps (Homebrew's own
# recommendation), so a tap shipping an unrelated formula later never gets
# implicitly trusted. Idempotent (re-trusting is a no-op) and a no-op on brew
# versions predating the `trust` subcommand, so it is safe to call every run.
#   usage: brew_trust --formula <user>/<tap>/<name>
#          brew_trust --cask    <user>/<tap>/<name>
brew_trust() {
    local kind=$1 target=$2   # kind: --formula | --cask | --command

    ensure_homebrew_path || return 1

    # Feature-detect the subcommand once per deploy; older brew lacks it.
    if [[ -z $DOTFILES_BREW_HAS_TRUST ]]; then
        if brew trust --help > /dev/null 2>&1; then
            DOTFILES_BREW_HAS_TRUST=1
        else
            DOTFILES_BREW_HAS_TRUST=0
        fi
    fi
    (( DOTFILES_BREW_HAS_TRUST )) || return 0

    brew trust $kind $target > /dev/null 2>&1 || true
}

brew_install_or_upgrade() {
    local formula=$1
    local binary=${2:-$formula}

    if ! ensure_homebrew_path; then
        printf '%s\n' "  ...Homebrew not available, skipping $formula"
        return 1
    fi

    if ! brew list --formula $formula > /dev/null 2>&1; then
        if brew install $formula > /dev/null 2>&1; then
            hash -r
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...failed to install $formula"
        return 1
    elif ! have "$binary"; then
        if brew link $formula > /dev/null 2>&1 || brew link --overwrite $formula > /dev/null 2>&1; then
            hash -r
            printf '%s\n' "  ...linked"
            return 0
        fi
        printf '%s\n' "  ...$formula installed but $binary is not on PATH"
        return 1
    elif $upgrade_mode; then
        if brew upgrade $formula > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...$formula already at latest or upgrade failed"
        return 0
    fi
}

brew_cask_install_or_upgrade() {
    local cask=$1

    if ! ensure_homebrew_path; then
        printf '%s\n' "  ...Homebrew not available, skipping $cask"
        return 1
    fi

    if ! brew list --cask $cask > /dev/null 2>&1; then
        if brew install --cask $cask > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...failed to install $cask"
        return 1
    elif $upgrade_mode; then
        if brew upgrade --cask $cask > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...$cask already at latest or upgrade failed"
        return 0
    fi
}

brew_formula_install_or_upgrade() {
    local formula=$1

    if ! ensure_homebrew_path; then
        printf '%s\n' "  ...Homebrew not available, skipping $formula"
        return 1
    fi

    if ! brew list --formula $formula > /dev/null 2>&1; then
        if brew install $formula > /dev/null 2>&1; then
            hash -r
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...failed to install $formula"
        return 1
    elif $upgrade_mode; then
        if brew upgrade $formula > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
            return 0
        fi
        printf '%s\n' "  ...$formula already at latest or upgrade failed"
        return 0
    fi
}

# Keep iTerm2's default profile aligned with the Solarized Dark preset used by Ghostty.
# Heavy lifting lives in scripts/configure-iterm2-profile.py.
configure_iterm2_profile() {
    if [[ $DOTFILES_OS != Darwin ]]; then
        return 0
    fi

    local prefs="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
    local preset="/Applications/iTerm.app/Contents/Resources/ColorPresets.plist"

    if [[ ! -f $prefs || ! -f $preset ]]; then
        return 0
    fi

    printf '%s\n' "Configuring iTerm2 Solarized Dark defaults..."
    if /usr/bin/python3 "$SCRIPT_DIR/scripts/configure-iterm2-profile.py" "$prefs" "$preset"; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  ...failed to update iTerm2 preferences"
    fi
}
