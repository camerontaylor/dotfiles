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
zf_ln -sfn $SCRIPT_DIR/configs/cmux/cmux.json $XDG_CONFIG_HOME/cmux/cmux.json
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
# AeroSpace tiling-WM config. macOS-only tool, but AeroSpace only ever READS this
# file (never writes back), so a repo symlink is safe and gives both Macs an
# identical config; the link is an inert dangling file on Linux. Karabiner is
# deliberately NOT symlinked here — its JSON is GUI-owned and machine-specific, so
# it is generated from configs/karabiner/karabiner.ts in 78_karabiner.zsh instead.
zf_ln -sfn $SCRIPT_DIR/configs/aerospace/aerospace.toml $XDG_CONFIG_HOME/aerospace/aerospace.toml
# Sway config — the Linux counterpart to AeroSpace, same one-modifier scheme
# ($mod = Super where ⌥ sits on a Mac). Mirror the aerospace handling: Sway only
# READS this file, so an unconditional repo symlink is safe and gives every
# graphical Linux box an identical config; on macOS (and headless Linux that
# never starts Sway) the link is an inert dangling file. The Caps→Esc/Hyper half
# is delivered system-wide by keyd, installed separately in 79_keyd.zsh.
zf_ln -sfn $SCRIPT_DIR/configs/sway/config $XDG_CONFIG_HOME/sway/config
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $XDG_CONFIG_HOME/agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $HOME/.agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agent-orchestrator/config.yaml $HOME/.agent-orchestrator.yaml
zf_ln -sfn $SCRIPT_DIR/configs/ai/agents $HOME/.agents
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
# gpg-agent.conf is GENERATED, not symlinked: pinentry-program needs an
# absolute path (gpg-agent execs it verbatim — no ~, no PATH lookup) and $HOME
# differs per host, so we render the shared base (gpg/gpg-agent.conf) plus a
# host-resolved pinentry-program line pointing at the pinentry-auto wrapper,
# which picks pinentry-mac on macOS and stock pinentry elsewhere. Write to a
# temp file + mv: the target may still be the old symlink INTO the repo, and a
# direct `>` would follow it and clobber the base file.
zf_ln -sfn $SCRIPT_DIR/scripts/pinentry-auto $HOME/.local/bin/pinentry-auto
if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] generate $XDG_CONFIG_HOME/gnupg/gpg-agent.conf"
else
    {
        cat $SCRIPT_DIR/gpg/gpg-agent.conf
        print "pinentry-program $HOME/.local/bin/pinentry-auto"
    } > $XDG_CONFIG_HOME/gnupg/gpg-agent.conf.tmp
    mv -f $XDG_CONFIG_HOME/gnupg/gpg-agent.conf.tmp $XDG_CONFIG_HOME/gnupg/gpg-agent.conf
    # Pick the change up without killing cached passphrases / SSH keys.
    (( ${+commands[gpgconf]} )) && gpgconf --reload gpg-agent 2> /dev/null || true
fi
zf_ln -sfn $SCRIPT_DIR/tools/git-diff-pager $HOME/.local/bin/git-diff-pager
zf_ln -sfn $SCRIPT_DIR/scripts/commit-conventional $HOME/.local/bin/commit-conventional
zf_ln -sfn $SCRIPT_DIR/scripts/generate-commit-msg $HOME/.local/bin/generate-commit-msg
# Claude Code
claude_code_config_dir=$SCRIPT_DIR/configs/ai/claude-code
zf_ln -sfn $claude_code_config_dir/CLAUDE.md $HOME/.claude/CLAUDE.md
# RTK was nuked. Actively remove any stale link left by prior deploys so the
# removal propagates to every machine on its next deploy (idempotent no-op once gone).
if [[ -L $HOME/.claude/RTK.md || -e $HOME/.claude/RTK.md ]]; then
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] rm -f $HOME/.claude/RTK.md (stale RTK link)"
    else
        rm -f $HOME/.claude/RTK.md && print "  removed stale ~/.claude/RTK.md"
    fi
fi
zf_ln -sfn $claude_code_config_dir/settings.json $HOME/.claude/settings.json
zf_ln -sfn $claude_code_config_dir/settings.local.json $HOME/.claude/settings.local.json
zf_ln -sfn $claude_code_config_dir/statusline-command.sh $HOME/.claude/statusline-command.sh
zf_ln -sfn $claude_code_config_dir/hooks $HOME/.claude/hooks
zf_ln -sfn $claude_code_config_dir/skills $HOME/.claude/skills
zf_ln -sfn $claude_code_config_dir/commands $HOME/.claude/commands
zf_ln -sfn $claude_code_config_dir/agents $HOME/.claude/agents
zf_ln -sfn $claude_code_config_dir/mcp.json $HOME/.claude/.mcp.json
# Codex CLI
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/config.toml $HOME/.codex/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/agents $HOME/.codex/agents
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/prompts $HOME/.codex/prompts
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/rules $HOME/.codex/rules
zf_ln -sfn $SCRIPT_DIR/configs/ai/codex/skills $HOME/.codex/skills
# CodeWhale
zf_ln -sfn $SCRIPT_DIR/configs/ai/codewhale/config.toml $HOME/.codewhale/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/codewhale/settings.toml $HOME/.codewhale/settings.toml
zf_ln -sfn $SCRIPT_DIR/configs/ai/codewhale/skills $HOME/.codewhale/skills
# OpenCode
zf_ln -sfn $SCRIPT_DIR/configs/ai/opencode/opencode.json $XDG_CONFIG_HOME/opencode/opencode.json
# Portless
zf_ln -sfn $SCRIPT_DIR/configs/portless $HOME/.portless
zf_ln -sfn $SCRIPT_DIR/configs/ai/portkey/portkey-gateway.service $XDG_CONFIG_HOME/systemd/user/portkey-gateway.service
# npm globals list: mise's node backend reads ~/.default-npm-packages and
# reinstalls the listed globals automatically whenever it installs a node
# version, so a node bump can't silently drop the globals.
zf_ln -sfn $SCRIPT_DIR/.default-npm-packages $HOME/.default-npm-packages
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
    zf_mkdir -p $XDG_CONFIG_HOME/hypr
    zf_ln -sfn $SCRIPT_DIR/configs/hypr/hyprlock.conf $XDG_CONFIG_HOME/hypr/hyprlock.conf
    zf_ln -sfn $SCRIPT_DIR/configs/hypr/hypridle.conf $XDG_CONFIG_HOME/hypr/hypridle.conf
    zf_mkdir -p $XDG_CONFIG_HOME/wpaperd
    zf_ln -sfn $SCRIPT_DIR/configs/wpaperd/config.toml $XDG_CONFIG_HOME/wpaperd/config.toml
fi
print "  ...done"
