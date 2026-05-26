# macOS-only brew package setup that doesn't fit in 50_mise.zsh's fallback:
# brew upgrade in --upgrade mode, latest zsh registered as login shell,
# ncurses for Ghostty terminfo, engram tap, iTerm2 cask, Nerd Font cask.

# Find Homebrew on fresh macOS shells before running brew-managed setup.
if [[ $(uname -s) == Darwin ]] && (( ! ${+commands[brew]} )); then
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x $brew_bin ]]; then
            path=(${brew_bin:h} $path)
            break
        fi
    done
    unset brew_bin
fi

if (( ${+commands[brew]} )) && $upgrade_mode; then
    print "Updating Homebrew..."
    if brew update > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...brew update failed"
    fi
    print "Upgrading Homebrew packages..."
    if brew upgrade > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...brew upgrade had issues (may be normal if no updates)"
    fi
fi

# Install and register latest Homebrew zsh on macOS.
if [[ $(uname -s) == Darwin ]] && (( ! ${+commands[brew]} )); then
    print "Setting up latest zsh via Homebrew..."
    print "  ...Homebrew not found, skipping"
elif [[ $(uname -s) == Darwin ]] && (( ${+commands[brew]} )); then
    print "Setting up latest zsh via Homebrew..."
    if brew list --formula zsh > /dev/null 2>&1; then
        if $upgrade_mode; then
            if brew upgrade zsh > /dev/null 2>&1; then
                print "  ...zsh upgraded"
            else
                print "  ...zsh already latest or upgrade failed"
            fi
        else
            print "  ...zsh already installed"
        fi
    elif brew install zsh > /dev/null 2>&1; then
        print "  ...zsh installed"
    else
        print "  ...failed to install zsh"
    fi

    local brew_zsh="$(brew --prefix)/bin/zsh"
    if [[ -x $brew_zsh ]]; then
        if ! grep -Fxq "$brew_zsh" /etc/shells 2>/dev/null; then
            if (( EUID == 0 )); then
                print -r -- "$brew_zsh" >> /etc/shells
                print "  ...registered $brew_zsh in /etc/shells"
            elif (( ${+commands[sudo]} )) && sudo -n true 2>/dev/null; then
                print -r -- "$brew_zsh" | sudo tee -a /etc/shells > /dev/null
                print "  ...registered $brew_zsh in /etc/shells"
            else
                print "  ...$brew_zsh is not in /etc/shells"
                print "     run: echo $brew_zsh | sudo tee -a /etc/shells"
            fi
        fi

        local current_shell
        current_shell=$(dscl . -read /Users/$USER UserShell 2>/dev/null | awk '{print $2}')
        [[ -z $current_shell ]] && current_shell=$SHELL
        if [[ $current_shell != $brew_zsh ]]; then
            if grep -Fxq "$brew_zsh" /etc/shells 2>/dev/null \
                && chsh -s "$brew_zsh" "$USER" < /dev/null > /dev/null 2>&1; then
                print "  ...login shell changed to $brew_zsh"
            else
                print "  ...login shell is still $current_shell"
                print "     run: chsh -s $brew_zsh"
            fi
        else
            print "  ...login shell already uses $brew_zsh"
        fi
    fi
fi

# ncurses for Ghostty terminfo compilation.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing ncurses via brew..."
    brew_formula_install_or_upgrade ncurses || true
fi

# fd / git-delta: upstream releases dropped x86_64-apple-darwin, so we can't get
# them through mise on Intel Macs. brew bottles ship for both arches.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing fd via brew..."
    brew_formula_install_or_upgrade fd || true
    print "Installing git-delta via brew..."
    brew_formula_install_or_upgrade git-delta || true
fi

# engram tap install.
if (( ${+commands[brew]} )) && (( ! ${+commands[engram]} )); then
    print "Installing engram via brew..."
    if brew install gentleman-programming/tap/engram > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install engram"
    fi
elif (( ${+commands[brew]} )) && $upgrade_mode; then
    print "Upgrading engram via brew..."
    if brew upgrade gentleman-programming/tap/engram > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...engram already at latest or upgrade failed"
    fi
fi

# iTerm2 cask.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask iterm2 > /dev/null 2>&1; then
        print "Installing iTerm2..."
        brew_cask_install_or_upgrade iterm2 || true
    elif $upgrade_mode; then
        print "Upgrading iTerm2..."
        brew_cask_install_or_upgrade iterm2 || true
    fi
fi

configure_iterm2_profile

# JetBrains Mono Nerd Font cask.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask font-jetbrains-mono-nerd-font > /dev/null 2>&1; then
        print "Installing JetBrains Mono Nerd Font..."
        brew_cask_install_or_upgrade font-jetbrains-mono-nerd-font || true
    elif $upgrade_mode; then
        print "Upgrading JetBrains Mono Nerd Font..."
        brew_cask_install_or_upgrade font-jetbrains-mono-nerd-font || true
    fi
fi
