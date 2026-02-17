# Set terminal tab/window title to user@host:dir
# Updates after each command via precmd hook
_set_terminal_title() {
    print -Pn "\e]0;%n@%m:%~\a"
}
add-zsh-hook precmd _set_terminal_title
