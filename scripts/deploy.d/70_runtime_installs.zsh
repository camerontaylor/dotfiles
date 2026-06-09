# curl/cargo installs for runtimes/CLIs without a mise backend:
# Claude Code, Vite+, rustup/cargo, linear-cli, CodeWhale.

if (( ! ${+commands[claude]} )); then
    print "Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install Claude Code"
    fi
fi

local vp_home="${VP_HOME:-$HOME/.vite-plus}"
local vp_bin="$vp_home/bin/vp"
local npm_bin="$vp_home/bin/npm"
local npm_packages_file="$SCRIPT_DIR/.default-npm-packages"
local installer_home="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/vite-plus-installer-home"

if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] would install/refresh Vite+ in $vp_home"
else
    if [[ ! -x $vp_bin || $upgrade_mode == true ]]; then
        print "Installing Vite+..."
        mkdir -p $installer_home
        # The official installer writes shell setup by default. Give it a
        # disposable shell home; checked-in zsh fragments own real shell setup.
        if env HOME=$installer_home ZDOTDIR=$installer_home \
            VP_HOME=$vp_home VP_NODE_MANAGER=yes \
            bash -c 'curl -fsSL https://vite.plus | bash' > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install Vite+"
        fi
    fi

    # Remove the pre-migration mise Node/npm installs FIRST. Doing this before
    # the Vite+ shim/prune step below means any vp shim still pointing into a
    # removed mise install becomes a detectable dangling link we can clear.
    if (( ${+commands[mise]} )); then
        local -a obsolete_mise_tools=(
            # gh dropped from mise.toml: ghx's gh shim now owns the gh command,
            # and a mise gh would shadow it on PATH. Uninstall any prior install
            # BEFORE the ghx fallback below runs, so its installer sees no real
            # gh and plants the shim.
            gh
            node
            npm
            npm:happy
            npm:@biomejs/biome
            npm:@openai/codex
            npm:oh-my-codex
            npm:@google/gemini-cli
            npm:t3
            npm:oh-my-claude-sisyphus
            npm:pnpm
            npm:vite-plus
            npm:tsx
            npm:portless
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

        print "Removing stale mise Node/npm installs..."
        mise uninstall -y --all $obsolete_mise_tools > /dev/null 2>&1 || true
        mise reshim --force -y > /dev/null 2>&1 || true
        print "  ...done"
    fi

    if [[ -x $vp_bin ]]; then
        export PATH="$vp_home/bin:$PATH"
        rehash

        print "Refreshing Vite+ Node/npm shims..."
        if VP_HOME=$vp_home VP_NODE_MANAGER=yes $vp_bin env setup --refresh > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to refresh Vite+ Node/npm shims"
        fi

        # Prune dangling shims left in vp's bin by the mise -> Vite+ migration.
        # vp's shim refresh will NOT overwrite a name that already exists, so a
        # stale symlink pointing at an uninstalled mise package (e.g. the old
        # npm-pnpm shim) keeps shadowing the real node-global binary and breaks
        # the tool on PATH. Clearing dead links lets the npm-globals install
        # below recreate correct shims.
        local _vp_shim
        for _vp_shim in $vp_home/bin/*(N); do
            if [[ -L $_vp_shim && ! -e $_vp_shim ]]; then
                rm -f -- $_vp_shim
            fi
        done

        if [[ -f $npm_packages_file ]]; then
            if [[ -x $npm_bin ]]; then
                local -a npm_packages=()
                local npm_package
                while IFS= read -r npm_package || [[ -n $npm_package ]]; do
                    [[ -z $npm_package || $npm_package == \#* ]] && continue
                    npm_packages+=("$npm_package")
                done < $npm_packages_file

                if (( ${#npm_packages} > 0 )); then
                    print "Installing npm globals through Vite+ npm..."
                    if $npm_bin install -g $npm_packages > /dev/null 2>&1; then
                        print "  ...done"
                    else
                        print "  ...failed to install npm globals"
                    fi
                fi
            else
                print "  ...Vite+ npm shim missing; skipping npm globals"
            fi
        fi
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
