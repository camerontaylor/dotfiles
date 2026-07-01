# Pager configuration (prefer moor, fallback to less)
if (( ${+commands[moor]} )); then
    export PAGER=moor
else
    export PAGER=less
fi
export LESS="--RAW-CONTROL-CHARS --ignore-case --hilite-unread --LONG-PROMPT --window=-4 --tabs=4 --mouse --wheel-lines=3"
export READNULLCMD=$PAGER

# make sure local gpg knows about current TTY; avoid pinentry prompts in SSH sessions
if [[ -z ${SSH_TTY:-} && -z ${SSH_CONNECTION:-} && -z ${SSH_CLIENT:-} ]]; then
    export GPG_TTY=$TTY
else
    unset GPG_TTY
fi

# XDG basedir spec compliance
if [[ ! -v XDG_CONFIG_HOME ]]; then
    export XDG_CONFIG_HOME=$HOME/.config
fi
if [[ ! -v XDG_CACHE_HOME ]]; then
    export XDG_CACHE_HOME=$HOME/.cache
fi
if [[ ! -v XDG_DATA_HOME ]]; then
    export XDG_DATA_HOME=$HOME/.local/share
fi
if [[ ! -v XDG_STATE_HOME ]]; then
    export XDG_STATE_HOME=$HOME/.local/state
fi
_systemd_runtime_dir="/run/user/${EUID:-$(id -u)}"
if [[ -d $_systemd_runtime_dir && -O $_systemd_runtime_dir ]]; then
    export XDG_RUNTIME_DIR=$_systemd_runtime_dir
elif [[ ! -v XDG_RUNTIME_DIR || -z $XDG_RUNTIME_DIR ]]; then
    export XDG_RUNTIME_DIR=${TMPDIR:-/tmp}/runtime-$USER
fi
unset _systemd_runtime_dir

# ensure that XDG_RUNTIME_DIR dir exists, as it can be under tmpfs
if [[ ! -d $XDG_RUNTIME_DIR ]]; then
    zf_mkdir -m 0700 -p $XDG_RUNTIME_DIR
fi

# best effort to make tools compliant to XDG basedir spec
export GNUPGHOME=$XDG_CONFIG_HOME/gnupg
export LESSHISTFILE=$XDG_DATA_HOME/lesshst
export MYSQL_HISTFILE=$XDG_DATA_HOME/mysql_history
export REDISCLI_HISTFILE=$XDG_DATA_HOME/rediscli_history
export BUNDLE_USER_CONFIG=$XDG_CONFIG_HOME/bundle
export BUNDLE_USER_CACHE=$XDG_CACHE_HOME/bundle
export BUNDLE_USER_PLUGIN=$XDG_DATA_HOME/bundle
export DOCKER_CONFIG=$XDG_CONFIG_HOME/docker
export WINEPREFIX=$XDG_DATA_HOME/wine
export MACHINE_STORAGE_PATH=$XDG_DATA_HOME/docker/machine
export MINIKUBE_HOME=$XDG_DATA_HOME/minikube
export VAGRANT_HOME=$XDG_DATA_HOME/vagrant
export HTOPRC=$XDG_CONFIG_HOME/htop/htoprc
export PACKER_CONFIG=$XDG_CONFIG_HOME/packer
export PACKER_CACHE_DIR=$XDG_CACHE_HOME/packer
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/config
export NPM_CONFIG_CACHE=$XDG_CACHE_HOME/npm
export HTTPIE_CONFIG_DIR=$XDG_CONFIG_HOME/httpie
export ANSIBLE_LOCAL_TEMP=$XDG_RUNTIME_DIR/ansible/tmp
export GOPATH=$XDG_DATA_HOME/go
export GEM_HOME=$XDG_DATA_HOME/gem
export GEM_SPEC_CACHE=$XDG_CACHE_HOME/gem
export GEMRC=$XDG_CONFIG_HOME/gem/gemrc
export TASKDATA=$XDG_DATA_HOME/task
export TASKRC=$XDG_CONFIG_HOME/task/taskrc
export PERL_CPANM_HOME=$XDG_CACHE_HOME/cpanm
export SOLARGRAPH_CACHE=$XDG_CACHE_HOME/solargraph
export GTK2_RC_FILES=$XDG_CONFIG_HOME/gtk-2.0/gtkrc
export GHOSTTY_CONFIG_DIR="$HOME/.config/ghostty"

# Ghostty sets COLORTERM locally but it doesn't survive SSH
if [[ $TERM == xterm-ghostty && ! -v COLORTERM ]]; then
    export COLORTERM=truecolor
fi

# Remote hosts without Ghostty's terminfo decode keys poorly under xterm-ghostty.
if [[ $TERM == xterm-ghostty && ( -n ${SSH_TTY:-} || -n ${SSH_CONNECTION:-} ) ]]; then
    if (( ${+commands[infocmp]} )); then
        infocmp xterm-ghostty >/dev/null 2>&1 || export TERM=xterm-256color
    elif (( ${+commands[tput]} )); then
        tput -T xterm-ghostty longname >/dev/null 2>&1 || export TERM=xterm-256color
    else
        export TERM=xterm-256color
    fi
fi
