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
# manager. brew on macOS (no sudo, safe from a git hook); on Linux we only detect
# and hint, because auto-`sudo` from a post-merge/post-checkout hook would hang.
if [[ $(uname -s) == Darwin ]] && (( ${+commands[brew]} )); then
    for formula in git-extras testssl; do
        brew list --formula $formula > /dev/null 2>&1 && continue
        print "Installing $formula via brew..."
        if brew install $formula > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed, install manually: brew install $formula"
        fi
    done
else
    (( ${+commands[git-extras]} )) \
        || print "  hint: git-extras not installed (e.g. paru -S git-extras)"
    (( ${+commands[testssl]} )) || (( ${+commands[testssl.sh]} )) \
        || print "  hint: testssl not installed (e.g. sudo pacman -S testssl.sh)"
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
