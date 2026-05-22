if (( ${+commands[zoxide]} )); then
    # zoxide init output is static (no cwd-resolved state) → safe to evalcache
    evalcache zoxide init zsh
else
    # Fallback to zsh-z plugin
    # XDG compliance
    ZSHZ_DATA=$XDG_CACHE_HOME/zsh/z
    # match to uncommon prefix
    ZSHZ_UNCOMMON=1
    # ignore case when lowercase, match case with uppercase
    ZSHZ_CASE=smart

    source $ZDOTDIR/plugins/z/zsh-z.plugin.zsh
fi
true
