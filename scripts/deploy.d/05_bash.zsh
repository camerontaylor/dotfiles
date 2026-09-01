# Hoist a modern bash ahead of fragments 10–74 (docs/bash-compatibility.md §E).
#
# This install used to live in 75_brew_setup.zsh — i.e. AFTER every fragment
# that might shell out to bash — the same path-dependent skew CLAUDE.md
# documents for BSD userland: on the README's `git clone && ./deploy.zsh`
# path, fragments ≤74 resolved `bash` to /bin/bash 3.2 even on boxes that end
# the deploy with brew 5.x. macOS ships bash 3.2.57 (frozen at the last GPLv2
# release); installing 5.x unlocks associative arrays, mapfile, ${var^^},
# globstar, etc. for any script using `#!/usr/bin/env bash`.
#
# /bin/bash 3.2 is the floor and is always present on macOS, so this is a
# guarded no-op whenever Homebrew is unreachable (and on Linux, where the
# distro bash is already 5.x). Not registered in /etc/shells — zsh remains
# the login shell (DOTFILES_SHELL in 75_brew_setup.zsh is the opt-out knob).

if [[ $DOTFILES_OS == Darwin ]] && ensure_homebrew_path; then
    printf '%s\n' "Installing modern bash via brew..."
    brew_formula_install_or_upgrade bash || true
fi
