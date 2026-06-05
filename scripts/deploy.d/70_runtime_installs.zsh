# curl-based installs for runtimes/CLIs without a mise backend:
# Claude Code, Vite+, rustup/cargo, linear-cli.

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

    if [[ -x $vp_bin ]]; then
        export PATH="$vp_home/bin:$PATH"
        rehash

        print "Refreshing Vite+ Node/npm shims..."
        if VP_HOME=$vp_home VP_NODE_MANAGER=yes $vp_bin env setup --refresh > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to refresh Vite+ Node/npm shims"
        fi

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

    if (( ${+commands[mise]} )); then
        local -a obsolete_mise_tools=(
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
        )

        print "Removing stale mise Node/npm installs..."
        mise uninstall -y --all $obsolete_mise_tools > /dev/null 2>&1 || true
        mise reshim --force -y > /dev/null 2>&1 || true
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
