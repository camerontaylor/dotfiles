# Override regular 'clear' with custom one, that puts prompt at bottom
# Also suppress it from history
alias clear=" clear-screen-soft-bottom"

# GNU userland aliases: on macOS prefer the `g`-prefixed brew binaries
# (coreutils, grep, diffutils); on Linux the stock names are already GNU.
# Falls through silently if the GNU binary is missing, leaving BSD behavior
# rather than a broken alias.
gnu_alias() {
    local name=$1
    shift
    if [[ $OSTYPE == darwin* ]] && (( ${+commands[g$name]} )); then
        alias "$name"="g$name $*"
    elif [[ $OSTYPE != darwin* ]] && (( ${+commands[$name]} )); then
        alias "$name"="$name $*"
    fi
}

# Prefer nvim when installed
(( ${+commands[nvim]} )) && {
    alias nv="nvim"
    alias vi="nvim"
    alias vim="nvim"
}

# Prefer Homebrew's modern bash over macOS's bundled 3.2.57 when typing
# `bash some-script.sh` interactively. The brew binary is already first on
# PATH via `brew shellenv` (see zsh/env.d/03_paths.zsh), so this alias is
# belt-and-suspenders insurance against future PATH-ordering changes.
# Has NO effect on scripts launched by a `#!/bin/bash` shebang — those go
# straight to /bin/bash 3.2 and must use `#!/usr/bin/env bash` to pick up
# the brew binary.
if [[ $OSTYPE == darwin* ]] && [[ -n $HOMEBREW_PREFIX ]] && [[ -x $HOMEBREW_PREFIX/bin/bash ]]; then
    alias bash="$HOMEBREW_PREFIX/bin/bash"
fi

# Open a path in ForkLift (macOS only). ForkLift's plain `open -a` handler
# dumps the path into its search UI; its AppleScript `reveal` verb opens a
# dir directly and selects a file in its parent, so use that instead.
if [[ $OSTYPE == darwin* ]]; then
    fl() {
        local t="${1:-.}"
        osascript >/dev/null \
            -e 'on run argv' \
            -e 'tell application "ForkLift" to reveal path (item 1 of argv)' \
            -e 'tell application "ForkLift" to activate' \
            -e 'end run' "${t:A}"
    }
fi

# Human file sizes
gnu_alias df --human-readable --print-type
gnu_alias du --human-readable --total

# Handy stuff and a bit of XDG compliance
gnu_alias grep --color=auto --binary-files=without-match --devices=skip
(( ${+commands[quilt]} )) && alias quilt="quilt --quiltrc $DOTFILES/configs/quiltrc"
(( ${+commands[tmux]} )) && alias stmux="tmux new-session 'sudo --login'"
(( ${+commands[wget]} )) && alias wget="wget --hsts-file=$XDG_CACHE_HOME/wget-hsts"
(( ${+commands[gh]} )) && alias gh-pr="$DOTFILES/scripts/gh-pr.sh"
# Prefer eza over ls when available
if (( ${+commands[eza]} )); then
    alias ls="eza --group-directories-first --color=auto --hyperlink"
    alias ll="eza -l --git --almost-all --group-directories-first"
    alias lln="eza -l --git --almost-all --group-directories-first -snew"
    alias tree="eza --tree --git-ignore"
else
    alias ls="ls --group-directories-first --color=auto --hyperlink=auto --classify"
    alias ll="LC_COLLATE=C ls -l -v --almost-all --human-readable"
    alias lln="ls -l -t -r --almost-all --human-readable"
fi
gnu_alias diff --color=auto --new-file --text --recursive --unified


# OpenClaw
alias openclaw='docker compose -f ~/repos/deploy/openclaw/docker-compose.yml exec openclaw-gateway openclaw'

# GTK portal file dialogs
export GTK_USE_PORTAL=1

# History suppression
alias pwd=" pwd"
alias exit=" exit"

# Safety
gnu_alias rm -I --preserve-root=all

# Suppress suggestions and globbing, enable wrappers
(( ${+commands[find]} )) && alias find="noglob find"
(( ${+commands[touch]} )) && alias touch="nocorrect touch"
(( ${+commands[mkdir]} )) && alias mkdir="nocorrect mkdir"
(( ${+commands[cp]} )) && alias cp="nocorrect cp --verbose"
(( ${+commands[ag]} )) && alias ag="noglob ag"
(( ${+commands[fd]} )) && alias fd="noglob fd"
(( ${+commands[man]} )) && alias man="nocorrect man"
(( ${+commands[sudo]} )) && alias sudo="noglob wrap-sudo " # trailing space is needed to enable alias expansion
