#!/bin/sh
# Dual-shell syntax gate — every shell file in this repo must parse under
# BOTH zsh and /bin/bash (docs/bash-compatibility.md). One script, two
# callers: scripts/pre-commit (staged files under scripts/) and CI
# (.github/workflows/shells.yml — the whole tree, where the interactive
# zsh/ + bash/ + bin/ layers live that the staged path never sees).
#
# POSIX sh (not zsh): the pre-commit hook may fire on hosts without zsh
# installed... except the zsh -n leg needs zsh — so the hook does require a
# zsh on PATH; POSIX keeps the *file-list plumbing* portable to dash on
# Ubuntu CI runners. The staged list moves through a temp file because
# POSIX sh has no <(...) process substitution, and a `while` fed from a
# pipeline would lose the failure flag to its subshell.
#
# bash is pinned to /bin/bash: that is 3.2 on macOS (the fleet floor — a
# brew bash 5 first on PATH would accept more syntax than the oldest shell
# the bootstrap must survive) and the distro bash on Linux (the real
# target there).
#
# Scope caveat, verified empirically: -n is a floor, not a proof. bash -n
# rejects zsh glob qualifiers in word position (`*(N)`) but ACCEPTS every
# tested zsh parameter flag — `x=${(@f)v}`, `x=${+commands[x]}`,
# `x=${~v}`, `[[ -o interactive ]]` all parse clean under bash 3.2 and
# only explode at runtime. Those regressions are caught by running the
# bash driver (deploy.bash), not by this gate.
#
# Modes:
#   --staged  files staged under scripts/ (pre-commit path; zero exemptions
#             — the bootstrap layer is fully dual by policy)
#   --all     whole tree except submodules; files that are zsh-only by
#             design are listed in _zsh_only() with a reason and skip only
#             the bash -n leg (zsh -n still runs — a zsh-only file that
#             fails zsh -n is a real bug)

set -u

_prog=${0##*/}

fail=0

# zsh-only files — bash -n skipped in --all mode (file: reason).
# Keep sorted. Anything added here must say WHY it can never be bash.
# Derived empirically: run --all, every bash -n failure not in this list is
# either a new zsh-only file (add it with a reason) or a dual-target file
# that regressed (fix the file).
_zsh_only() {
    case $1 in
        deploy.zsh) return 0 ;;                       # the zsh driver; bash leg is deploy.bash (§A)
        zsh/.p10k.zsh) return 0 ;;                    # powerlevel10k wizard config
        zsh/.zshrc) return 0 ;;                       # interactive zsh entrypoint; twin is bash/.bashrc
        zsh/rc.d/01_instant_prompt.zsh) return 0 ;;   # p10k instant-prompt plumbing
        zsh/rc.d/05_keys.zsh) return 0 ;;             # bindkey/zle keymaps, zsh-builtins only
        zsh/rc.d/07_semantic_integration.zsh) return 0 ;; # zsh-defer'd plugin hooks
        zsh/rc.d/09_colors.zsh) return 0 ;;           # zsh color arrays/attributes
        zsh/rc.d/10_file_managers.zsh) return 0 ;;    # yazi + zsh glob-qualified wrappers
        zsh/rc.d/11_portkey.zsh) return 0 ;;          # autoload + zle prompt fn
        zsh/rc.d/12_paseo.zsh) return 0 ;;            # ${+commands[...]} + emulate -L
        zsh/rc.d/13_grc.zsh) return 0 ;;              # zsh-specific alias wrapping
        zsh/rc.d/15_completion.zsh) return 0 ;;       # compinit/zstyle/fpath wiring
        zsh/rc.d/17_fzf_tab.zsh) return 0 ;;          # fzf-tab zle plugin glue
        zsh/rc.d/19_ssh_auth_sock.zsh) return 0 ;;    # zsh-only socket update hook
        zsh/rc.d/20_cursor_shape.zsh) return 0 ;;     # zle escape sequences per-keymap
        zsh/fpath/ccm) return 0 ;;                    # stateful portkey wrapper, zsh constructs
        zsh/fpath/ccm-happy) return 0 ;;              # stateful portkey wrapper, zsh constructs
        zsh/fpath/ccz) return 0 ;;                    # stateful portkey wrapper, zsh constructs
        zsh/fpath/ccz-happy) return 0 ;;              # stateful portkey wrapper, zsh constructs
        zsh/fpath/evalcache) return 0 ;;              # ${(@f)...}/zparseopts internals
        zsh/fpath/compdefcache) return 0 ;;           # compdef/compadd wrappers
        zsh/fpath/ftb-tmux-popup) return 0 ;;         # zle widget + zsh parameter flags
        zsh/fpath/ineachdir) return 0 ;;              # zparseopts + TRAPINT + always block
        zsh/fpath/dotfiles-encrypt) return 0 ;;       # ${(...)~} glob modifiers
        zsh/fpath/w) return 0 ;;                      # wtp + zsh param expansion flags
        zsh/fpath/fz) return 0 ;;                     # zsh param expansion flags
        *) return 1 ;;
    esac
}

# zsh -n exemptions — files the linter itself is wrong about (file: reason).
# zsh -n is NOT a pure parse check: `${(pl:$((expr))::\n:)}` in command-
# argument position trips "bad math expression: illegal character: \M-I"
# while the identical construct in assignment position passes, and
# `autoload -Uz +X <file>` (which really compiles the body) succeeds. These
# files are verified loadable instead — see _zsh_loadable.
_zsh_n_exempt() {
    case $1 in
        zsh/fpath/clear-screen-soft-bottom) return 0 ;; # exactly that pl: construct; ^L widget in daily use
        *) return 1 ;;
    esac
}

# Compile check for _zsh_n_exempt files: +X loads and compiles the function
# without running it, which is the strongest machine-checkable "this parses"
# zsh offers for fpath files.
_zsh_loadable() {
    # Absolute-path autoload (a relative path isn't a function name); the
    # -c arg list keeps quoting airtight.
    zsh -f -c 'autoload -Uz +X $1' gate "$PWD/$1" 2>/dev/null
}

# Is this path a shell file? Extensions cover the named files; the shebang
# fallback covers extensionless executables (bin/, scripts/ tools).
_is_shell() {
    case $1 in
        */fpath/*|*/fpath.d/*|*.zsh|*.sh)
            return 0 ;;
        */.zshrc|*/.zshenv|*/.zprofile|*/.bashrc|*/.bash_profile)
            return 0 ;;
        *)
            if head -n 1 "$1" 2>/dev/null | grep -qE '^#!.*(bash|zsh|sh)([[:space:]]|$)'; then
                return 0
            fi
            return 1 ;;
    esac
}

_check_file() {
    _f=$1
    _mode=$2
    [ -n "$_f" ] || return 0
    _is_shell "$_f" || return 0
    [ -f "$_f" ] || return 0

    if ! zsh -n "$_f" 2>/dev/null; then
        if _zsh_n_exempt "$_f" && _zsh_loadable "$_f"; then
            printf '%s\n' "  ...zsh -n false positive, autoload +X verified: $_f"
        else
            printf '%s\n' "$_prog: zsh -n failed: $_f" >&2
            fail=1
            return 0
        fi
    fi

    if [ "$_mode" = all ] && _zsh_only "$_f"; then
        printf '%s\n' "  ...zsh-only, bash -n skipped: $_f"
        return 0
    fi

    if ! /bin/bash -n "$_f" 2>/dev/null; then
        printf '%s\n' "$_prog: /bin/bash -n failed: $_f" >&2
        fail=1
    fi
}

mode=
case ${1:-} in
    --staged) mode=staged ;;
    --all)    mode=all ;;
    *)  printf 'usage: %s --staged|--all\n' "$_prog" >&2
        exit 2 ;;
esac

list=$(mktemp "${TMPDIR:-/tmp}/shell-gate.XXXXXX") || {
    printf '%s\n' "$_prog: mktemp failed" >&2
    exit 1
}
trap 'rm -f "$list"' EXIT INT TERM

if [ "$mode" = staged ]; then
    # A failing `git diff --cached` aborts loud rather than letting the gate
    # pass vacuously on an empty list.
    if ! git diff --cached --name-only --diff-filter=ACMR -- scripts > "$list"; then
        printf '%s\n' "$_prog: git diff --cached failed; refusing to pass the gate on an empty list" >&2
        exit 1
    fi
else
    # Tree-wide: bootstrap layer + interactive layers. Submodules (tools/,
    # plugins/, zsh/plugins/) are foreign code and out of scope; .git noise
    # excluded. Roots that may not exist on a platform (raycast is mac-ish,
    # but it is tracked everywhere) are tolerated via find's implicit skip.
    find deploy.zsh deploy.bash scripts zsh bash bin raycast \
         \( -name .git -o -name plugins -o -name node_modules \) -prune -o \
         -type f -print > "$list" 2>/dev/null || true
fi

while IFS= read -r f; do
    _check_file "$f" "$mode"
done < "$list"

if [ "$fail" = 1 ]; then
    printf '%s\n' "$_prog: shell syntax gate failed — fix before committing" >&2
    exit 1
fi

exit 0
