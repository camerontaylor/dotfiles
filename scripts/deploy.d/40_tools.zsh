# Install non-mise CLI tools. The former tools/ submodules now come from mise
# (fzf via aqua, pnpm-shell-completion via github) or are vendored under
# tools/vendor/ (httpstat, spark, spectre-meltdown-checker, git-quick-stats).
# This fragment: (1) symlinks vendored scripts that must live on PATH, (2)
# best-effort installs the two tools that need a package manager (git-extras,
# testssl), then (3) runs the pre-existing wtp / gh-prreview / moor setup.

# git-quick-stats must be on PATH so `git quick-stats` subcommand dispatch finds
# it. httpstat/spark/spectre are reached via aliases in zsh/rc.d, so they need no
# symlink. Vendored scripts have no build step and behave identically on both OSes.
zf_ln -sfn $SCRIPT_DIR/tools/vendor/git-quick-stats $HOME/.local/bin/git-quick-stats

# git-extras (80+ git subcommands + completion) and testssl (TLS scanner) have no
# mise/aqua backend and are pure-shell, so they come from the system package
# manager. The package layout differs per platform:
#   macOS            : brew    — git-extras, testssl       (binary is `testssl`)
#   Debian/Ubuntu    : apt     — git-extras, testssl.sh    (both in the archive)
#   Arch-family      : testssl.sh from the official repo (pacman); git-extras is
#                      AUR-only, so it needs an AUR helper (paru/yay) — pacman
#                      can't fetch it. (29_testssl.zsh aliases testssl=testssl.sh.)
# sudo / AUR helpers can prompt for a password; the post-merge/post-checkout git
# hook has no TTY to answer it, so a Linux install is only attempted when sudo is
# already passwordless/cached or stdin is a terminal (interactive `./deploy.zsh`).
# Otherwise we print a copy-paste hint instead of hanging — same guard as
# 75_brew_setup.zsh's htop, honouring the no-sudo-in-hook rule.
if [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[brew]} )); then
    for formula in git-extras testssl; do
        brew list --formula $formula > /dev/null 2>&1 && continue
        print "Installing $formula via brew..."
        if brew install $formula > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed, install manually: brew install $formula"
        fi
    done
elif [[ $DOTFILES_OS == Linux ]]; then
    # os-release is designed to be sourced; do it in a subshell so its vars don't
    # leak. Absent file / missing keys => empty, which falls through to "unknown".
    local distro_id="" distro_like=""
    if [[ -r /etc/os-release ]]; then
        distro_id=$(. /etc/os-release 2>/dev/null && print -r -- "${ID:-}")
        distro_like=$(. /etc/os-release 2>/dev/null && print -r -- "${ID_LIKE:-}")
    fi

    # Build a list of "<probe names>|<install command>" for the missing tools on
    # this distro. <probe names> is a space-separated set of command names whose
    # presence means "already installed" (skip). An empty command means "no known
    # automatic recipe here" -> hint only.
    local -a recipes=()
    case " $distro_id $distro_like " in
        *" debian "*|*" ubuntu "*)
            if (( ${+commands[apt-get]} )); then
                recipes+=( "git-extras|sudo apt-get install -y git-extras" )
                recipes+=( "testssl testssl.sh|sudo apt-get install -y testssl.sh" )
            fi
            ;;
        *" arch "*)
            # testssl.sh: official repo -> pacman (-Sy refreshes a stale db so it
            # doesn't 404; --needed makes it idempotent). See 41_net_tools.zsh for
            # the partial-upgrade caveat of -Sy without -u.
            (( ${+commands[pacman]} )) \
                && recipes+=( "testssl testssl.sh|sudo pacman -Sy --needed --noconfirm testssl.sh" )
            # git-extras: AUR -> first available helper (run WITHOUT a sudo prefix;
            # helpers call sudo internally and refuse to run as root).
            local aur=""
            (( ${+commands[paru]} )) && aur=paru
            [[ -z $aur ]] && (( ${+commands[yay]} )) && aur=yay
            if [[ -n $aur ]]; then
                recipes+=( "git-extras|$aur -S --needed --noconfirm git-extras" )
            else
                recipes+=( "git-extras|" )   # no AUR helper -> hint only
            fi
            ;;
    esac

    if (( ${#recipes} == 0 )); then
        # Unknown distro or no package manager detected — hint with the generic names.
        (( ${+commands[git-extras]} )) \
            || print "  hint: git-extras not installed — install via your package manager"
        (( ${+commands[testssl]} )) || (( ${+commands[testssl.sh]} )) \
            || print "  hint: testssl not installed — install via your package manager"
    else
        local recipe probe_str cmd label present p
        for recipe in $recipes; do
            probe_str=${recipe%%|*}
            cmd=${recipe#*|}
            label=${probe_str%% *}        # first probe name = display label
            present=0
            for p in ${=probe_str}; do
                (( ${+commands[$p]} )) && { present=1; break }
            done
            (( present )) && continue
            if [[ -z $cmd ]]; then
                print "  hint: $label not installed (AUR only) — e.g. paru -S $label"
            elif (( DEPLOY_DRY_RUN )); then
                print "  [dry-run] would: $cmd"
            elif sudo -n true 2>/dev/null || [[ -t 0 ]]; then
                print "Installing $label..."
                if eval "$cmd" > /dev/null 2>&1; then
                    rehash
                    print "  ...done"
                else
                    print "  ...failed, install manually: $cmd"
                fi
            else
                print "  hint: $label not installed — run: $cmd"
            fi
        done
    fi
fi

if (( ! ${+commands[wtp]} )); then
    $SCRIPT_DIR/scripts/install-wtp.zsh || true
fi

if (( ${+commands[gh]} )); then
    gh extension list 2>/dev/null | grep -q chmouel/gh-prreview \
        || gh extension install chmouel/gh-prreview 2>/dev/null \
        || true
fi

if (( ! ${+commands[moor]} )); then
    print "Installing moor..."
    if bash $SCRIPT_DIR/scripts/install-moor.sh > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install moor, skipping"
    fi
fi
