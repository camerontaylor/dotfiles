# Spawn a one-shot interactive zsh so powerlevel10k can download gitstatusd.
# Otherwise the first real interactive shell pays the download latency.
# Skipped under --dry-run: the child shell's side effects (gitstatusd
# download into ~/.cache, instant-prompt cache) are real mutations, and on
# an unlinked HOME it's an expensive no-op anyway.

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "P10k warmup skipped in dry-run (would: one-shot interactive zsh to fetch gitstatusd)"
    return 0
fi

printf '%s\n' "Downloading gitstatusd for powerlevel10k..."
zsh -is <<< '' &> /dev/null || true
printf '%s\n' "  ...done"
