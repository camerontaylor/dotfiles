# Aliases — curated subset of zsh/rc.d/08_aliases.zsh. Skipped rows and why:
#   noglob/nocorrect prefixes (find/touch/mkdir/cp/ag/fd/man/sudo) — zsh
#     precommand modifiers with no bash counterpart, and bash never
#     glob-expands arguments anyway;
#   `clear` override — wraps a zsh zle function;
#   `fl` (ForkLift reveal) — uses zsh's ${t:A} abspath expansion;
#   wrap-sudo — a zsh script on the zsh fpath.
# ${+commands[x]} probes become `command -v x`.

command -v nvim >/dev/null 2>&1 && {
    alias nv="nvim"
    alias vi="nvim"
    alias vim="nvim"
}

# Prefer Homebrew's bash over the bundled 3.2 interactively. No effect on
# `#!/bin/bash` shebangs — those must use `#!/usr/bin/env bash` (same note
# as the zsh alias).
if [[ $OSTYPE == darwin* ]] && [[ -n $HOMEBREW_PREFIX ]] && [[ -x $HOMEBREW_PREFIX/bin/bash ]]; then
    alias bash="$HOMEBREW_PREFIX/bin/bash"
fi

# GNU userland flags: `g`-prefixed brew binaries on macOS, stock (already
# GNU) names on Linux. Falls through silently when missing.
_gnu_alias() {
    _ga_name=$1
    shift
    if [[ $OSTYPE == darwin* ]] && command -v "g$_ga_name" >/dev/null 2>&1; then
        alias "$_ga_name"="g$_ga_name $*"
    elif [[ $OSTYPE != darwin* ]] && command -v "$_ga_name" >/dev/null 2>&1; then
        alias "$_ga_name"="$_ga_name $*"
    fi
    unset _ga_name
}
_gnu_alias df --human-readable --print-type
_gnu_alias du --human-readable --total
_gnu_alias grep --color=auto --binary-files=without-match --devices=skip
_gnu_alias diff --color=auto --new-file --text --recursive --unified
_gnu_alias rm -I --preserve-root=all

command -v eza >/dev/null 2>&1 && {
    alias ls="eza --group-directories-first --color=auto --hyperlink"
    alias ll="eza -l --git --almost-all --group-directories-first"
    alias lln="eza -l --git --almost-all --group-directories-first -snew"
    alias tree="eza --tree --git-ignore"
}
command -v wget >/dev/null 2>&1 && alias wget="wget --hsts-file=$XDG_CACHE_HOME/wget-hsts"
command -v quilt >/dev/null 2>&1 && alias quilt="quilt --quiltrc $DOTFILES/configs/quiltrc"
command -v tmux >/dev/null 2>&1 && alias stmux="tmux new-session 'sudo --login'"
command -v gh >/dev/null 2>&1 && alias gh-pr="$DOTFILES/scripts/gh-pr.sh"

alias openclaw='docker compose -f ~/repos/deploy/openclaw/docker-compose.yml exec openclaw-gateway openclaw'

# GTK portal file dialogs (env, but lives beside its zsh alias twin)
export GTK_USE_PORTAL=1

# History suppression — leading space + HISTCONTROL=ignorespace
alias pwd=" pwd"
alias exit=" exit"
