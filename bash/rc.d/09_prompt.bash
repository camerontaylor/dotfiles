# Prompt: starship. The zsh side uses powerlevel10k (.p10k.zsh); starship
# is the bash-side prompt. configs/starship.toml is already symlinked to
# ~/.config/starship.toml by 20_symlinks.zsh and starship reads that
# location by default — no config path needed here.
# `|| true`: a missing starship is a skip, not a fragment error.
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)" || true
