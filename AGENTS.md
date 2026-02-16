<!-- Generated: 2026-02-17 -->

# dotfiles

XDG-compliant zsh/neovim/vim/tmux dotfiles. All external code is git submodules (~145). Solarized Dark everywhere.

## Commands
- `./deploy.zsh` — full install: create dirs, symlink configs, sync submodules, install tools
- Deploy runs automatically on `git pull` (post-merge/post-checkout hooks)

## How to Add Things
- **New zsh env var**: `zsh/env.d/NN_name.zsh` (runs for ALL shells, keep fast)
- **New zsh rc config**: `zsh/rc.d/NN_name.zsh` (interactive only, see `zsh/AGENTS.md` for numbering)
- **New zsh function**: create file in `zsh/fpath/`, add `autoload -Uz name` in `rc.d/04_autoload.zsh`
- **New cargo tool**: add to `rust_tools` array in `deploy.zsh` (~line 157)
- **New submodule tool**: `git submodule add <url> tools/<name>`, add install logic to `deploy.zsh`
- **New nvim plugin**: submodule in `nvim/plugins/`, config in `nvim/init/NN_name.lua`
- **Local overrides**: 90-99 prefix files are gitignored (zsh/env.d/, zsh/rc.d/, nvim/init/)

## Conventions
- Feature detection: `(( ${+commands[tool]} ))` with modern-first fallbacks (eza>ls, zoxide>z, bat>cat, delta>diff-so-fancy, fd>find, nvim>vim)
- Numbered file prefixes control load order; `zz_*` runs last
- Non-critical zsh plugins deferred via `zsh-defer` (rc.d/24-27)
- Language version managers (pyenv, rbenv, etc.) lazy-loaded via `evalcache`
- All configs symlinked to XDG locations by `deploy.zsh`; never place files directly in `~/.config/`
- Don't edit anything under `plugins/`, `tools/`, or `env-wrappers/` — those are submodules

## Structure
- `zsh/` — shell config: `.zshenv` -> `env.d/*`, `.zshrc` -> `rc.d/*`, custom functions in `fpath/`
- `nvim/` — Lua config (0.11.0+): mini.nvim ecosystem, mason LSP, blink.cmp completion
- `vim/` — legacy VimScript config (deprecated), 73 plugins via native packages
- `tmux/` — tmux with Solarized, vim-aware pane nav, top status bar
- `configs/` — git, ghostty, tig, htop, ranger, yazi, gem configs
- `tools/` — fzf, diff-so-fancy, git-extras, etc. (submodules)
- `env-wrappers/` — goenv, jenv, luaenv, nodenv, nvm, phpenv, plenv, pyenv, rbenv
- `deploy.zsh` — the installer and git hook; auto-installs rustup, cargo tools, fzf, wtp
