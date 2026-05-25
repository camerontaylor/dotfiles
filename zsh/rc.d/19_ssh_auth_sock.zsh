# Maintain SSH_AUTH_SOCK to link at well-known places
if [[ EUID -ne 0 && -d $HOME/.ssh ]]; then
    ssh_auth_sock_link=$HOME/.ssh/ssh_auth_sock
    ssh_auth_sock_selected=0
    ssh_session=0
    [[ -n ${SSH_TTY:-} || -n ${SSH_CONNECTION:-} || -n ${SSH_CLIENT:-} ]] && ssh_session=1

    if [[ -S $SSH_AUTH_SOCK && ! -h $SSH_AUTH_SOCK && $SSH_AUTH_SOCK != $ssh_auth_sock_link ]]; then
        zf_ln -sfn $SSH_AUTH_SOCK $ssh_auth_sock_link
        ssh_auth_sock_selected=1
    elif (( ! ssh_session )); then
        if (( ${+commands[gpgconf]} )); then
            gpgconf --launch gpg-agent 2>/dev/null
            gpg_agent_ssh_sock=$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)
        fi

        if [[ -n $gpg_agent_ssh_sock && -S $gpg_agent_ssh_sock ]]; then
            zf_ln -sfn $gpg_agent_ssh_sock $ssh_auth_sock_link
            ssh_auth_sock_selected=1
        elif [[ -S $GNUPGHOME/S.gpg-agent.ssh ]]; then
            zf_ln -sfn $GNUPGHOME/S.gpg-agent.ssh $ssh_auth_sock_link
            ssh_auth_sock_selected=1
        elif [[ -S /run/user/$EUID/gnupg/S.gpg-agent.ssh ]]; then
            zf_ln -sfn /run/user/$EUID/gnupg/S.gpg-agent.ssh $ssh_auth_sock_link
            ssh_auth_sock_selected=1
        elif [[ -S /run/user/$EUID/gnupg/*/S.gpg-agent.ssh(#qN) ]]; then
            zf_ln -sfn /run/user/$EUID/gnupg/*/S.gpg-agent.ssh $ssh_auth_sock_link
            ssh_auth_sock_selected=1
        elif [[ -S $XDG_RUNTIME_DIR/ssh-agent.socket ]]; then
            zf_ln -sfn $XDG_RUNTIME_DIR/ssh-agent.socket $ssh_auth_sock_link
            ssh_auth_sock_selected=1
        fi
    elif [[ -S $XDG_RUNTIME_DIR/ssh-agent.socket ]]; then
        zf_ln -sfn $XDG_RUNTIME_DIR/ssh-agent.socket $ssh_auth_sock_link
        ssh_auth_sock_selected=1
    fi

    if (( ssh_auth_sock_selected )) || { (( ! ssh_session )) && [[ -S $ssh_auth_sock_link ]]; }; then
        export SSH_AUTH_SOCK=$ssh_auth_sock_link
    else
        unset SSH_AUTH_SOCK
    fi
fi
