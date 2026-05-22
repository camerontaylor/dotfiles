# Set terminal tab/window title to user@host:dir outside iTerm2 and SSH.
#
# iTerm2 manual tab names should stay sticky. Its shell integration, the
# prompt hook below, and tmux automatic renaming can all write OSC 0 titles, so
# we skip the automatic title refresh when running in iTerm2 or any SSH shell
# and leave manual overrides alone.
if [[ ${TERM_PROGRAM-} != iTerm.app && ${LC_TERMINAL-} != iTerm2 && -z ${ITERM_SESSION-} && -z ${SSH_TTY-} ]]; then
    _set_terminal_title() {
        print -Pn "\e]0;%n@%m:%~\a"
    }

    add-zsh-hook precmd _set_terminal_title
fi
