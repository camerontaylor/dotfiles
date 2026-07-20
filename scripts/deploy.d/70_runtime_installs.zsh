# curl/cargo installs for CLIs without a mise backend (Claude Code,
# rustup/cargo, linear-cli, CodeWhale, ghx) plus npm globals through the
# mise-managed node (pinned in configs/mise.toml, installed by 50_mise.zsh).

if (( ! ${+commands[claude]} )); then
    print "Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install Claude Code"
    fi
fi

local npm_packages_file="$SCRIPT_DIR/.default-npm-packages"

if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] would install npm globals through mise node's npm"
elif (( ${+commands[mise]} )); then
    # Drop mise installs that other installers own now. NOTE: node/npm and the
    # npm: backend tools that systemd units resolve through mise (npm:t3 for
    # t3-serve.service, npm:portless for the webfront runner + the pin in
    # mise.toml) must NEVER be listed here — a previous version of this list
    # uninstalled node itself on every deploy, which severed every unit that
    # execs through mise and crash-looped them for a week (2026-07).
    local -a obsolete_mise_tools=(
        # gh dropped from mise.toml: ghx's gh shim now owns the gh command,
        # and a mise gh would shadow it on PATH. Uninstall any prior install
        # BEFORE the ghx fallback below runs, so its installer sees no real
        # gh and plants the shim.
        gh
        # Old npm: backend installs replaced by the npm globals below.
        npm:happy
        npm:@biomejs/biome
        npm:@openai/codex
        npm:oh-my-codex
        npm:@google/gemini-cli
        npm:oh-my-claude-sisyphus
        npm:pnpm
        npm:vite-plus
        npm:tsx
        npm:agent-browser
        npm:@ast-grep/cli
        npm:@ast-grep/napi
        npm:oxlint
        npm:not-claude-code-emulator
        npm:@oh-my-pi/pi-coding-agent
        npm:@aoagents/ao
        npm:@code-yeongyu/comment-checker
        github:usewhale/DeepSeek-COde-Whale
        github:usewhale/DeepSeek-Code-Whale
    )

    print "Removing stale mise installs..."
    mise uninstall -y --all $obsolete_mise_tools > /dev/null 2>&1 || true
    print "  ...done"

    # npm globals install into the active mise node's prefix through its own
    # npm; `mise reshim` then exposes them via ~/.local/share/mise/shims to
    # every shell AND to systemd units. (mise also auto-installs this list
    # when it installs a new node version, via the ~/.default-npm-packages
    # symlink planted by 20_symlinks.zsh.)
    local mise_node_ok=false
    if mise exec node -- node --version > /dev/null 2>&1; then
        mise_node_ok=true
    else
        print "  ...mise node unavailable (mise install node); skipping npm globals"
    fi

    if [[ $mise_node_ok == true && -f $npm_packages_file ]]; then
        local -a npm_packages=()
        local npm_package
        while IFS= read -r npm_package || [[ -n $npm_package ]]; do
            [[ -z $npm_package || $npm_package == \#* ]] && continue
            npm_packages+=("$npm_package")
        done < $npm_packages_file

        if (( ${#npm_packages} > 0 )); then
            print "Installing npm globals through mise node's npm..."
            if mise exec node -- npm install -g $npm_packages > /dev/null 2>&1; then
                print "  ...done"
            else
                print "  ...failed to install npm globals"
            fi
        fi
    fi

    mise reshim --force -y > /dev/null 2>&1 || true
    rehash

    # One-shot teardown of the abandoned Vite+ node manager. vp hijacked
    # node/npm/pnpm through ~/.vite-plus/bin shims that only interactive
    # shells had on PATH, while systemd units kept resolving node through
    # mise — a split-brain that made service breakage invisible from a
    # terminal. Only remove once the mise node demonstrably works, so a
    # botched deploy can't leave the machine with no node at all.
    if [[ $mise_node_ok == true && -d $HOME/.vite-plus ]]; then
        print "Removing Vite+ (node/npm are mise-managed; see configs/mise.toml)..."
        rm -rf -- $HOME/.vite-plus
        print "  ...done"
    fi
fi

if (( ! ${+commands[cargo]} )); then
    print "Installing rustup and cargo..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path > /dev/null 2>&1; then
        export PATH=$HOME/.cargo/bin:$PATH
        print "  ...done"
    else
        print "  ...failed to install rustup, skipping"
    fi
fi

# linear-cli: git-only upstream, no mise/aqua backend exists.
if (( ${+commands[cargo]} )); then
    if (( ! ${+commands[linear-cli]} )); then
        print "Installing linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install linear-cli"
        fi
    elif $upgrade_mode; then
        print "Upgrading linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked --force > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to upgrade linear-cli"
        fi
    fi
fi

# CodeWhale: crates.io is the most direct update source for both the CLI and TUI.
if (( ${+commands[cargo]} )); then
    local codewhale_spec codewhale_package codewhale_binary codewhale_action
    local -a codewhale_cargo_packages=(
        codewhale-cli:codewhale
        codewhale-tui:codewhale-tui
    )

    for codewhale_spec in "${codewhale_cargo_packages[@]}"; do
        codewhale_package=${codewhale_spec%%:*}
        codewhale_binary=${codewhale_spec#*:}

        if (( ! ${+commands[$codewhale_binary]} )); then
            codewhale_action=install
        elif $upgrade_mode; then
            codewhale_action=upgrade
        else
            continue
        fi

        if [[ $codewhale_action == install ]]; then
            print "Installing $codewhale_package via cargo..."
        else
            print "Upgrading $codewhale_package via cargo..."
        fi
        if cargo install "$codewhale_package" --locked --force > /dev/null 2>&1; then
            rehash
            print "  ...done"
        else
            print "  ...failed to $codewhale_action $codewhale_package"
        fi
    done
fi

# ghx — GitHub CLI caching daemon. Brew-equipped hosts install it in
# 75_brew_setup.zsh; this is the fallback for hosts WITHOUT brew (most Linux),
# pulling the release binary into ~/.local/bin (on PATH, no sudo). Runs LAST so
# the mise-gh uninstall above has already happened: with no real gh on PATH,
# install.sh plants its `gh` shim, so `gh` -> ghx -> ghx's auto-managed gh under
# ~/.ghx/bin. install.sh auto-detects linux/darwin x amd64/arm64. --upgrade
# re-fetches the latest release.
if (( ! ${+commands[brew]} )) && { (( ! ${+commands[ghx]} )) || [[ $upgrade_mode == true ]]; }; then
    print "Installing ghx..."
    if curl -fsSL https://raw.githubusercontent.com/brunoborges/ghx/main/install.sh \
        | INSTALL_DIR=$HOME/.local/bin bash > /dev/null 2>&1; then
        rehash
        print "  ...done"
    else
        print "  ...failed to install ghx"
    fi
fi
