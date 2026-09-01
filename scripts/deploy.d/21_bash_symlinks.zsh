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

# fpath CLI wrappers moved out of zsh/fpath into bin/ (bash twins, shared by
# both shells — ~/.local/bin is already on PATH via zsh/env.d/03_paths.zsh,
# so linking here adds NO new PATH entry and cannot change PATH order).
# webfront-root goes first as a sibling: the wrappers resolve it via
# $(dirname "$0") so repo bin/ and ~/.local/bin stay self-consistent pairs.
deploy_ln -sfn $SCRIPT_DIR/bin/webfront-root $HOME/.local/bin/webfront-root
for _bash_wrapper in cc yolo p ccd ccd-happy \
                      ccm-direct ccm-direct-happy ccd-direct ccd-direct-happy \
                      ccfw-direct ccz-direct ccz-direct-happy \
                      lspath bag fgb fgd fgl psg; do
    deploy_ln -sfn $SCRIPT_DIR/bin/$_bash_wrapper $HOME/.local/bin/$_bash_wrapper
done
unset _bash_wrapper

printf '%s\n' "  ...done"
