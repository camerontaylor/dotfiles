# Sourced by deploy.zsh before any fragment runs. Provides shared helpers used
# across multiple fragments. Not designed for standalone invocation.

# Dry-run-aware wrappers over the zf_ln / zf_mkdir builtins loaded by
# deploy.zsh. A real run passes straight through to the builtin (preserving
# its exit status, and so err_exit behavior); under --dry-run
# (DEPLOY_DRY_RUN=1) they print the intended command instead of mutating.
deploy_ln() {
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would ln $*"
    else
        zf_ln "$@"
    fi
}

deploy_mkdir() {
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would mkdir $*"
    else
        zf_mkdir "$@"
    fi
}

ensure_homebrew_path() {
    if (( ${+commands[brew]} )); then
        return 0
    fi

    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x $brew_bin ]]; then
            eval "$($brew_bin shellenv zsh)"
            rehash
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
        print "  ...Homebrew not available, skipping $formula"
        return 1
    fi

    if ! brew list --formula $formula > /dev/null 2>&1; then
        if brew install $formula > /dev/null 2>&1; then
            rehash
            print "  ...done"
            return 0
        fi
        print "  ...failed to install $formula"
        return 1
    elif (( ! ${+commands[$binary]} )); then
        if brew link $formula > /dev/null 2>&1 || brew link --overwrite $formula > /dev/null 2>&1; then
            rehash
            print "  ...linked"
            return 0
        fi
        print "  ...$formula installed but $binary is not on PATH"
        return 1
    elif $upgrade_mode; then
        if brew upgrade $formula > /dev/null 2>&1; then
            print "  ...done"
            return 0
        fi
        print "  ...$formula already at latest or upgrade failed"
        return 0
    fi
}

brew_cask_install_or_upgrade() {
    local cask=$1

    if ! ensure_homebrew_path; then
        print "  ...Homebrew not available, skipping $cask"
        return 1
    fi

    if ! brew list --cask $cask > /dev/null 2>&1; then
        if brew install --cask $cask > /dev/null 2>&1; then
            print "  ...done"
            return 0
        fi
        print "  ...failed to install $cask"
        return 1
    elif $upgrade_mode; then
        if brew upgrade --cask $cask > /dev/null 2>&1; then
            print "  ...done"
            return 0
        fi
        print "  ...$cask already at latest or upgrade failed"
        return 0
    fi
}

brew_formula_install_or_upgrade() {
    local formula=$1

    if ! ensure_homebrew_path; then
        print "  ...Homebrew not available, skipping $formula"
        return 1
    fi

    if ! brew list --formula $formula > /dev/null 2>&1; then
        if brew install $formula > /dev/null 2>&1; then
            rehash
            print "  ...done"
            return 0
        fi
        print "  ...failed to install $formula"
        return 1
    elif $upgrade_mode; then
        if brew upgrade $formula > /dev/null 2>&1; then
            print "  ...done"
            return 0
        fi
        print "  ...$formula already at latest or upgrade failed"
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

    print "Configuring iTerm2 Solarized Dark defaults..."
    if /usr/bin/python3 "$SCRIPT_DIR/scripts/configure-iterm2-profile.py" "$prefs" "$preset"; then
        print "  ...done"
    else
        print "  ...failed to update iTerm2 preferences"
    fi
}
