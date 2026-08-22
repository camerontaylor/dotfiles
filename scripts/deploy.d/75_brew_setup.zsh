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

# Trust the specific non-official tap formulae/casks this script installs before
# any `brew install`/`brew list` touches them. Without this, a brew with
# HOMEBREW_REQUIRE_TAP_TRUST set silently ignores these taps and every install
# below would no-op. Trust the exact items, not the whole taps (see brew_trust).
# wtp (satococoa/tap) is trusted in scripts/install-wtp.zsh, which runs earlier.
if (( ${+commands[brew]} )); then
    brew_trust --formula gentleman-programming/tap/engram
    brew_trust --formula felixkratz/formulae/borders
    brew_trust --cask nikitabobko/tap/aerospace
    brew_trust --cask manaflow-ai/cmux/cmux
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

# Modern bash via brew. macOS ships bash 3.2.57 (frozen at the last GPLv2
# release); installing 5.x unlocks associative arrays, `mapfile`,
# `${var^^}`, `**` globstar, etc. for any script that uses
# `#!/usr/bin/env bash` (or `bash some-script.sh` typed interactively,
# which goes through the brew-first PATH). Not registered in /etc/shells —
# zsh remains the login shell.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing modern bash via brew..."
    brew_formula_install_or_upgrade bash || true
fi

# ncurses for Ghostty terminfo compilation.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing ncurses via brew..."
    brew_formula_install_or_upgrade ncurses || true
fi

# htop process viewer; config is symlinked by 20_symlinks.zsh. There is no
# mise/aqua backend for htop, so it comes from the platform package manager:
# brew on macOS (refreshed every run), pacman on Arch-family Linux.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing htop via brew..."
    brew_formula_install_or_upgrade htop || true
elif (( ${+commands[pacman]} )) && (( ! ${+commands[htop]} )); then
    # sudo can prompt for a password. In a non-interactive deploy (e.g. the
    # post-merge git hook) there's no TTY to answer it, so only attempt the
    # install when sudo is already passwordless/cached or stdin is a terminal;
    # otherwise leave a copy-paste hint instead of hanging on the prompt.
    if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
        print "Installing htop via pacman..."
        if sudo pacman -S --needed --noconfirm htop > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install htop via pacman"
        fi
    else
        print "htop missing; install it with: sudo pacman -S --needed htop"
    fi
fi

# mosh — UDP-based remote shell that survives roaming/sleep; used for
# connections across the home cluster. No mise/aqua backend, so it comes from
# the platform package manager: brew on macOS, apt on Debian/Ubuntu, pacman on
# Arch-family Linux. Mirrors htop's per-OS fanout above.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing mosh via brew..."
    brew_formula_install_or_upgrade mosh || true
elif (( ${+commands[apt-get]} )) && (( ! ${+commands[mosh]} )); then
    if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
        print "Installing mosh via apt..."
        if sudo apt-get install -y mosh > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install mosh via apt"
        fi
    else
        print "mosh missing; install it with: sudo apt-get install -y mosh"
    fi
elif (( ${+commands[pacman]} )) && (( ! ${+commands[mosh]} )); then
    if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
        print "Installing mosh via pacman..."
        if sudo pacman -S --needed --noconfirm mosh > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install mosh via pacman"
        fi
    else
        print "mosh missing; install it with: sudo pacman -S --needed mosh"
    fi
fi

# GNU userland on macOS. The g-prefixed binaries (grm, gdf, gdu, ggrep, gdiff,
# gsed, gtar, gawk, gfind, gxargs) are referenced directly by the gnu_alias
# helper in zsh/rc.d/08_aliases.zsh; the un-prefixed names are picked up via
# the gnubin PATH prepend in zsh/env.d/03_paths.zsh. gnu-getopt is keg-only
# (would shadow /usr/bin/getopt), so it's symlinked through a dedicated
# branch in 03_paths.zsh rather than the gnubin loop.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing GNU userland via brew..."
    brew_formula_install_or_upgrade coreutils || true
    brew_formula_install_or_upgrade grep || true
    brew_formula_install_or_upgrade diffutils || true
    brew_formula_install_or_upgrade gnu-sed || true
    brew_formula_install_or_upgrade gnu-tar || true
    brew_formula_install_or_upgrade gawk || true
    brew_formula_install_or_upgrade findutils || true
    brew_formula_install_or_upgrade gnu-getopt || true
fi

# Linux-script compat helpers that aren't part of GNU coreutils but ship as
# standard tooling on most Linux distros and bite ported scripts when missing:
#   moreutils  — `sponge` (in-place pipeline rewrites), `ts`, `chronic`, `vipe`
#   flock      — macOS has no flock(1) at all; many cron/lock scripts depend on it
#
# Not installed:
#   bash-completion@2 — zsh is the daily driver and ~/.bashrc is unmanaged,
#     so the completion files would just sit on disk inert.
#   zsh-completions (brew formula) — redundant; zsh/plugins/completions is the
#     same zsh-users/zsh-completions repo vendored as a submodule and already
#     wired into fpath by zsh/rc.d/15_completion.zsh:19.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing Linux-script compat helpers via brew..."
    brew_formula_install_or_upgrade moreutils || true
    brew_formula_install_or_upgrade flock || true
    # macOS ships openrsync (rsync 2.6.9 compat, protocol 29) which rejects
    # common GNU rsync flags like --info=progress2 and behaves differently on
    # --exclude patterns. Install brew's rsync 3.x to get parity with Linux.
    brew_formula_install_or_upgrade rsync || true
fi

# PostgreSQL client tools. Homebrew's libpq formula provides psql without
# installing or starting a local PostgreSQL server.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing PostgreSQL client tools via brew..."
    brew_formula_install_or_upgrade libpq || true
    if [[ -d $HOMEBREW_PREFIX/opt/libpq/bin ]]; then
        path=($HOMEBREW_PREFIX/opt/libpq/bin $path)
        rehash
    fi
fi

# fd / git-delta: upstream releases dropped x86_64-apple-darwin, so we can't get
# them through mise on Intel Macs. brew bottles ship for both arches.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing fd via brew..."
    brew_install_or_upgrade fd fd || true
    print "Installing git-delta via brew..."
    brew_install_or_upgrade git-delta delta || true
    print "Installing age via brew..."
    brew_install_or_upgrade age age || true
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

# ghx (GitHub CLI caching layer) retired 2026-08: gh is mise-managed again
# (configs/mise.toml). Drift-correct hosts that still carry the brew install:
# the formula linked gh (shim) + ghx + ghxd, and the deploy kept a brew gh
# installed-but-unlinked as ghx's real binary — remove all of it plus ~/.ghx
# (cache + auto-managed gh) so mise's gh owns the command again. Brew-less
# hosts get the equivalent cleanup in 70_runtime_installs.zsh.
if (( ${+commands[brew]} )) && brew list --formula ghx > /dev/null 2>&1; then
    print "Removing ghx (gh is mise-managed again)..."
    # ghxd self-daemonizes (reparents to PID 1) and ignores SIGTERM; KILL it.
    pkill -9 -u "$USER" -x ghxd 2>/dev/null || true
    brew uninstall brunoborges/tap/ghx > /dev/null 2>&1 || true
    brew uninstall gh > /dev/null 2>&1 || true
    brew untap brunoborges/tap > /dev/null 2>&1 || true
    rm -rf "$HOME/.ghx"
    rehash
    print "  ...done"
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

# cmux cask — Ghostty-based terminal wrapper with vertical tabs / agent notifications.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask cmux > /dev/null 2>&1; then
        print "Installing cmux..."
        brew_cask_install_or_upgrade cmux || true
    elif $upgrade_mode; then
        print "Upgrading cmux..."
        brew_cask_install_or_upgrade cmux || true
    fi
fi

# Raycast cask — launcher / keystroke productivity tool.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask raycast > /dev/null 2>&1; then
        print "Installing Raycast..."
        brew_cask_install_or_upgrade raycast || true
    elif $upgrade_mode; then
        print "Upgrading Raycast..."
        brew_cask_install_or_upgrade raycast || true
    fi
fi

# T3 Code cask — desktop web GUI for coding agents (Codex/Claude/OpenCode).
# The `t3` CLI (server form, port 3773) is installed cross-platform through
# .default-npm-packages and exposed over the mesh by setup-caddy.sh; this cask
# is the macOS desktop companion app.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask t3-code > /dev/null 2>&1; then
        print "Installing T3 Code..."
        brew_cask_install_or_upgrade t3-code || true
    elif $upgrade_mode; then
        print "Upgrading T3 Code..."
        brew_cask_install_or_upgrade t3-code || true
    fi
fi

# Paseo cask — self-hosted orchestrator for Claude Code / Codex / Copilot /
# OpenCode / Pi agents, reachable from the phone over Tailscale. The cask ships
# BOTH the Electron app and its own `paseo` CLI (symlinked into the brew
# prefix), version-locked to each other — which is why @getpaseo/cli is
# deliberately NOT in .default-npm-packages: two `paseo` binaries drifting apart
# on one PATH is the Vite+ split-brain all over again (see 70_runtime_installs).
# ceres, headless and without a cask, gets the CLI as a mise tool instead.
# Per-host daemon config (bind address, password, web UI) is applied by
# scripts/setup-paseo.sh — one-shot, not part of deploy. See docs/paseo.md.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask paseo > /dev/null 2>&1; then
        print "Installing Paseo..."
        brew_cask_install_or_upgrade paseo || true
    elif $upgrade_mode; then
        print "Upgrading Paseo..."
        brew_cask_install_or_upgrade paseo || true
    fi
fi

# AeroSpace cask — i3-like tiling window manager for macOS. Lives in the
# maintainer's own tap (nikitabobko/tap), so the tap-qualified name is used for
# both the `brew list` presence check and the install/upgrade.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask nikitabobko/tap/aerospace > /dev/null 2>&1; then
        print "Installing AeroSpace..."
        brew_cask_install_or_upgrade nikitabobko/tap/aerospace || true
    elif $upgrade_mode; then
        print "Upgrading AeroSpace..."
        brew_cask_install_or_upgrade nikitabobko/tap/aerospace || true
    fi
fi

# Karabiner-Elements cask — keyboard customizer / key remapper for macOS.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask karabiner-elements > /dev/null 2>&1; then
        print "Installing Karabiner-Elements..."
        brew_cask_install_or_upgrade karabiner-elements || true
    elif $upgrade_mode; then
        print "Upgrading Karabiner-Elements..."
        brew_cask_install_or_upgrade karabiner-elements || true
    fi
fi

# JankyBorders (borders) — optional focus-ring/window-border overlay that pairs
# with AeroSpace (a tiling WM has no titlebars, so a colored border marks the
# focused window). Formula in the maintainer's tap (felixkratz/formulae), so the
# tap-qualified name is used for both the presence check and install/upgrade.
# It runs as a per-user LaunchAgent via `brew services`; start it once installed
# (idempotent — a no-op if already loaded). `brew services` needs the formula
# present, so only attempt the start when the install above succeeded.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing JankyBorders..."
    brew_formula_install_or_upgrade felixkratz/formulae/borders || true
    if brew list --formula felixkratz/formulae/borders > /dev/null 2>&1; then
        if brew services list 2>/dev/null | grep -qE '^borders[[:space:]]+(started|running)'; then
            print "  ...borders service already running"
        elif brew services start felixkratz/formulae/borders > /dev/null 2>&1; then
            print "  ...borders service started"
        else
            print "  ...failed to start borders service"
        fi
    fi
fi

# duti — sets default applications for file types / UTIs from the CLI. Consumed
# by scripts/macos/macos-defaults.sh (77_macos_defaults.zsh) to point text/code
# file types at VS Code. Plain formula in homebrew-core.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing duti..."
    brew_formula_install_or_upgrade duti || true
fi

# pinentry-mac — native macOS dialog for gpg-agent passphrase prompts. Without
# it, brew gnupg's default pinentry is the curses one, which paints its prompt
# INTO whatever TTY gpg-agent last saw — so background SSH/GPG operations (e.g.
# the nightly dotfiles.pull LaunchAgent pulling over git+ssh) ambush an
# unrelated terminal's UI. The generated gpg-agent.conf (20_symlinks.zsh)
# routes pinentry through scripts/pinentry-auto, which prefers this when
# present. gnupg itself is not deploy-managed; the wrapper degrades gracefully
# if either half is missing.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    print "Installing pinentry-mac..."
    brew_formula_install_or_upgrade pinentry-mac || true
fi

# ForkLift cask — dual-pane macOS file manager / FTP-SFTP client.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    if ! brew list --cask forklift > /dev/null 2>&1; then
        print "Installing ForkLift..."
        brew_cask_install_or_upgrade forklift || true
    elif $upgrade_mode; then
        print "Upgrading ForkLift..."
        brew_cask_install_or_upgrade forklift || true
    fi
fi
