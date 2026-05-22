# curl-based installs for runtimes/CLIs without a mise backend:
# Claude Code, vite-plus, rustup/cargo, linear-cli.

if (( ! ${+commands[claude]} )); then
    print "Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install Claude Code"
    fi
fi

if (( ! ${+commands[vp]} )); then
    print "Installing vite-plus..."
    if curl -fsSL https://vite.plus | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install vite-plus"
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
