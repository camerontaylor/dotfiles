# 04c_worktree_scope.zsh — chpwd hook: enter worktree scope on cd into a worktree.
#
# Why a chpwd hook (not mise hook):
#   mise hooks run in a mise-spawned subprocess. exec systemd-run -- $SHELL -i
#   in that subprocess replaces the SUBPROCESS, not the user's interactive zsh.
#   chpwd runs inline in the user's shell, so exec truly replaces the user's
#   shell. (Verified empirically during deep-interview iter 2: even with
#   mise's `experimental=true` flag set, the mise hook subprocess can't reach
#   the parent shell.)
#
# Why this slot (04c_): runs after 04_autoload.zsh so add-zsh-hook is available,
# and before 05_keys.zsh under en_AU.UTF-8.

autoload -Uz add-zsh-hook

_agents_worktree_scope_enter() {
  # Must be in an interactive shell.
  [[ -o interactive ]] || return 0

  # Do not replace command-string shells (`zsh -ic 'cd worktree && ...'`) with
  # a fresh prompt; callers use that form specifically because it should return.
  [[ -z "${ZSH_EXECUTION_STRING:-}" ]] || return 0

  # Must be inside a git working tree (not non-git dir).
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  # Distinguish worktree from main checkout. In main: git-dir == git-common-dir.
  # In worktrees: git-dir is <main>/.git/worktrees/<name>, git-common-dir is <main>/.git.
  # Use cd -P + pwd -P for portability (no realpath dependency).
  local git_dir git_common_dir resolved_git resolved_common
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 0
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
  resolved_git=$(cd -P -- "$git_dir" 2>/dev/null && pwd -P) || return 0
  resolved_common=$(cd -P -- "$git_common_dir" 2>/dev/null && pwd -P) || return 0
  [[ "$resolved_git" != "$resolved_common" ]] || return 0

  # Compute slug compatible with derive_session_name in cglauncher:60-74.
  local wt_path branch clean hash slug unit
  wt_path=$(git rev-parse --show-toplevel)
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
  clean=$(echo "$branch" | sed 's|.*/||; s|[^a-zA-Z0-9-]|-|g' | tr '[:upper:]' '[:lower:]')
  hash=$(echo -n "$wt_path" | md5sum | cut -c1-4)
  slug="wt-${clean}-${hash}"
  unit="worktree-${slug}-${$}-${RANDOM}.scope"

  # If already inside this worktree's scope, do nothing. systemd-run cannot
  # attach a process to an existing scope by reusing --unit, so scopes are
  # per-shell and the stable slug is used only for idempotency and inspection.
  if [[ -r /proc/self/cgroup ]] && grep -q "/worktree-${slug}-[^/]*\\.scope" /proc/self/cgroup; then
    return 0
  fi

  if (( ! ${+commands[systemctl]} || ! ${+commands[systemd-run]} )); then
    return 0
  fi

  # Read agents.slice cap to compute per-worktree cap = min(16G, agents.slice / 2).
  local agents_max cap_16g cap_half mem_max
  agents_max=$(systemctl --user show agents.slice -p MemoryMax --value 2>/dev/null)
  if [[ -z "$agents_max" || "$agents_max" == "infinity" ]]; then
    print -u2 "[worktree-scope] WARNING: cannot read agents.slice MemoryMax; skipping scope creation."
    return 0
  fi
  cap_16g=$(( 16 * 1024 * 1024 * 1024 ))
  cap_half=$(( agents_max / 2 ))
  if (( cap_half < cap_16g )); then
    mem_max=$cap_half  # 16G hosts: 5G per scope
  else
    mem_max=$cap_16g
  fi

  # Validate transient scope creation before replacing this shell. Do not use
  # --unit here: the real handoff gets a unique name below.
  if ! systemd-run --user --scope --slice=agents.slice --quiet --collect -- true >/dev/null 2>&1; then
    print -u2 "[worktree-scope] WARNING: systemd-run scope handoff failed; skipping scope creation."
    return 0
  fi

  exec systemd-run --user --scope --slice=agents.slice --unit="$unit" \
    --property=MemoryMax=${mem_max} --property=MemorySwapMax=0 \
    --property=CPUQuota=200% --same-dir --quiet --collect -- "$SHELL" -i
}

add-zsh-hook chpwd _agents_worktree_scope_enter
