# Vite+ owns vp plus Node/npm/pnpm shims. The installer-generated env file
# keeps vp's shell function in sync, but dotfiles owns where it is sourced.
if [[ -f "$HOME/.vite-plus/env" ]]; then
    . "$HOME/.vite-plus/env"
elif [[ -d "$HOME/.vite-plus/bin" ]]; then
    path=("$HOME/.vite-plus/bin" $path)
fi
