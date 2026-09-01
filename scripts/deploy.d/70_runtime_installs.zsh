# curl/cargo installs for CLIs without a mise backend (Claude Code,
# rustup/cargo, linear-cli, CodeWhale), npm globals through the mise-managed
# node (pinned in configs/mise.toml, installed by 50_mise.zsh), and gjc as a
# bun global (bun-only package; see its block below).

if ! have claude; then
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
elif have mise; then
    # Drop mise installs that other installers own now. NOTE: node/npm and the
    # npm: backend tools that systemd units resolve through mise (npm:t3 for
    # t3-serve.service, npm:portless for the webfront runner + the pin in
    # mise.toml) must NEVER be listed here — a previous version of this list
    # uninstalled node itself on every deploy, which severed every unit that
    # execs through mise and crash-looped them for a week (2026-07).
    local -a obsolete_mise_tools=(
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

        # corepack is in the npm globals list AFTER pnpm, so its bin shim wins
        # the `pnpm` name (pnpm's own binary is demoted to `pn`). corepack then
        # serves pnpm from its OWN cache under $XDG_CACHE_HOME/node/corepack,
        # which npm never touches — so `pnpm@latest` in .default-npm-packages
        # updates `pn` while `pnpm` silently stays pinned to whatever corepack
        # last cached (it sat on 11.5.1 for months this way). Point corepack at
        # the current pnpm too so both names agree.
        print "Pointing corepack's pnpm shim at the current release..."
        if mise exec node -- corepack install -g pnpm@latest > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to refresh corepack pnpm (non-fatal)"
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

# gjc (gajae-code): a bun-ONLY package — its package.json declares
# `engines: { bun: ">=1.4.0" }` and bin/gjc.js runs under `#!/usr/bin/env bun`
# — so it CANNOT ride the npm globals sweep above; installing it with npm
# yields a binary that won't start. Tracked at @latest: the CLI moves fast and
# the config we ship for it (configs/ai/gjc/, linked in 20_symlinks.zsh)
# follows the current schema.
#
# bun's global bin dir ($XDG_CACHE_HOME/.bun/bin when BUN_INSTALL is unset) is
# NOT on any PATH here — only ~/.local/bin is (zsh/env.d/03_paths.zsh:46) — so
# link the binary there. A symlink beats adding a PATH entry to env.d because
# ~/.local/bin also reaches non-zsh callers (systemd units, paseo dispatch).
if have bun; then
    autoload -Uz is-at-least

    local gjc_bun_version gjc_bun_bin
    gjc_bun_version=$(bun --version 2>/dev/null)

    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would install/upgrade gajae-code (gjc) as a bun global"
    elif ! is-at-least 1.4.0 ${gjc_bun_version:-0}; then
        # 50_mise.zsh runs `mise upgrade` on every deploy, so bun should already
        # be current (configs/mise.toml pins the major, `bun = "1"`). If a box is
        # still behind, say so rather than planting a gjc its runtime can't run.
        print "gjc needs bun >= 1.4.0; this box has ${gjc_bun_version:-none}, skipping"
        print "  ...run 'mise upgrade bun', then ./deploy.zsh"
    else
        print "Installing/upgrading gjc (gajae-code) as a bun global..."
        if bun install -g gajae-code@latest > /dev/null 2>&1; then
            print "  ...done"
            # `bun install -g` rewrites node_modules/@gajae-code/coding-agent in
            # place, under anything already running out of it. Deliberately NOT a
            # reason to skip the upgrade: gjc's broker and daemon are long-lived
            # on ceres, so a "skip while running" guard would pin that box
            # forever. Unlike the openclaw beta->stable downgrades documented in
            # .default-npm-packages, this only ever moves forward — but a live
            # process keeps the old build, so name it and let the human restart.
            # Two cmdline shapes to catch: `bun ~/.local/bin/gjc <cmd>` and the
            # broker/daemon forms that exec straight out of node_modules.
            if pgrep -u "$USER" -f 'gajae-code|bin/gjc' > /dev/null 2>&1; then
                print "  ...note: gjc processes are running on the old build;"
                print "     restart them ('gjc daemon' / open sessions) to pick this up"
            fi
        else
            print "  ...failed to install gjc"
        fi
    fi

    # Drift-correct the ~/.local/bin bridge even when the install was skipped:
    # the link is what puts gjc on PATH at all, and it was hand-made (untracked)
    # on the boxes that had gjc before this fragment existed. deploy_ln (not
    # zf_ln) so --dry-run reports the link instead of refreshing it; `bun pm
    # bin -g` is read-only, so it is safe to probe in either mode.
    gjc_bun_bin=$(bun pm bin -g 2>/dev/null)
    if [[ -n $gjc_bun_bin && -x $gjc_bun_bin/gjc ]]; then
        deploy_ln -sfn $gjc_bun_bin/gjc $HOME/.local/bin/gjc
        (( DEPLOY_DRY_RUN )) || rehash
    fi
fi

if ! have cargo; then
    print "Installing rustup and cargo..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path > /dev/null 2>&1; then
        export PATH=$HOME/.cargo/bin:$PATH
        print "  ...done"
    else
        print "  ...failed to install rustup, skipping"
    fi
fi

# linear-cli: git-only upstream, no mise/aqua backend exists.
if have cargo; then
    if ! have linear-cli; then
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
if have cargo; then
    local codewhale_spec codewhale_package codewhale_binary codewhale_action
    local -a codewhale_cargo_packages=(
        codewhale-cli:codewhale
        codewhale-tui:codewhale-tui
    )

    for codewhale_spec in "${codewhale_cargo_packages[@]}"; do
        codewhale_package=${codewhale_spec%%:*}
        codewhale_binary=${codewhale_spec#*:}

        if ! have "$codewhale_binary"; then
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

# ghx (GitHub CLI caching layer) retired 2026-08: gh is mise-managed again
# (configs/mise.toml). Drift-correct hosts that still carry ghx's curl install:
# its install.sh planted ghx/ghxd plus a `gh` shim in ~/.local/bin, which would
# shadow mise's real gh on PATH. Only delete ~/.local/bin/gh when it is
# actually the shim (mentions ghx), never a real binary someone put there.
# ~/.ghx holds the cache and ghx's auto-managed gh binary. Brew hosts get the
# equivalent cleanup in 75_brew_setup.zsh.
if [[ -e $HOME/.local/bin/ghx || -d $HOME/.ghx ]]; then
    print "Removing ghx (gh is mise-managed again)..."
    # ghxd self-daemonizes (reparents to PID 1) and ignores SIGTERM; KILL it.
    pkill -9 -u "$USER" -x ghxd 2>/dev/null || true
    rm -f "$HOME/.local/bin/ghx" "$HOME/.local/bin/ghxd"
    if [[ -f $HOME/.local/bin/gh ]] && grep -q ghx "$HOME/.local/bin/gh" 2>/dev/null; then
        rm -f "$HOME/.local/bin/gh"
    fi
    rm -rf "$HOME/.ghx"
    rehash
    print "  ...done"
fi
