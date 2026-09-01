# Spawn a one-shot interactive zsh so powerlevel10k can download gitstatusd.
# Otherwise the first real interactive shell pays the download latency.

printf '%s\n' "Downloading gitstatusd for powerlevel10k..."
zsh -is <<< '' &> /dev/null || true
printf '%s\n' "  ...done"
