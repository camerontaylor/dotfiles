# zsh-only file: `command -v` sees zsh builtins, so non-zsh shells (the bash
# env.d loader) return before touching the module system instead of paying a
# `zmodload: command not found` on every startup.
command -v zmodload >/dev/null 2>&1 || return 0

# Enable profiling, if requested via env var
# do `ZSH_ZPROF_ENABLE=1 exec zsh`
# (`${var:-}` beats `[[ -v var ]]`: same truthiness in zsh, and -v only
# exists in bash 4.2+.)
if [[ -n ${ZSH_ZPROF_ENABLE:-} ]]; then
    zmodload zsh/zprof
fi

# Load zsh/files module to provide some builtins for file modifications
zmodload -F zsh/files b:zf_ln b:zf_mkdir b:zf_rm
