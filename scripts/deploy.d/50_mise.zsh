# Bootstrap mise, then run `mise install` to materialize tools from
# configs/mise.toml. Brew fallback follows for tools mise couldn't acquire.

if (( ! ${+commands[mise]} )); then
    print "Installing mise..."
    local mise_arch=$DOTFILES_ARCH
    local mise_os=${DOTFILES_OS:l}
    if [[ $mise_os == linux && ($mise_arch == x86_64 || $mise_arch == aarch64) ]]; then
        [[ $mise_arch == x86_64 ]] && mise_arch=x64
        [[ $mise_arch == aarch64 ]] && mise_arch=arm64
        local mise_version
        mise_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/jdx/mise/releases/latest | sed 's|.*/tag/v||')
        if [[ -n $mise_version ]]; then
            if curl -fsSL "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-${mise_os}-${mise_arch}" -o $HOME/.local/bin/mise; then
                chmod +x $HOME/.local/bin/mise
                export PATH=$HOME/.local/bin:$PATH
                print "  ...done"
            else
                print "  ...failed to download mise, skipping"
            fi
        else
            print "  ...failed to determine latest mise version, skipping"
        fi
    elif [[ $mise_os == darwin && ($mise_arch == x86_64 || $mise_arch == arm64) ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade mise mise || true
        fi
        if (( ! ${+commands[mise]} )); then
            local mise_dl_arch=$mise_arch
            [[ $mise_dl_arch == x86_64 ]] && mise_dl_arch=x64
            local mise_version
            mise_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/jdx/mise/releases/latest | sed 's|.*/tag/v||')
            if [[ -n $mise_version ]]; then
                if curl -fsSL "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-macos-${mise_dl_arch}" -o $HOME/.local/bin/mise; then
                    chmod +x $HOME/.local/bin/mise
                    export PATH=$HOME/.local/bin:$PATH
                    print "  ...done (direct download)"
                else
                    print "  ...failed to download mise, try: brew install mise"
                fi
            else
                print "  ...failed to determine latest mise version, try: brew install mise"
            fi
        else
            export PATH=$HOME/.local/bin:$PATH
        fi
    else
        print "  ...unsupported platform for mise auto-install, skipping"
    fi
fi

if (( ${+commands[mise]} )); then
    if $upgrade_mode; then
        print "Upgrading mise..."
        if mise self-update --yes --no-plugins > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...mise self-update had issues"
        fi
    fi

    print "Installing mise tools (node, bun, ruby, etc.)..."
    if mise install > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...mise install had issues"
    fi

    print "Upgrading mise tools..."
    if mise upgrade --yes > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...mise upgrade had issues"
    fi
fi

# Brew fallback for tools listed in mise.toml. Runs only on macOS, only when a
# tool is still missing post-mise (i.e., the aqua release URL drifted or mise
# itself isn't installed). Acts as a hedge, not a default path.
if [[ $DOTFILES_OS == Darwin ]] && ensure_homebrew_path 2>/dev/null; then
    local fallback_tool
    for fallback_tool in gh ripgrep neovim delta bat eza fd sd zoxide tree-sitter awscli ast-grep glab; do
        local fallback_bin=$fallback_tool
        case $fallback_tool in
            ripgrep) fallback_bin=rg ;;
            ast-grep) fallback_bin=sg ;;
            awscli)  fallback_bin=aws ;;
            neovim)  fallback_bin=nvim ;;
        esac
        if (( ! ${+commands[$fallback_bin]} )); then
            print "Mise didn't install $fallback_tool; trying brew fallback..."
            brew_install_or_upgrade $fallback_tool $fallback_bin || true
        fi
    done
fi
