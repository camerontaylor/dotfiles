# Load Vite+ completions after compinit. The env file is already sourced for
# every shell in env.d/09_vite_plus.zsh; this is only for interactive compdefs.
if (( ${+commands[vp]} )); then
    eval "$(VP_COMPLETE=zsh command vp)"
    eval '
    _vpr_complete() {
        local -a orig=("${words[@]}")
        words=("vp" "run" "${orig[@]:1}")
        CURRENT=$((CURRENT + 1))
        ${=_comps[vp]}
    }
    compdef _vpr_complete vpr
    '
fi
