# Some sane defaults for fzf
export FZF_DEFAULT_OPTS="--ansi --height=50% --tmux=bottom,50%,border-native --border=top --layout=reverse-list"

# Use fd as fzf's file finder (respects .gitignore, faster than find)
if (( ${+commands[fd]} )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi

# Use bat for fzf file preview
if (( ${+commands[bat]} )); then
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
fi
