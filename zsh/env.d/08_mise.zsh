# XDG-compliant mise configuration (polyglot runtime manager)
export MISE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mise"
export MISE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
export MISE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mise"
export MISE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mise"

# Add mise shims to PATH for non-interactive shells and scripts.
# Full hook-based activation happens in rc.d/22_mise.zsh for interactive shells.
[[ -d "$MISE_DATA_DIR/shims" ]] && path=("$MISE_DATA_DIR/shims" $path)
