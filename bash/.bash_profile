# Login shells. bash reads only this file for logins (never .bashrc), so
# delegate to the interactive file — the classic pattern — and keep env
# handling in exactly one place (bash/env.sh, which .bashrc sources).
# zsh stays the interactive default; this tree is the opt-in bash twin
# (DOTFILES_SHELL knob, scripts/deploy.d/75_brew_setup.zsh).
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
