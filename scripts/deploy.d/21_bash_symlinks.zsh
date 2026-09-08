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
# Agent-routing wrappers are linked by the agents sibling deploy.
for _bash_wrapper in lspath bag fgb fgd fgl psg; do
    deploy_ln -sfn $SCRIPT_DIR/bin/$_bash_wrapper $HOME/.local/bin/$_bash_wrapper
done
unset _bash_wrapper

# webfront-root + p retired 2026-09-08 (owner decision, docs/fleet-consolidation.md
# "Owner decisions") — the webfront app is gone and the compat shims outlived it.
# Drift-correct hosts that still carry the old links (they dangle once the repo
# files are gone); only ever remove symlinks, never a real file — same shape as
# the ghx retirement in 70_runtime_installs.zsh. deploy_rm keeps --dry-run clean.
for _retired_link in webfront-root p; do
    if [ -L "$HOME/.local/bin/$_retired_link" ]; then
        printf '%s\n' "Removing retired link ~/.local/bin/$_retired_link..."
        deploy_rm -f "$HOME/.local/bin/$_retired_link"
        printf '%s\n' "  ...done"
    fi
done
unset _retired_link

printf '%s\n' "  ...done"
