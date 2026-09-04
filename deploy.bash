#!/usr/bin/env bash
# Bash twin of deploy.zsh — same CLI, same helpers, same fragments, same log
# format. The fragments under scripts/deploy.d/ are shared contract surface:
# shell-agnostic bodies served by either driver (docs/bash-compatibility.md §A).
# zsh stays the regression baseline; `diff <(./deploy.zsh --dry-run)
# <(./deploy.bash --dry-run)` must be empty modulo timestamps.
#
# This file itself targets the bash 3.2 floor (macOS stock /bin/bash): no
# globstar, typeset -g, declare -A, [[ -v ]], ${var,,}, or mapfile. `shopt -s
# nullglob` is fine HERE (driver is bash-only; only fragments/helpers must be
# dual-shell). Usage and fragment layout: see deploy.zsh.
#
# Known dry-run differential vs deploy.zsh beyond timestamps: a zsh
# interpreter implicitly sources ~/.zshenv before the script body runs (the
# repo's sets a worktree-aware ZDOTDIR and loads env.d), while bash starts
# from the raw inherited environment. On an already-deployed box that makes
# 10_dirs.zsh print its "would symlink .zshenv" branch here vs "present and
# valid" under zsh; on a fresh box both drivers take the symlink branch.

set -eE -o pipefail

# Diagnostics only — deploy.zsh's err_exit exits silently; -E inherits this
# trap into sourced fragments so a fatal failure names the driver line.
trap 'printf "%s\n" "deploy.bash: aborted at line $LINENO (exit $?)" >&2' ERR

# ── Version floor assert (docs/bash-compatibility.md §E) ──────────────────
# Fragments ≤74 and both drivers must run on the fleet's oldest shell, so the
# floor is /bin/bash 3.2 (macOS stock). Anything older/missing fails loud
# instead of half-running the deploy.
_bash_version=$(/bin/bash --version 2>/dev/null | head -n 1)
_bash_version=${_bash_version#*version }
_bash_major=${_bash_version%%.*}
_bash_minor=${_bash_version#*.}
_bash_minor=${_bash_minor%%.*}
case $_bash_major in ''|*[!0-9]*) _bash_major=0 ;; esac
case $_bash_minor in ''|*[!0-9]*) _bash_minor=0 ;; esac
if (( _bash_major < 3 )) || { (( _bash_major == 3 )) && (( _bash_minor < 2 )); }; then
    printf '%s\n' "FATAL: /bin/bash is version $_bash_major.$_bash_minor; this deploy needs >= 3.2" >&2
    exit 2
fi
unset _bash_version _bash_major _bash_minor

# Argument parsing — fail-closed on unknown flags or missing --only value.
upgrade_mode=false
export DEPLOY_DRY_RUN=0
# Escape hatch for fragment-level safety guards. It originally bypassed the
# mtime/clobber date guards in 65_sops.zsh; that fragment was retired by the
# secrets-repo migration, and its replacement (65_secrets.zsh) deliberately
# has no guards to bypass — ciphertext is canonical, plaintext is derived, so
# re-rendering is always correct. No fragment reads DEPLOY_FORCE today; the
# flag is kept as a stable interface for future guarded fragments.
export DEPLOY_FORCE=0
deploy_only=()
while (( $# > 0 )); do
    case $1 in
        --upgrade|-u)
            upgrade_mode=true
            ;;
        --dry-run|-n)
            DEPLOY_DRY_RUN=1
            ;;
        --force|-f)
            DEPLOY_FORCE=1
            ;;
        --only=*)
            deploy_only+=("${1#--only=}")
            ;;
        --only)
            if (( $# < 2 )) || [[ $2 == --* ]]; then
                printf '%s\n' "FATAL: --only requires a value (fragment basename without .zsh)" >&2
                exit 2
            fi
            deploy_only+=("$2")
            shift
            ;;
        --help|-h)
            printf '%s\n' "usage: deploy.bash [--upgrade|-u] [--dry-run|-n] [--force|-f] [--only NAME ...]"
            printf '%s\n' ""
            printf '%s\n' "  --upgrade    run brew/mise/cargo upgrades in addition to installs"
            printf '%s\n' "  --dry-run    fragments print intentions via [dry-run] without mutating"
            printf '%s\n' "  --force      bypass fragment safety guards (no fragment reads it"
            printf '%s\n' "               today; secrets rendering is unconditional)"
            printf '%s\n' "  --only NAME  run only fragments whose basename matches NAME"
            printf '%s\n' "               (e.g., --only 30_submodules); repeat for multiple"
            exit 0
            ;;
        *)
            printf '%s\n' "FATAL: unknown argument: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# Absolute, symlink-resolved dir of this script — zsh's ${0:A:h} has no bash
# spelling; this is the canonical walk from scripts/generate-commit-msg.
_self=${BASH_SOURCE[0]}
while [[ -L $_self ]]; do
    _self_dir=$(cd -P -- "$(dirname -- "$_self")" && pwd)
    _self=$(readlink "$_self")
    [[ $_self != /* ]] && _self=$_self_dir/$_self
done
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$_self")" && pwd)
# with systemd-homed, an absolute resolution lands on the storage location
# /home/username.homedir instead of the mounted /home/username — massage
# SCRIPT_DIR back (mirrors deploy.zsh).
if [[ $SCRIPT_DIR == "$HOME".homedir* ]]; then
    SCRIPT_DIR=${SCRIPT_DIR/.homedir/}
fi
cd "$SCRIPT_DIR"
export SCRIPT_DIR

# Default XDG paths.
XDG_CACHE_HOME=$HOME/.cache
XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share
XDG_STATE_HOME=$HOME/.local/state

# Begin deploy log. `mkdir` MUST precede the `tee` redirect so the first-ever
# run on a fresh machine doesn't fail with "no such file or directory".
mkdir -p $XDG_STATE_HOME
exec > >(tee -a "$XDG_STATE_HOME/dotfiles-deploy.log") 2>&1

# deploy.zsh prints ${deploy_only:-all}: zsh joins the array with spaces, so
# mirror that with [*] rather than bash's first-element ${deploy_only:-…}.
if (( ${#deploy_only[@]} > 0 )); then
    _only_display=${deploy_only[*]}
else
    _only_display=all
fi
printf '%s\n' "=== deploy started at $(date -Iseconds) (upgrade_mode=$upgrade_mode dry_run=$DEPLOY_DRY_RUN force=$DEPLOY_FORCE only=$_only_display) ==="

export DOTFILES_OS=$(uname -s)
export DOTFILES_ARCH=$(uname -m)
export upgrade_mode

# Load shared helpers (ensure_homebrew_path, brew_install_or_upgrade,
# brew_cask_install_or_upgrade, brew_formula_install_or_upgrade,
# configure_iterm2_profile).
source $SCRIPT_DIR/scripts/deploy.d/lib/helpers.zsh

# Fire fragments in numeric order. The lib/ subdir is excluded since its name
# doesn't begin with a digit. Filter to --only NAME if given; the case-based
# membership test replaces zsh's ${deploy_only[(r)…]} reverse index.
shopt -s nullglob
for fragment in "$SCRIPT_DIR"/scripts/deploy.d/[0-9]*.zsh; do
    _base=${fragment##*/}
    _frag_name=${_base%.zsh}
    if (( ${#deploy_only[@]} > 0 )); then
        _matched=0
        for _name in "${deploy_only[@]}"; do
            [[ $_name == "$_frag_name" ]] && _matched=1
        done
        (( _matched )) || continue
    fi
    printf '%s\n' "==> $_base"
    if ! source "$fragment"; then
        printf '%s\n' "FAILED: $_base" >&2
        exit 1
    fi
done

printf '%s\n' "=== deploy finished at $(date -Iseconds) ==="
