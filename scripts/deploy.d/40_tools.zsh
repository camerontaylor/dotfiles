# Build-and-install submoduled tools: git-extras, git-quick-stats, fzf,
# diff-so-fancy, wtp, moor. plus gh-prreview extension when gh is present.

if (( ${+commands[make]} )); then
    print "Installing git-extras..."
    pushd tools/git-extras
    PREFIX=$HOME/.local make install > /dev/null
    popd
    print "  ...done"

    if (( ${+commands[which]} )); then
        print "Installing git-quick-stats..."
        pushd tools/git-quick-stats
        PREFIX=$HOME/.local make install > /dev/null
        popd
        print "  ...done"
    fi
fi

print "Installing fzf..."
pushd tools/fzf
if fzf_install_output=$(./install --bin); then
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/bin/fzf $HOME/.local/bin/fzf
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/bin/fzf-tmux $HOME/.local/bin/fzf-tmux
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/man/man1/fzf.1 $XDG_DATA_HOME/man/man1/fzf.1
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/man/man1/fzf-tmux.1 $XDG_DATA_HOME/man/man1/fzf-tmux.1
    print "  ...done"
else
    print $fzf_install_output
    print "  ...error detected, ignoring, please check the fzf installation guide"
fi
popd

if (( ${+commands[perl]} )); then
    print "Installing diff-so-fancy..."
    zf_ln -sfn $SCRIPT_DIR/tools/diff-so-fancy/diff-so-fancy $HOME/.local/bin/diff-so-fancy
    print "  ...done"
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
