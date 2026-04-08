# Start tmux automatically for SSH sessions
# Handoff to tmux early, as rest of the rc config isn't needed for this shell
if (( ${+commands[tmux]} )) && [[ ! -v TMUX && -v SSH_TTY && $EUID != 0 ]]; then
    exec tmux new-session -A -s ssh
fi
