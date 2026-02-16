# Initialize wtp shell integration (tab completion and wtp cd)
if (( ${+commands[wtp]} )); then
  eval "$(wtp shell-init zsh)"
fi
