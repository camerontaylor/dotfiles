# Register the worktree-scope chpwd hook after zoxide so directory tracking
# happens before any systemd-run shell handoff.
add-zsh-hook chpwd _agents_worktree_scope_enter
