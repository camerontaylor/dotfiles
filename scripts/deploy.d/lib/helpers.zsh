# Sourced by deploy.zsh before any fragment runs. Provides shared helpers used
# across multiple fragments. Not designed for standalone invocation.

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
