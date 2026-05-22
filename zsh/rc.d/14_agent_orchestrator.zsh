# Agent Orchestrator (ao)
if [[ -z ${AO_GLOBAL_CONFIG:-} && -n ${XDG_CONFIG_HOME:-} ]]; then
    export AO_GLOBAL_CONFIG=$XDG_CONFIG_HOME/agent-orchestrator/config.yaml
fi

_ao_completion_dir=$DOTFILES/configs/ai/agent-orchestrator/completions
if [[ -d $_ao_completion_dir ]]; then
    fpath=($_ao_completion_dir $fpath)

    if [[ -n ${XDG_CACHE_HOME:-} && -f $_ao_completion_dir/_ao && -f $XDG_CACHE_HOME/zsh/compdump && $_ao_completion_dir/_ao -nt $XDG_CACHE_HOME/zsh/compdump ]]; then
        rm -f $XDG_CACHE_HOME/zsh/compdump
    fi
fi

unset _ao_completion_dir
