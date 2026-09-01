# Post-install nvim housekeeping: helptags, treesitter parsers, mason
# registries. All gated by `command -v nvim`.

if have nvim; then
    printf '%s\n' "Generating nvim helptags..."
    command nvim --headless -c "helptags ALL" -c "qall" &> /dev/null
    printf '%s\n' "  ...done"

    printf '%s\n' "Updating tree-sitter parsers..."
    command nvim --headless -c "TSUpdate" -c "qall" &> /dev/null
    printf '%s\n' "  ...done"

    printf '%s\n' "Updating mason registries..."
    command nvim --headless -c "MasonUpdate" -c "qall" &> /dev/null
    printf '%s\n' "  ...done"
fi
