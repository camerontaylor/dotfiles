# History substring search - must load after syntax-highlighting (26)
# Both are deferred, but zsh-defer preserves ordering
zsh-defer -c '
    source $ZDOTDIR/plugins/history-substring-search/zsh-history-substring-search.zsh
    bindkey "^[[A" history-substring-search-up
    bindkey "^[[B" history-substring-search-down
    bindkey -M vicmd "k" history-substring-search-up
    bindkey -M vicmd "j" history-substring-search-down
'
