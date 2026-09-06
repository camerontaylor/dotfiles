# Create XDG directory tree + link .zshenv if needed.

if [[ $DOTFILES_OS == Darwin ]]; then
    ensure_homebrew_path || true
fi

printf '%s\n' "Creating required directory tree..."
deploy_mkdir -p $XDG_CONFIG_HOME/{ghostty,cmux,git/local,btop,htop,ranger,gem,tig,gnupg,nvim/{plugin,after},yazi,bat}
deploy_mkdir -p $XDG_CACHE_HOME/{zsh,tig}
deploy_mkdir -p $XDG_DATA_HOME/{{goenv,jenv,luaenv,nodenv,phpenv,plenv,pyenv}/plugins,zsh,man/man1,nvim/site/pack/plugins}
deploy_mkdir -p $XDG_CONFIG_HOME/{mise,systemd/user,opencode,agent-orchestrator,aerospace,sway}
deploy_mkdir -p $HOME/{.claude,.codex,.codewhale,.ssh,.agent-orchestrator,.worktrees,.gjc/agent}
deploy_mkdir -p $XDG_STATE_HOME
deploy_mkdir -p $HOME/.local/{bin,etc}
deploy_chmod 700 $XDG_CONFIG_HOME/gnupg
deploy_chmod 700 $HOME/.ssh
# ControlMaster multiplexed-connection sockets (ssh/config ControlPath). OpenSSH
# will NOT create this dir itself; absent it, every connection silently falls
# back to a fresh (unshared) connection.
deploy_mkdir -p $HOME/.ssh/sockets
deploy_chmod 700 $HOME/.ssh/sockets
printf '%s\n' "  ...done"

printf '%s\n' "Checking the ~/.zshenv entry point..."
# The whole zsh config keys off $HOME/.zshenv: zsh/.zshenv walks that symlink
# to derive ZDOTDIR, then sources env.d/ (secrets loader included). So the
# entry point that must exist is $HOME/.zshenv -> $SCRIPT_DIR/zsh/.zshenv, and
# the destination is ALWAYS $HOME/.zshenv.
#
# It must NOT be ${ZDOTDIR}/.zshenv. When ZDOTDIR carries the symlinked
# spelling (~/.local/dotfiles/zsh) rather than the resolved repo path, that
# path resolves back into this repo, and `ln -sfn src ${ZDOTDIR}/.zshenv`
# links the source file onto its own inode — a self-referential symlink that
# leaves every new shell with no zshenv, so nothing in env.d (secrets, PATH,
# aliases) loads. Observed 2026-09-03 after the secrets split; it silently
# broke Z_AI_API_KEY and every cc* alias until this was corrected.
#
# Compare resolved paths (abspath) so a correct-but-symlinked ZDOTDIR does not
# trigger a needless relink; write to $HOME, which can never be the source's
# own inode, so a self-link is structurally impossible.
_zshenv_want=$(abspath $SCRIPT_DIR/zsh/.zshenv 2>/dev/null)
_zshenv_have=$(abspath $HOME/.zshenv 2>/dev/null)
if [[ -n $_zshenv_want && $_zshenv_have == $_zshenv_want ]]; then
    printf '%s\n' "  ...~/.zshenv already resolves here, skipping symlink"
else
    printf '%s\n' "  ...linking ~/.zshenv -> $(tilde_collapse $SCRIPT_DIR/zsh/.zshenv)"
    deploy_ln -sfn $SCRIPT_DIR/zsh/.zshenv $HOME/.zshenv
fi
unset _zshenv_want _zshenv_have
