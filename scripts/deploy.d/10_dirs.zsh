# Create XDG directory tree + link .zshenv if needed.

if [[ $DOTFILES_OS == Darwin ]]; then
    ensure_homebrew_path || true
fi

print "Creating required directory tree..."
zf_mkdir -p $XDG_CONFIG_HOME/{ghostty,cmux,git/local,htop,ranger,gem,tig,gnupg,nvim/{plugin,after},yazi,bat}
zf_mkdir -p $XDG_CACHE_HOME/{zsh,tig}
zf_mkdir -p $XDG_DATA_HOME/{{goenv,jenv,luaenv,nodenv,phpenv,plenv,pyenv}/plugins,zsh,man/man1,nvim/site/pack/plugins}
zf_mkdir -p $XDG_CONFIG_HOME/{mise,systemd/user,opencode,agent-orchestrator,aerospace,sway}
zf_mkdir -p $HOME/{.claude,.codex,.codewhale,.ssh,.agent-orchestrator,.worktrees,.gjc/agent}
zf_mkdir -p $XDG_STATE_HOME
zf_mkdir -p $HOME/.local/{bin,etc}
zf_chmod 700 $XDG_CONFIG_HOME/gnupg
zf_chmod 700 $HOME/.ssh
# ControlMaster multiplexed-connection sockets (ssh/config ControlPath). OpenSSH
# will NOT create this dir itself; absent it, every connection silently falls
# back to a fresh (unshared) connection.
zf_mkdir -p $HOME/.ssh/sockets
zf_chmod 700 $HOME/.ssh/sockets
print "  ...done"

print "Checking for ZDOTDIR env variable..."
if [[ $ZDOTDIR == $SCRIPT_DIR/zsh ]]; then
    print "  ...present and valid, skipping .zshenv symlink"
else
    print "  ...failed to match this script dir. ZDOTDIR is \"$ZDOTDIR\", which doesn't match expected value \"$SCRIPT_DIR/zsh\". Symlinking .zshenv"
    zf_ln -sfn $SCRIPT_DIR/zsh/.zshenv ${ZDOTDIR:-$HOME}/.zshenv
fi
