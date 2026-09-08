# Symlink every dotfile/config into its XDG home.

printf '%s\n' "Linking config files..."
deploy_ln -sfn $SCRIPT_DIR/configs/bat/config $XDG_CONFIG_HOME/bat/config
deploy_ln -sfn $SCRIPT_DIR/nvim/init.lua $XDG_CONFIG_HOME/nvim/init.lua
deploy_ln -sfn $SCRIPT_DIR/nvim/init $XDG_CONFIG_HOME/nvim/plugin/init
deploy_ln -sfn $SCRIPT_DIR/nvim/lsp $XDG_CONFIG_HOME/nvim/after/lsp
deploy_ln -sfn $SCRIPT_DIR/nvim/ftplugin $XDG_CONFIG_HOME/nvim/ftplugin
deploy_ln -sfn $SCRIPT_DIR/nvim/plugins $XDG_DATA_HOME/nvim/site/pack/plugins/start
deploy_ln -sfn $SCRIPT_DIR/tmux $XDG_CONFIG_HOME/tmux
deploy_ln -sfn $SCRIPT_DIR/configs/ghostty $XDG_CONFIG_HOME/ghostty/config
deploy_ln -sfn $SCRIPT_DIR/configs/cmux/cmux.json $XDG_CONFIG_HOME/cmux/cmux.json
deploy_ln -sfn $SCRIPT_DIR/configs/gitconfig $XDG_CONFIG_HOME/git/config
deploy_ln -sfn $SCRIPT_DIR/configs/gitattributes $XDG_CONFIG_HOME/git/attributes
deploy_ln -sfn $SCRIPT_DIR/configs/gitignore $XDG_CONFIG_HOME/git/ignore
deploy_ln -sfn $SCRIPT_DIR/configs/tigrc $XDG_CONFIG_HOME/tig/config
deploy_ln -sfn $SCRIPT_DIR/configs/htoprc $XDG_CONFIG_HOME/htop/htoprc
# btop rewrites this file wholesale on exit (save_config_on_exit defaults true),
# regenerating every comment from its own current_config() — so configs/btop.conf
# is kept verbatim in btop's emitted format, and hand-added commentary there would
# be erased on first quit. The write is an in-place ofstream, so it follows this
# symlink back into the repo exactly as htoprc does; see README "Local paths &
# ignoring config churn" for the --assume-unchanged escape hatch.
deploy_ln -sfn $SCRIPT_DIR/configs/btop.conf $XDG_CONFIG_HOME/btop/btop.conf
deploy_ln -sfn $SCRIPT_DIR/configs/ranger $XDG_CONFIG_HOME/ranger/rc.conf
deploy_ln -sfn $SCRIPT_DIR/configs/gemrc $XDG_CONFIG_HOME/gem/gemrc
deploy_ln -sfn $SCRIPT_DIR/configs/ranger-plugins $XDG_CONFIG_HOME/ranger/plugins
deploy_ln -sfn $SCRIPT_DIR/configs/starship.toml $XDG_CONFIG_HOME/starship.toml
deploy_ln -sfn $SCRIPT_DIR/configs/mise.toml $XDG_CONFIG_HOME/mise/config.toml
# AeroSpace tiling-WM config. macOS-only tool, but AeroSpace only ever READS this
# file (never writes back), so a repo symlink is safe and gives both Macs an
# identical config; the link is an inert dangling file on Linux. Karabiner is
# deliberately NOT symlinked here — its JSON is GUI-owned and machine-specific, so
# it is generated from configs/karabiner/karabiner.ts in 78_karabiner.zsh instead.
deploy_ln -sfn $SCRIPT_DIR/configs/aerospace/aerospace.toml $XDG_CONFIG_HOME/aerospace/aerospace.toml
# Sway config — the Linux counterpart to AeroSpace, same one-modifier scheme
# ($mod = Super where ⌥ sits on a Mac). Mirror the aerospace handling: Sway only
# READS this file, so an unconditional repo symlink is safe and gives every
# graphical Linux box an identical config; on macOS (and headless Linux that
# never starts Sway) the link is an inert dangling file. The Caps→Esc/Hyper half
# is delivered system-wide by keyd, installed separately in 79_keyd.zsh.
deploy_ln -sfn $SCRIPT_DIR/configs/sway/config $XDG_CONFIG_HOME/sway/config
deploy_mkdir -p $XDG_CONFIG_HOME/waveterm
deploy_ln -sfn $SCRIPT_DIR/configs/waveterm/settings.json $XDG_CONFIG_HOME/waveterm/settings.json
deploy_mkdir -p $XDG_CONFIG_HOME/gtk-3.0
deploy_ln -sfn $SCRIPT_DIR/configs/gtk-3.0-bookmarks $XDG_CONFIG_HOME/gtk-3.0/bookmarks
deploy_ln -sfn $SCRIPT_DIR/yazi/init.lua $XDG_CONFIG_HOME/yazi/init.lua
deploy_ln -sfn $SCRIPT_DIR/yazi/keymap.toml $XDG_CONFIG_HOME/yazi/keymap.toml
deploy_ln -sfn $SCRIPT_DIR/yazi/theme.toml $XDG_CONFIG_HOME/yazi/theme.toml
deploy_ln -sfn $SCRIPT_DIR/yazi/yazi.toml $XDG_CONFIG_HOME/yazi/yazi.toml
deploy_ln -sfn $SCRIPT_DIR/yazi/plugins $XDG_CONFIG_HOME/yazi/plugins
deploy_ln -sfn $SCRIPT_DIR/gpg/gpg.conf $XDG_CONFIG_HOME/gnupg/gpg.conf
# gpg-agent.conf is GENERATED, not symlinked: pinentry-program needs an
# absolute path (gpg-agent execs it verbatim — no ~, no PATH lookup) and $HOME
# differs per host, so we render the shared base (gpg/gpg-agent.conf) plus a
# host-resolved pinentry-program line pointing at the pinentry-auto wrapper,
# which picks pinentry-mac on macOS and stock pinentry elsewhere. Write to a
# temp file + mv: the target may still be the old symlink INTO the repo, and a
# direct `>` would follow it and clobber the base file.
deploy_ln -sfn $SCRIPT_DIR/scripts/pinentry-auto $HOME/.local/bin/pinentry-auto
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] generate $XDG_CONFIG_HOME/gnupg/gpg-agent.conf"
else
    {
        cat $SCRIPT_DIR/gpg/gpg-agent.conf
        printf '%s\n' "pinentry-program $HOME/.local/bin/pinentry-auto"
    } > $XDG_CONFIG_HOME/gnupg/gpg-agent.conf.tmp
    mv -f $XDG_CONFIG_HOME/gnupg/gpg-agent.conf.tmp $XDG_CONFIG_HOME/gnupg/gpg-agent.conf
    # Pick the change up without killing cached passphrases / SSH keys.
    have gpgconf && gpgconf --reload gpg-agent 2> /dev/null || true
fi
deploy_ln -sfn $SCRIPT_DIR/tools/git-diff-pager $HOME/.local/bin/git-diff-pager
# Agent configuration, workflow commands and units are owned by the agents
# sibling (67_agents.zsh). Portless remains general development tooling.
deploy_ln -sfn $SCRIPT_DIR/configs/portless $HOME/.portless
# npm globals list: mise's node backend reads ~/.default-npm-packages and
# reinstalls the listed globals automatically whenever it installs a node
# version, so a node bump can't silently drop the globals.
deploy_ln -sfn $SCRIPT_DIR/.default-npm-packages $HOME/.default-npm-packages
# wake-peers (Universal Control screen-wake fanout). The sleepwatcher
# LaunchAgent itself is activated only on macOS peer hosts by
# scripts/deploy.d/76_wake_peers.zsh; these symlinks are cross-platform
# harmless data files.
deploy_mkdir -p $XDG_CONFIG_HOME/wake-peers
deploy_ln -sfn $SCRIPT_DIR/configs/wake-peers/peers.conf $XDG_CONFIG_HOME/wake-peers/peers.conf
deploy_ln -sfn $SCRIPT_DIR/scripts/wake-peers $HOME/.local/bin/wake-peers
deploy_ln -sfn $SCRIPT_DIR/configs/wake-peers/displaywakeup $HOME/.displaywakeup
# Link every plaintext ssh file (not the *.enc ciphertexts). The old
# `*~*.enc(N.)` exclusion glob was zsh-only; find does the same walk in both
# shells and stays silent when the directory has no matches (the zsh driver
# runs err_exit without null_glob, where a missed glob is a hard error).
# `! -name '.*'` mirrors the glob's dotfile skip.
while IFS= read -r _ssh_file; do
    deploy_ln -sfn "$_ssh_file" "$HOME/.ssh/${_ssh_file##*/}"
done < <(find "$SCRIPT_DIR/ssh" -maxdepth 1 -type f ! -name '*.enc' ! -name '.*' 2>/dev/null | sort)
# niri Wayland desktop stack (Linux only)
if [[ $DOTFILES_OS == Linux ]]; then
    deploy_mkdir -p $XDG_CONFIG_HOME/niri
    deploy_ln -sfn $SCRIPT_DIR/configs/niri/config.kdl $XDG_CONFIG_HOME/niri/config.kdl
    deploy_mkdir -p $XDG_CONFIG_HOME/waybar
    deploy_ln -sfn $SCRIPT_DIR/configs/waybar/config.jsonc $XDG_CONFIG_HOME/waybar/config.jsonc
    deploy_ln -sfn $SCRIPT_DIR/configs/waybar/style.css $XDG_CONFIG_HOME/waybar/style.css
    deploy_mkdir -p $XDG_CONFIG_HOME/mako
    deploy_ln -sfn $SCRIPT_DIR/configs/mako/config $XDG_CONFIG_HOME/mako/config
    deploy_mkdir -p $XDG_CONFIG_HOME/fuzzel
    deploy_ln -sfn $SCRIPT_DIR/configs/fuzzel/fuzzel.ini $XDG_CONFIG_HOME/fuzzel/fuzzel.ini
    deploy_mkdir -p $XDG_CONFIG_HOME/hypr
    deploy_ln -sfn $SCRIPT_DIR/configs/hypr/hyprlock.conf $XDG_CONFIG_HOME/hypr/hyprlock.conf
    deploy_ln -sfn $SCRIPT_DIR/configs/hypr/hypridle.conf $XDG_CONFIG_HOME/hypr/hypridle.conf
    deploy_mkdir -p $XDG_CONFIG_HOME/wpaperd
    deploy_ln -sfn $SCRIPT_DIR/configs/wpaperd/config.toml $XDG_CONFIG_HOME/wpaperd/config.toml
fi
printf '%s\n' "  ...done"
