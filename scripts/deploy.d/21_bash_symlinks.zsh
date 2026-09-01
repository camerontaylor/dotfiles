# Bash interactive layer — the opt-in twin of the zsh install.
# zsh stays the default interactive shell (DOTFILES_SHELL knob,
# 75_brew_setup.zsh); these links only make `bash` usable, never default.
# 3.2 floor: mirrors 20_symlinks' constructs exactly.

printf '%s\n' "Linking bash interactive files..."

# One dir link covers env.sh, rc.d/, inputrc (bash's equivalent of the zsh
# ZDOTDIR tree — bash has no BASH_DOTDIR, hence the ~/.config/bash convention
# plus $BASH_ENV/$INPUTRC exports from bash/env.sh).
deploy_ln -sfn $SCRIPT_DIR/bash $XDG_CONFIG_HOME/bash
# Login + interactive entrypoints: bash only reads these from $HOME, so the
# zero-home trick below is the only way around them.
deploy_ln -sfn $SCRIPT_DIR/bash/.bash_profile $HOME/.bash_profile
deploy_ln -sfn $SCRIPT_DIR/bash/.bashrc $HOME/.bashrc

printf '%s\n' "  ...done"
