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

# Run a mise subcommand quietly, but if it fails surface the captured output
# (last $1 lines) instead of swallowing it into /dev/null. mktemp keeps this
# BSD-clean; we only print on failure so success stays quiet.
run_mise_step() {
    local label=$1 tail_lines=$2; shift 2
    local log; log=$(mktemp "${TMPDIR:-/tmp}/mise-step.XXXXXX") || return 1
    # Capture rc on the line right after the command: in zsh, reading $? after
    # an `if cmd; then ...; fi` block yields 0 when the then-branch is skipped,
    # so we must grab it before any further construct runs.
    "$@" > "$log" 2>&1
    local rc=$?
    if (( rc == 0 )); then
        print "  ...done"
        rm -f "$log"
        return 0
    fi
    print "  ...$label had issues (exit $rc); last $tail_lines lines of output:"
    if [[ -s $log ]]; then
        tail -n "$tail_lines" "$log" | sed 's/^/    | /'
    else
        print "    | (no output captured)"
    fi
    rm -f "$log"
    return $rc
}

if (( ${+commands[mise]} )); then
    if $upgrade_mode; then
        print "Upgrading mise..."
        run_mise_step "mise self-update" 20 mise self-update --yes --no-plugins
    fi

    print "Installing mise tools (node, bun, python, etc.)..."
    run_mise_step "mise install" 30 mise install

    print "Upgrading mise tools..."
    run_mise_step "mise upgrade" 20 mise upgrade --yes
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
