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

    # mise hits the GitHub API for aqua release metadata and artifact
    # attestation verification. Unauthenticated requests are capped at 60/hr
    # and fail with 403 mid-install, leaving tools half-provisioned. Feed it a
    # token from the usual sources if one is reachable.
    if [[ -z $MISE_GITHUB_TOKEN && -z $GITHUB_TOKEN ]]; then
        if (( ${+commands[gh]} )) && gh auth token > /dev/null 2>&1; then
            export MISE_GITHUB_TOKEN=$(gh auth token 2>/dev/null)
        fi
    fi
    if [[ -z $MISE_GITHUB_TOKEN && -z $GITHUB_TOKEN ]]; then
        print "  ...no GitHub token found; mise may hit API rate limits"
        print "     (export GITHUB_TOKEN, or run 'gh auth login')"
    fi

    # `mise upgrade` bumps tools within their pinned major and PRUNES the old
    # install dir. Anything resolving through a mise shim follows along;
    # anything holding an absolute path into the old prefix does not. openclaw
    # is the one npm global deliberately excluded from .default-npm-packages
    # (it was the beta->stable downgrade vector — see that file), so
    # 70_runtime_installs.zsh does not reinstall it into the new prefix either.
    # Its install/repair is owned solely by the ExecStartPre guard on
    # openclaw-gateway.service (~/repos/hart/scripts/openclaw-ensure-beta.sh).
    #
    # 2026-08-29 21:57: node 24.19.0 -> 24.20.0 landed exactly this way. The npm
    # global went with the pruned prefix, the `openclaw` shim died, every Claude
    # session's stdio MCP failed with CONNECTION_CLOSED, and the live gateway
    # was left executing a DELETED inode — one restart from a permanent
    # crashloop. Nothing restarted the service, so the guard that would have
    # repaired it never got the chance to run.
    #
    # So: if the node prefix actually moved, poke the gateway. try-restart is a
    # no-op when the unit is not running, the guard then reinstalls
    # openclaw@beta into the new prefix, and the service comes back on a live
    # inode. Gated on the unit file existing, so this is ceres-only in practice
    # and silent everywhere else.
    local node_prefix_before node_prefix_after
    node_prefix_before=$(mise where node 2>/dev/null)

    print "Installing mise tools (node, bun, python, etc.)..."
    run_mise_step "mise install" 30 mise install

    print "Upgrading mise tools..."
    run_mise_step "mise upgrade" 20 mise upgrade --yes

    node_prefix_after=$(mise where node 2>/dev/null)
    if [[ -n $node_prefix_after && $node_prefix_after != $node_prefix_before ]]; then
        print "  ...node prefix moved (${node_prefix_before:-none} -> $node_prefix_after)"
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would try-restart openclaw-gateway.service onto the new prefix"
        elif [[ -f $XDG_CONFIG_HOME/systemd/user/openclaw-gateway.service ]] && (( ${+commands[systemctl]} )); then
            # A post-merge hook shell may have no D-Bus session env, so reaching
            # the user bus can legitimately fail. Never fail the deploy for it —
            # report and move on; the 5-min drift detector is the backstop.
            if systemctl --user try-restart openclaw-gateway.service 2>/dev/null; then
                print "  ...restarted openclaw-gateway onto the new node prefix"
            else
                print "  ...could not restart openclaw-gateway (no user bus?); do it manually"
            fi
        fi
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
