(( ${+commands[zoxide]} )) || return 0

autoload -Uz add-zsh-hook
typeset -gA _zoxide_seeded_git_common_dirs

_zoxide_add_pwd_once() {
    add-zsh-hook -d precmd _zoxide_add_pwd_once
    command zoxide add -- "$PWD" >/dev/null 2>&1 || true
}

_zoxide_seed_git_worktrees() {
    local common_dir line worktree

    common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
    [[ "$common_dir" == /* ]] || common_dir="$PWD/$common_dir"
    common_dir="${common_dir:A}"

    [[ -z "${_zoxide_seeded_git_common_dirs[$common_dir]:-}" ]] || return 0
    _zoxide_seeded_git_common_dirs[$common_dir]=1

    git worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
        [[ "$line" == worktree\ * ]] || continue
        worktree="${line#worktree }"
        [[ -d "$worktree" ]] || continue
        command zoxide add -- "$worktree" >/dev/null 2>&1 || true
    done
}

add-zsh-hook precmd _zoxide_add_pwd_once
add-zsh-hook precmd _zoxide_seed_git_worktrees
add-zsh-hook chpwd _zoxide_seed_git_worktrees
