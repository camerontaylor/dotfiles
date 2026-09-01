# zoxide `z` — bash twin of zsh/rc.d/14_z.zsh.
# `|| true`: the loader reports a non-zero fragment as an error; a missing
# zoxide is a skip, not an error (same idiom as env.d/06_ghostty_ssh_cache).
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)" || true
