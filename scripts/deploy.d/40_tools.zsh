# Install non-mise CLI tools. The former tools/ submodules now come from mise
# (fzf via aqua, pnpm-shell-completion via github) or are vendored under
# tools/vendor/ (httpstat, spark, spectre-meltdown-checker, git-quick-stats).
# This fragment: (1) symlinks vendored scripts that must live on PATH, (2)
# best-effort installs tools that need a package manager (git-extras,
# git-restore-mtime, testssl), then (3) runs the pre-existing wtp /
# gh-prreview / moor setup.

# git-quick-stats must be on PATH so `git quick-stats` subcommand dispatch finds
# it. httpstat/spark/spectre are reached via aliases in zsh/rc.d, so they need no
# symlink. Vendored scripts have no build step and behave identically on both OSes.
zf_ln -sfn $SCRIPT_DIR/tools/vendor/git-quick-stats $HOME/.local/bin/git-quick-stats

# git-extras (80+ git subcommands + completion), git-restore-mtime, and testssl
# (TLS scanner) have no mise/aqua backend, so they come from the system package
# manager. The package layout differs per platform:
#   macOS            : brew    — git-extras, git-tools, testssl
#                                (git-tools provides git-restore-mtime)
#   Debian/Ubuntu    : apt     — git-extras, git-restore-mtime, testssl.sh
#   Arch-family      : testssl.sh from the official repo (pacman); git-extras and
#                      git-tools are AUR-only, so they need an AUR helper
#                      (paru/yay) — pacman can't fetch them.
#                      (29_testssl.zsh aliases testssl=testssl.sh.)
# sudo / AUR helpers can prompt for a password; the post-merge/post-checkout git
# hook has no TTY to answer it, so a Linux install is only attempted when sudo is
# already passwordless/cached or stdin is a terminal (interactive `./deploy.zsh`).
# Otherwise we print a copy-paste hint instead of hanging — same guard as
# 75_brew_setup.zsh's htop, honouring the no-sudo-in-hook rule.
if [[ $DOTFILES_OS == Darwin ]] && have brew; then
    local brew_tool formula bin_name
    for brew_tool in git-extras:git-extras git-tools:git-restore-mtime testssl:testssl; do
        formula=${brew_tool%%:*}
        bin_name=${brew_tool#*:}
        brew list --formula $formula > /dev/null 2>&1 && continue
        have "$bin_name" && continue
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
            if have apt-get; then
                recipes+=( "git-extras|sudo apt-get install -y git-extras" )
                recipes+=( "git-restore-mtime|sudo apt-get install -y git-restore-mtime" )
                recipes+=( "testssl testssl.sh|sudo apt-get install -y testssl.sh" )
            fi
            ;;
        *" arch "*)
            # testssl.sh: official repo -> pacman (-Sy refreshes a stale db so it
            # doesn't 404; --needed makes it idempotent). See 41_net_tools.zsh for
            # the partial-upgrade caveat of -Sy without -u.
            have pacman \
                && recipes+=( "testssl testssl.sh|sudo pacman -Sy --needed --noconfirm testssl.sh" )
            # git-extras: AUR -> first available helper (run WITHOUT a sudo prefix;
            # helpers call sudo internally and refuse to run as root).
            local aur=""
            have paru && aur=paru
            [[ -z $aur ]] && have yay && aur=yay
            if [[ -n $aur ]]; then
                recipes+=( "git-extras|$aur -S --needed --noconfirm git-extras" )
                recipes+=( "git-restore-mtime|$aur -S --needed --noconfirm git-tools" )
            else
                recipes+=( "git-extras|" )   # no AUR helper -> hint only
                recipes+=( "git-restore-mtime|" )
            fi
            ;;
    esac

    if (( ${#recipes} == 0 )); then
        # Unknown distro or no package manager detected — hint with the generic names.
        have git-extras \
            || print "  hint: git-extras not installed — install via your package manager"
        have git-restore-mtime \
            || print "  hint: git-restore-mtime not installed — install git-tools/git-restore-mtime via your package manager"
        have testssl || have testssl.sh \
            || print "  hint: testssl not installed — install via your package manager"
    else
        local recipe probe_str cmd label present p
        for recipe in $recipes; do
            probe_str=${recipe%%|*}
            cmd=${recipe#*|}
            label=${probe_str%% *}        # first probe name = display label
            present=0
            for p in ${=probe_str}; do
                have "$p" && { present=1; break }
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

if ! have wtp; then
    $SCRIPT_DIR/scripts/install-wtp.zsh || true
fi

if have gh; then
    gh extension list 2>/dev/null | grep -q chmouel/gh-prreview \
        || gh extension install chmouel/gh-prreview 2>/dev/null \
        || true
fi

if ! have moor; then
    print "Installing moor..."
    if bash $SCRIPT_DIR/scripts/install-moor.sh > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install moor, skipping"
    fi
fi
