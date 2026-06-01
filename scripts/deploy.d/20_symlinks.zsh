# Symlink every dotfile/config into its XDG home.

print "Linking config files..."
zf_ln -sfn $SCRIPT_DIR/configs/bat/config $XDG_CONFIG_HOME/bat/config
zf_ln -sfn $SCRIPT_DIR/nvim/init.lua $XDG_CONFIG_HOME/nvim/init.lua
zf_ln -sfn $SCRIPT_DIR/nvim/init $XDG_CONFIG_HOME/nvim/plugin/init
zf_ln -sfn $SCRIPT_DIR/nvim/lsp $XDG_CONFIG_HOME/nvim/after/lsp
zf_ln -sfn $SCRIPT_DIR/nvim/ftplugin $XDG_CONFIG_HOME/nvim/ftplugin
zf_ln -sfn $SCRIPT_DIR/nvim/plugins $XDG_DATA_HOME/nvim/site/pack/plugins/start
zf_ln -sfn $SCRIPT_DIR/tmux $XDG_CONFIG_HOME/tmux
zf_ln -sfn $SCRIPT_DIR/configs/ghostty $XDG_CONFIG_HOME/ghostty/config
zf_ln -sfn $SCRIPT_DIR/configs/gitconfig $XDG_CONFIG_HOME/git/config
zf_ln -sfn $SCRIPT_DIR/configs/gitattributes $XDG_CONFIG_HOME/git/attributes
zf_ln -sfn $SCRIPT_DIR/configs/gitignore $XDG_CONFIG_HOME/git/ignore
zf_ln -sfn $SCRIPT_DIR/configs/tigrc $XDG_CONFIG_HOME/tig/config
zf_ln -sfn $SCRIPT_DIR/configs/htoprc $XDG_CONFIG_HOME/htop/htoprc
zf_ln -sfn $SCRIPT_DIR/configs/ranger $XDG_CONFIG_HOME/ranger/rc.conf
zf_ln -sfn $SCRIPT_DIR/configs/gemrc $XDG_CONFIG_HOME/gem/gemrc
zf_ln -sfn $SCRIPT_DIR/configs/ranger-plugins $XDG_CONFIG_HOME/ranger/plugins
zf_ln -sfn $SCRIPT_DIR/configs/starship.toml $XDG_CONFIG_HOME/starship.toml
zf_ln -sfn $SCRIPT_DIR/configs/mise.toml $XDG_CONFIG_HOME/mise/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $XDG_CONFIG_HOME/agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $HOME/.agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $HOME/.agent-orchestrator.yaml
zf_mkdir -p $XDG_CONFIG_HOME/waveterm
zf_ln -sfn $SCRIPT_DIR/configs/waveterm/settings.json $XDG_CONFIG_HOME/waveterm/settings.json
zf_mkdir -p $XDG_CONFIG_HOME/gtk-3.0
zf_ln -sfn $SCRIPT_DIR/configs/gtk-3.0-bookmarks $XDG_CONFIG_HOME/gtk-3.0/bookmarks
zf_ln -sfn $SCRIPT_DIR/yazi/init.lua $XDG_CONFIG_HOME/yazi/init.lua
zf_ln -sfn $SCRIPT_DIR/yazi/keymap.toml $XDG_CONFIG_HOME/yazi/keymap.toml
zf_ln -sfn $SCRIPT_DIR/yazi/theme.toml $XDG_CONFIG_HOME/yazi/theme.toml
zf_ln -sfn $SCRIPT_DIR/yazi/yazi.toml $XDG_CONFIG_HOME/yazi/yazi.toml
zf_ln -sfn $SCRIPT_DIR/yazi/plugins $XDG_CONFIG_HOME/yazi/plugins
zf_ln -sfn $SCRIPT_DIR/gpg/gpg.conf $XDG_CONFIG_HOME/gnupg/gpg.conf
zf_ln -sfn $SCRIPT_DIR/gpg/gpg-agent.conf $XDG_CONFIG_HOME/gnupg/gpg-agent.conf
zf_ln -sfn $SCRIPT_DIR/tools/git-diff-pager $HOME/.local/bin/git-diff-pager
zf_ln -sfn $SCRIPT_DIR/scripts/commit-conventional $HOME/.local/bin/commit-conventional
zf_ln -sfn $SCRIPT_DIR/scripts/generate-commit-msg $HOME/.local/bin/generate-commit-msg
# Claude Code + OMC
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/CLAUDE.md $HOME/.claude/CLAUDE.md
# RTK was nuked. Actively remove any stale link left by prior deploys so the
# removal propagates to every machine on its next deploy (idempotent no-op once gone).
if [[ -L $HOME/.claude/RTK.md || -e $HOME/.claude/RTK.md ]]; then
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] rm -f $HOME/.claude/RTK.md (stale RTK link)"
    else
        rm -f $HOME/.claude/RTK.md && print "  removed stale ~/.claude/RTK.md"
    fi
fi
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/settings.json $HOME/.claude/settings.json
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/settings.local.json $HOME/.claude/settings.local.json
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/statusline-command.sh $HOME/.claude/statusline-command.sh
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/hooks $HOME/.claude/hooks
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/hud $HOME/.claude/hud
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/skills $HOME/.claude/skills
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/commands $HOME/.claude/commands
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/mcp.json $HOME/.claude/.mcp.json
zf_ln -sfn $SCRIPT_DIR/configs/ai/claude-code/omc-config.json $HOME/.claude/.omc-config.json
# Codex CLI + OMX
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/config.toml $HOME/.codex/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/AGENTS.md $HOME/.codex/AGENTS.md
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/agents $HOME/.codex/agents
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/prompts $HOME/.codex/prompts
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/rules $HOME/.codex/rules
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/skills $HOME/.codex/skills
# OpenCode
zf_ln -sfn $SCRIPT_DIR/configs/ai/opencode/opencode.json $XDG_CONFIG_HOME/opencode/opencode.json
zf_ln -sfn $SCRIPT_DIR/configs/ai/opencode/oh-my-openagent.json $XDG_CONFIG_HOME/opencode/oh-my-openagent.json
# OMX standalone config + agents
zf_ln -sfn $SCRIPT_DIR/configs/ai/omx/config.toml $HOME/.omx/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/omx/agents $HOME/.omx/agents
# Portless
zf_ln -sfn $SCRIPT_DIR/configs/portless $HOME/.portless
zf_ln -sfn $SCRIPT_DIR/configs/ai/portkey/portkey-gateway.service $XDG_CONFIG_HOME/systemd/user/portkey-gateway.service
# wake-peers (Universal Control screen-wake fanout). The sleepwatcher
# LaunchAgent itself is activated only on macOS peer hosts by
# scripts/deploy.d/76_wake_peers.zsh; these symlinks are cross-platform
# harmless data files.
zf_mkdir -p $XDG_CONFIG_HOME/wake-peers
zf_ln -sfn $SCRIPT_DIR/configs/wake-peers/peers.conf $XDG_CONFIG_HOME/wake-peers/peers.conf
zf_ln -sfn $SCRIPT_DIR/scripts/wake-peers $HOME/.local/bin/wake-peers
zf_ln -sfn $SCRIPT_DIR/configs/wake-peers/displaywakeup $HOME/.displaywakeup
for _ssh_file in $SCRIPT_DIR/ssh/*~$SCRIPT_DIR/ssh/*.enc(N.); do
    zf_ln -sfn $_ssh_file $HOME/.ssh/${_ssh_file:t}
done
# niri Wayland desktop stack (Linux only)
if [[ $DOTFILES_OS == Linux ]]; then
    zf_mkdir -p $XDG_CONFIG_HOME/niri
    zf_ln -sfn $SCRIPT_DIR/configs/niri/config.kdl $XDG_CONFIG_HOME/niri/config.kdl
    zf_mkdir -p $XDG_CONFIG_HOME/waybar
    zf_ln -sfn $SCRIPT_DIR/configs/waybar/config.jsonc $XDG_CONFIG_HOME/waybar/config.jsonc
    zf_ln -sfn $SCRIPT_DIR/configs/waybar/style.css $XDG_CONFIG_HOME/waybar/style.css
    zf_mkdir -p $XDG_CONFIG_HOME/mako
    zf_ln -sfn $SCRIPT_DIR/configs/mako/config $XDG_CONFIG_HOME/mako/config
    zf_mkdir -p $XDG_CONFIG_HOME/fuzzel
    zf_ln -sfn $SCRIPT_DIR/configs/fuzzel/fuzzel.ini $XDG_CONFIG_HOME/fuzzel/fuzzel.ini
    zf_mkdir -p $XDG_CONFIG_HOME/swaylock
    zf_ln -sfn $SCRIPT_DIR/configs/swaylock/config $XDG_CONFIG_HOME/swaylock/config
    zf_mkdir -p $XDG_CONFIG_HOME/wpaperd
    zf_ln -sfn $SCRIPT_DIR/configs/wpaperd/config.toml $XDG_CONFIG_HOME/wpaperd/config.toml
fi
print "  ...done"
