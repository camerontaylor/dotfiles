# Spawn a one-shot interactive zsh so powerlevel10k can download gitstatusd.
# Otherwise the first real interactive shell pays the download latency.

print "Downloading gitstatusd for powerlevel10k..."
zsh -is <<< '' &> /dev/null || true
print "  ...done"
