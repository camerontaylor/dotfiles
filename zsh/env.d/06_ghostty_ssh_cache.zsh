# Drop a stale ghostty ssh-cache entry (`app@localhost`) left behind by an
# earlier port-forward setup. `+ssh-cache --remove` prints "'X' is not in the
# cache." to STDERR when the entry is already gone — which is the steady state
# — so both streams must be discarded. .zshenv runs for EVERY zsh invocation
# (git hooks, cron, `zsh -c` from tooling), and an unredirected stderr here
# prefixes the output of every one of them.
(( ${+commands[ghostty]} )) && ghostty +ssh-cache --remove=app@localhost >/dev/null 2>&1 || true
