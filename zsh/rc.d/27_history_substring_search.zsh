# History substring search - must load after syntax-highlighting (26)
# Both are deferred, but zsh-defer preserves ordering
# Bound to Ctrl+Up/Ctrl+Down; Up/Down are plain history (up-line-or-history)
zsh-defer -c '
    source $ZDOTDIR/plugins/history-substring-search/zsh-history-substring-search.zsh
    bindkey "\e[1;5A" history-substring-search-up
    bindkey "\e[1;5B" history-substring-search-down
    bindkey -M vicmd "k" history-substring-search-up
    bindkey -M vicmd "j" history-substring-search-down
'
