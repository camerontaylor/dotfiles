_load_zsh_z_fallback() {
    # Fallback to zsh-z plugin
    # XDG compliance
    ZSHZ_DATA=$XDG_CACHE_HOME/zsh/z
    # match to uncommon prefix
    ZSHZ_UNCOMMON=1
    # ignore case when lowercase, match case with uppercase
    ZSHZ_CASE=smart

    source $ZDOTDIR/plugins/z/zsh-z.plugin.zsh
}

if (( ${+commands[zoxide]} )); then
    # zoxide init output is static (no cwd-resolved state) → safe to evalcache
    evalcache zoxide init zsh

    # Fall back ONLY if zoxide's init did not actually define its command.
    # Do NOT gate this on evalcache's exit code: on a cache hit evalcache
    # returns the exit status of the last sourced line, which is unreliable
    # (often non-zero) even when zoxide loaded perfectly. zsh-z defines `z`
    # as an *alias*, and a same-named alias shadows zoxide's `z` *function* —
    # so a spurious fallback silently routes `z` to zsh-z's empty database.
    (( ${+functions[__zoxide_z]} )) || _load_zsh_z_fallback
else
    _load_zsh_z_fallback
fi

unfunction _load_zsh_z_fallback
true
