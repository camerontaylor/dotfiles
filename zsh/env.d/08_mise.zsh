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
if [[ -z ${GITHUB_TOKEN:-} ]] && command -v gh >/dev/null 2>&1; then
    if _gh_token=$(gh auth token 2>/dev/null); then
        export GITHUB_TOKEN=$_gh_token
    fi
    unset _gh_token
fi
