# XDG-compliant mise configuration (polyglot runtime manager)
export MISE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mise"
export MISE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
export MISE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mise"
export MISE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mise"

# Add mise shims to PATH for non-interactive shells and scripts.
# Full hook-based activation happens in rc.d/22_mise.zsh for interactive shells.
[[ -d "$MISE_DATA_DIR/shims" ]] && path_prepend "$MISE_DATA_DIR/shims"

# Direct symlinks to static CLI binaries, built by deploy.d/51_mise_fastbin.zsh.
# Prepended AFTER the shims line so it lands AHEAD of it — path_prepend moves an
# entry to the front, so the last call wins. Everything not in fastbin still
# falls through to the shim behind it, keeping per-project runtime switching.
# Measured ~5x on tool invocation in non-interactive shells; see the fragment
# header for the full rationale and the numbers.
[[ -d "$MISE_DATA_DIR/fastbin" ]] && path_prepend "$MISE_DATA_DIR/fastbin"

# GitHub token — lifts mise's GitHub-release version-resolution rate limit
# from 60/hr (unauthenticated) to 5000/hr. Read from gh's keyring so it stays
# in sync with `gh auth login` rotations. Skipped if already exported (e.g. CI).
# The inner `if` ensures a missing/failed `gh auth token` doesn't make this
# whole file exit non-zero — .zshenv reports any non-zero source as an error.
#
# THE LOOKUP MUST BE BOUNDED. `gh auth token` reads the macOS keychain, and in
# a context with no UI it does not fail — it blocks forever waiting for a
# keychain prompt that can never be displayed. Measured 2026-09-11: every
# `zsh -c` LaunchAgent on neptune hung in run_init_scripts with a live
# `gh auth token` child, holding a pid, writing no log and never retrying.
# The guard above catches a FAILING gh, not a HANGING one, and a hung agent is
# invisible to a `launchctl list` glance.
#
# Note the PATH asymmetry that makes this reachable at all: `gh` is a mise
# shim, and the shims were prepended a few lines above, so gh IS on PATH under
# launchd — while `timeout`/`gtimeout` live in /usr/local/bin, which launchd's
# default PATH (/usr/bin:/bin:/usr/sbin:/sbin) excludes. So the tiers below
# resolve to "skip" exactly in the launchd case, which is the one that hangs.
#
# Tiers: bound it if we can; otherwise only risk an unbounded call when a
# human is attached (interactive => keychain unlocked, a prompt can resolve);
# otherwise skip. `case $- in *i*` and not `[[ -o interactive ]]`: the latter
# is unconditionally false under bash, which silently inverts the gate
# (CLAUDE.md, zsh-vs-bash foot-guns). Regression-tested by
# scripts/tests/macos-permissions-gate.sh.
if [[ -z ${GITHUB_TOKEN:-} ]] && command -v gh >/dev/null 2>&1; then
    _gh_timeout=
    if command -v timeout >/dev/null 2>&1; then
        _gh_timeout=timeout
    elif command -v gtimeout >/dev/null 2>&1; then
        _gh_timeout=gtimeout
    fi
    _gh_token=
    if [[ -n $_gh_timeout ]]; then
        _gh_token=$("$_gh_timeout" 5 gh auth token 2>/dev/null) || _gh_token=
    else
        case $- in
            *i*) _gh_token=$(gh auth token 2>/dev/null) || _gh_token= ;;
        esac
    fi
    [[ -n $_gh_token ]] && export GITHUB_TOKEN=$_gh_token
    unset _gh_token _gh_timeout
fi
