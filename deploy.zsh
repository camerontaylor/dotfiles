#!/usr/bin/env zsh
# Dotfiles deployer. Run by hand or auto-invoked by scripts/post-merge after
# every `git pull`. The actual install logic lives in scripts/deploy.d/NN_*.zsh
# (sourced in numeric order); shared helpers live in scripts/deploy.d/lib/.
#
# Usage: ./deploy.zsh [--upgrade|-u] [--dry-run|-n] [--only NAME ...]
#
# Fragment numbering convention (current layout):
#   05  bash           — hoist a modern brew bash ahead of fragments ≤74 (§E)
#   10  dirs           — XDG dirs, $HOME scaffolding
#   20  symlinks       — link zsh/git/tmux/nvim configs into $HOME
#   30  submodules     — `git submodule update --init`
#   40  tools          — build/install submoduled tools (fzf, diff-so-fancy, …)
#   50  mise           — bootstrap mise, install all `configs/mise.toml` tools
#   55  evalcache_prune — purge poisoned 0-byte zsh evalcache files (recovery)
#   60  git_hooks      — post-merge / pre-commit hooks
#   65  sops           — age/sops setup, decrypt env secrets
#   66  infra          — ensure ~/.local/infra sibling (clone/pull + its deploy)
#   70  runtime_installs — curl-installed CLIs without a mise backend
#   75  brew_setup     — brew formulae and casks
#   80  nvim_post      — post-symlink nvim setup
#   85  verify_tools   — smoke-test that mise/brew-installed binaries actually run
#   90  p10k_warmup    — pre-warm powerlevel10k caches
#   99  periodic       — install daily auto-pull (systemd/launchd/cron)
#
# History: this file was a 1129-line monolith. It now dispatches into
# fragments so each install concern can be reviewed/edited in isolation.

# typeset_silent: fragments are SOURCED into one shared shell, so a fragment's
# top-level `local` is really just `typeset` and leaves the name set globally.
# Without this option zsh *prints* any name that typeset re-declares while it
# already holds a value, so 82_zsh_completions leaking `entry`/`tool` made
# 85_verify_tools spray "entry='...'" into a real deploy's output. Only ever
# visible on a real run: --dry-run skips the loop that assigns them.
setopt extended_glob err_exit typeset_silent

# ── Version floor assert (docs/bash-compatibility.md §E) ──────────────────
# Fragments ≤74 and both drivers must run on the fleet's oldest shell, so the
# floor is /bin/bash 3.2 (macOS stock). Anything older/missing fails loud
# instead of half-running the deploy. Dual-parseable: deploy.bash carries the
# same block.
_bash_version=$(/bin/bash --version 2>/dev/null | head -n 1)
_bash_version=${_bash_version#*version }
_bash_major=${_bash_version%%.*}
_bash_minor=${_bash_version#*.}
_bash_minor=${_bash_minor%%.*}
case $_bash_major in (''|*[!0-9]*) _bash_major=0 ;; esac
case $_bash_minor in (''|*[!0-9]*) _bash_minor=0 ;; esac
if (( _bash_major < 3 )) || { (( _bash_major == 3 )) && (( _bash_minor < 2 )); }; then
    print "FATAL: /bin/bash is version $_bash_major.$_bash_minor; this deploy needs >= 3.2" >&2
    exit 2
fi
unset _bash_version _bash_major _bash_minor

# Argument parsing — fail-closed on unknown flags or missing --only value.
local upgrade_mode=false
export DEPLOY_DRY_RUN=0
# Escape hatch for fragment-level safety guards. It originally bypassed the
# mtime/clobber date guards in 65_sops.zsh; that fragment was retired by the
# secrets-repo migration, and its replacement (65_secrets.zsh) deliberately
# has no guards to bypass — ciphertext is canonical, plaintext is derived, so
# re-rendering is always correct. No fragment reads DEPLOY_FORCE today; the
# flag is kept as a stable interface for future guarded fragments.
export DEPLOY_FORCE=0
typeset -ga deploy_only=()
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
                print "FATAL: --only requires a value (fragment basename without .zsh)" >&2
                exit 2
            fi
            deploy_only+=("$2")
            shift
            ;;
        --help|-h)
            print "usage: deploy.zsh [--upgrade|-u] [--dry-run|-n] [--force|-f] [--only NAME ...]"
            print ""
            print "  --upgrade    run brew/mise/cargo upgrades in addition to installs"
            print "  --dry-run    fragments print intentions via [dry-run] without mutating"
            print "  --force      bypass fragment safety guards (no fragment reads it"
            print "               today; secrets rendering is unconditional)"
            print "  --only NAME  run only fragments whose basename matches NAME"
            print "               (e.g., --only 30_submodules); repeat for multiple"
            exit 0
            ;;
        *)
            print "FATAL: unknown argument: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

zmodload -m -F zsh/files b:zf_\*

SCRIPT_DIR=${0:A:h}
# with systemd-homed `a`/`A` expands to storage location `/home/username.homedir`
# instead of mounted location `/home/username` — massage SCRIPT_DIR back.
if [[ $SCRIPT_DIR == $HOME.homedir* ]]; then
    SCRIPT_DIR=${SCRIPT_DIR/.homedir/}
fi
cd $SCRIPT_DIR
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
print "=== deploy started at $(date -Iseconds) (upgrade_mode=$upgrade_mode dry_run=$DEPLOY_DRY_RUN force=$DEPLOY_FORCE only=${deploy_only:-all}) ==="

export DOTFILES_OS=$(uname -s)
export DOTFILES_ARCH=$(uname -m)
export upgrade_mode

# Load shared helpers (ensure_homebrew_path, brew_install_or_upgrade,
# brew_cask_install_or_upgrade, brew_formula_install_or_upgrade,
# configure_iterm2_profile).
source $SCRIPT_DIR/scripts/deploy.d/lib/helpers.zsh

# Fire fragments in numeric order. The lib/ subdir is excluded since its name
# doesn't begin with a digit. Filter to --only NAME if given.
local fragment_glob='[0-9]*.zsh'
for fragment in $SCRIPT_DIR/scripts/deploy.d/$~fragment_glob(N); do
    local frag_name=${fragment:t:r}
    if (( ${#deploy_only} > 0 )) && [[ -z ${deploy_only[(r)${frag_name}]:-} ]]; then
        continue
    fi
    print "==> ${fragment:t}"
    if ! source $fragment; then
        print "FAILED: ${fragment:t}" >&2
        exit 1
    fi
done

print "=== deploy finished at $(date -Iseconds) ==="
