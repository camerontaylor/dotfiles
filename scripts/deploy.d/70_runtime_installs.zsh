# curl/cargo installs for CLIs without a mise backend (rustup/cargo,
# linear-cli, CodeRabbit) and npm globals through the mise-managed node (pinned
# in configs/mise.toml, installed by 50_mise.zsh). Claude Code / moor /
# wtp-Linux moved to mise backends (configs/mise.toml) — the drift-correctors
# below retire what this fragment used to install by hand.
#
# Dry-run contract (AGENTS.md): same story as 50_mise.zsh — the npm
# block below had a per-step gate, but the curl/rustup/cargo blocks did not,
# and on a provisioned box every install is a quiet `have`-skipped no-op, so
# nothing looked wrong until a fresh HOME (CI) got a real rust toolchain
# mid-"dry-run". The fragment is 100% mutation, so preview at fragment scope.
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "Runtime installs skipped in dry-run (would: npm globals, coderabbit, rustup, linear-cli, claude + retired-tool drift cleanup)"
    return 0
fi

# Claude Code is mise-managed (aqua:anthropics/claude-code). Drift-correct
# hosts that still carry the native installer's layout (claude.ai/install.sh
# era): a ~/.local/bin/claude symlink into ~/.local/share/claude plus its
# versions dir. mise shims precede ~/.local/bin on PATH, so the drift never
# wins interactively — this is hygiene plus reclaiming the duplicate bytes.
# Only remove the symlink when it really points into the native install,
# never a real binary someone put there; ~/.claude (config) is a different
# tree and untouched.
if [[ -L $HOME/.local/bin/claude ]]; then
    _claude_target=$(readlink $HOME/.local/bin/claude)
    case $_claude_target in
        "$HOME"/.local/share/claude/*)
            printf '%s\n' "Removing native-install Claude Code (mise owns claude now)..."
            rm -f $HOME/.local/bin/claude
            rm -rf $HOME/.local/share/claude
            hash -r
            printf '%s\n' "  ...done"
            ;;
    esac
fi
unset _claude_target

npm_packages_file="$SCRIPT_DIR/.default-npm-packages"

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would install npm globals through mise node's npm"
elif have mise; then
    # Drop mise installs that other installers own now. NOTE: node/npm, the
    # npm: backend tools that systemd units resolve through mise (npm:t3 for
    # t3-serve.service), and npm:portless (retained in mise.toml as generic
    # dev tooling — its webfront-runner consumer was retired 2026-09-08) must
    # NEVER be listed here — a previous version of this list uninstalled node
    # itself on every deploy, which severed every unit that execs through mise
    # and crash-looped them for a week (2026-07).
    obsolete_mise_tools=(
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

    printf '%s\n' "Removing stale mise installs..."
    mise uninstall -y --all "${obsolete_mise_tools[@]}" > /dev/null 2>&1 || true
    printf '%s\n' "  ...done"

    # Retired npm GLOBALS. Dropping a line from .default-npm-packages only
    # stops future installs — it does not uninstall anything, so without this
    # sweep a retired CLI stays on every box that ever deployed it and keeps
    # resolving on PATH through the mise shims. That is the whole difference
    # between "the repo no longer installs X" and "the fleet no longer has X".
    #
    # Same hard rule as obsolete_mise_tools above: node, npm, corepack, pnpm
    # and anything a systemd unit execs through the shims must NEVER appear
    # here.
    obsolete_npm_globals=(
        "@google/gemini-cli"   # retired 2026-09-18, no longer in use
    )

    # npm globals install into the active mise node's prefix through its own
    # npm; `mise reshim` then exposes them via ~/.local/share/mise/shims to
    # every shell AND to systemd units. (mise also auto-installs this list
    # when it installs a new node version, via the ~/.default-npm-packages
    # symlink planted by 20_symlinks.zsh.)
    mise_node_ok=false
    if mise exec node -- node --version > /dev/null 2>&1; then
        mise_node_ok=true
    else
        printf '%s\n' "  ...mise node unavailable (mise install node); skipping npm globals"
    fi

    # Sweep the retired globals declared above. Gated on mise_node_ok for the
    # same reason the install is: without a working node there is no npm to
    # call, and a failed uninstall must never look like a successful one.
    if [[ $mise_node_ok == true && ${#obsolete_npm_globals[@]} -gt 0 ]]; then
        printf '%s\n' "Removing retired npm globals..."
        mise exec node -- npm uninstall -g "${obsolete_npm_globals[@]}" > /dev/null 2>&1 || true
        printf '%s\n' "  ...done"
    fi

    if [[ $mise_node_ok == true && -f $npm_packages_file ]]; then
        npm_packages=()
        npm_package=
        while IFS= read -r npm_package || [[ -n $npm_package ]]; do
            [[ -z $npm_package || $npm_package == \#* ]] && continue
            npm_packages+=("$npm_package")
        done < $npm_packages_file

        if (( ${#npm_packages[@]} > 0 )); then
            printf '%s\n' "Installing npm globals through mise node's npm..."
            if mise exec node -- npm install -g "${npm_packages[@]}" > /dev/null 2>&1; then
                printf '%s\n' "  ...done"
            else
                printf '%s\n' "  ...failed to install npm globals"
            fi
        fi

        # corepack is in the npm globals list AFTER pnpm, so its bin shim wins
        # the `pnpm` name (pnpm's own binary is demoted to `pn`). corepack then
        # serves pnpm from its OWN cache under $XDG_CACHE_HOME/node/corepack,
        # which npm never touches — so `pnpm@latest` in .default-npm-packages
        # updates `pn` while `pnpm` silently stays pinned to whatever corepack
        # last cached (it sat on 11.5.1 for months this way). Point corepack at
        # the current pnpm too so both names agree.
        printf '%s\n' "Pointing corepack's pnpm shim at the current release..."
        if mise exec node -- corepack install -g pnpm@latest > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to refresh corepack pnpm (non-fatal)"
        fi
    fi

    mise reshim --force -y > /dev/null 2>&1 || true
    hash -r

    # One-shot teardown of the abandoned Vite+ node manager. vp hijacked
    # node/npm/pnpm through ~/.vite-plus/bin shims that only interactive
    # shells had on PATH, while systemd units kept resolving node through
    # mise — a split-brain that made service breakage invisible from a
    # terminal. Only remove once the mise node demonstrably works, so a
    # botched deploy can't leave the machine with no node at all.
    if [[ $mise_node_ok == true && -d $HOME/.vite-plus ]]; then
        printf '%s\n' "Removing Vite+ (node/npm are mise-managed; see configs/mise.toml)..."
        rm -rf -- $HOME/.vite-plus
        printf '%s\n' "  ...done"
    fi
fi

# gjc (gajae-code) — RETIRED 2026-09-18. It used to be installed here as a bun
# global (a bun-ONLY package: `engines: { bun: ">=1.4.0" }`, bin/gjc.js under
# `#!/usr/bin/env bun`) and bridged onto PATH with a ~/.local/bin/gjc symlink,
# because bun's global bin dir is on no PATH here.
#
# Both are drift-corrected away rather than merely un-installed, for the same
# reason as obsolete_npm_globals above: a box that already deployed gjc keeps
# both the bun global and the hand-made symlink forever otherwise, and the
# symlink is what put it on PATH for systemd units and paseo dispatch.
#
# NOTE for whoever removes this block later: bun itself stays. gjc was its only
# REQUIRED consumer (docs/cli-tools.md said as much), but bun is still a pinned
# runtime in configs/mise.toml, still offered as an alternative runner for
# configs/karabiner/karabiner.ts, and still has a completion row in
# 82_zsh_completions.zsh. Retiring bun is a separate decision.
deploy_rm -f "$HOME/.local/bin/gjc"
if have bun && [[ -z ${DEPLOY_DRY_RUN:+x} || $DEPLOY_DRY_RUN -eq 0 ]]; then
    if bun pm ls -g 2>/dev/null | grep -q gajae-code; then
        printf '%s\n' "Removing retired gjc (gajae-code) bun global..."
        bun remove -g gajae-code > /dev/null 2>&1 || true
        printf '%s\n' "  ...done"
    fi
fi

# CodeRabbit ships native macOS/Linux binaries through its official installer.
# Download completely before running; CI suppresses its browser-login prompt.
# Supply the managed bin directory on PATH so it never edits shell profiles.
if ! have coderabbit || $upgrade_mode; then
    printf '%s\n' "Installing/upgrading CodeRabbit CLI..."
    _coderabbit_installer=
    if _coderabbit_installer=$(mktemp "${TMPDIR:-/tmp}/coderabbit-install.XXXXXX"); then
        if curl --proto '=https' --tlsv1.2 -fsSL https://cli.coderabbit.ai/install.sh -o "$_coderabbit_installer" &&
            CI=1 CODERABBIT_INSTALL_DIR="$HOME/.local/bin" PATH="$HOME/.local/bin:$PATH" sh "$_coderabbit_installer" > /dev/null 2>&1; then
            hash -r
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to install CodeRabbit (non-fatal)"
        fi
        rm -f "$_coderabbit_installer"
    else
        printf '%s\n' "  ...failed to create CodeRabbit installer tempfile (non-fatal)"
    fi
    unset _coderabbit_installer
fi

if ! have cargo; then
    printf '%s\n' "Installing rustup and cargo..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path > /dev/null 2>&1; then
        export PATH=$HOME/.cargo/bin:$PATH
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  ...failed to install rustup, skipping"
    fi
fi

# linear-cli: git-only upstream, no mise/aqua/ubi backend exists (the crates
# release is stale; only the git master branch builds) — the one deliberate
# cargo-of-git install left (documented exception, docs/cli-tools.md).
if have cargo; then
    if ! have linear-cli; then
        printf '%s\n' "Installing linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to install linear-cli"
        fi
    elif $upgrade_mode; then
        printf '%s\n' "Upgrading linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked --force > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to upgrade linear-cli"
        fi
    fi
fi

# ghx (GitHub CLI caching layer) retired 2026-08: gh is mise-managed again
# (configs/mise.toml). Drift-correct hosts that still carry ghx's curl install:
# its install.sh planted ghx/ghxd plus a `gh` shim in ~/.local/bin, which would
# shadow mise's real gh on PATH. Only delete ~/.local/bin/gh when it is
# actually the shim (mentions ghx), never a real binary someone put there.
# ~/.ghx holds the cache and ghx's auto-managed gh binary. Brew hosts get the
# equivalent cleanup in 75_brew_setup.zsh.
if [[ -e $HOME/.local/bin/ghx || -d $HOME/.ghx ]]; then
    printf '%s\n' "Removing ghx (gh is mise-managed again)..."
    # ghxd self-daemonizes (reparents to PID 1) and ignores SIGTERM; KILL it.
    pkill -9 -u "$USER" -x ghxd 2>/dev/null || true
    rm -f "$HOME/.local/bin/ghx" "$HOME/.local/bin/ghxd"
    if [[ -f $HOME/.local/bin/gh ]] && grep -q ghx "$HOME/.local/bin/gh" 2>/dev/null; then
        rm -f "$HOME/.local/bin/gh"
    fi
    rm -rf "$HOME/.ghx"
    hash -r
    printf '%s\n' "  ...done"
fi
