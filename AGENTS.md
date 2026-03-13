<!-- Generated: 2026-02-17; updated 2026-03-13 -->

# dotfiles

XDG-compliant zsh/neovim/vim/tmux dotfiles. All external code is git submodules (~145). Solarized Dark everywhere.

## Commands
- `./deploy.zsh` — full install: create dirs, symlink configs, sync submodules, install tools, decrypt secrets
- Deploy runs automatically on `git pull` (post-merge/post-checkout hooks)
- `sudo bash scripts/install-build-deps.sh` — install APT deps for compiling Ruby, Python, Node via env-wrappers
- `dotfiles-encrypt <file>` — encrypt a secrets file (autoloaded function)

## Where to Add Commands/Tools
| Want to add... | Location |
|----------------|----------|
| Rust CLI tool | `deploy.zsh` → `rust_tools` array (~line 276) |
| Runtime (node, ruby, python, etc.) | `configs/mise.toml` → `[tools]` section |
| npm global package | `configs/mise.toml` → `"npm:pkg-name" = "latest"` |
| APT build dependency | `scripts/install-build-deps.sh` → `PACKAGES` array |
| Binary via curl/download | `deploy.zsh` → add new `if (( ! ${+commands[tool]} ))` block |
| Tool as git submodule | `tools/` → add submodule, symlink in `deploy.zsh` |
| Homebrew package | `deploy.zsh` → brew section (~line 303) |
| zsh function | `zsh/fpath/` → create file, autoload in `rc.d/04_autoload.zsh` |

## Secrets Encryption (SOPS + Age)
Files in the 90-99 range are gitignored and can hold secrets. Encrypt with `dotfiles-encrypt`:

```bash
# Create a secrets file
echo 'export MY_API_KEY="..."' > zsh/env.d/90_secrets.zsh
# Encrypt it (creates 90_secrets.zsh.enc)
dotfiles-encrypt zsh/env.d/90_secrets.zsh
# Decrypt happens automatically on deploy
```

**Key location**: `~/.config/sops/age/keys.txt` — **BACKUP THIS FILE** to your password manager!
**Encrypted file pattern**: `zsh/env.d/9[0-9]_*.enc`, `zsh/rc.d/9[0-9]_*.enc`, `nvim/init/9[0-9]_*.enc`
**Decryption**: `deploy.zsh` lines 236-251 auto-decrypts `.enc` files when original is missing or stale

## Runtime Management (mise)
mise replaced nvm/rbenv/direnv for polyglot runtime management. See `configs/mise.toml`.
- `mise install` — install all tools defined in config
- `mise ls` — show installed tools and versions
- `mise use --global node@22` — change global node version
- **Config**: `configs/mise.toml` → symlinked to `~/.config/mise/config.toml`
- **env.d/08_mise.zsh**: Sets XDG paths, adds shims to PATH (all shells)
- **rc.d/22_mise.zsh**: `mise activate zsh` hook + pnpm completions (interactive)

## How to Add Things
- **New zsh env var**: `zsh/env.d/NN_name.zsh` (runs for ALL shells, keep fast)
- **New zsh rc config**: `zsh/rc.d/NN_name.zsh` (interactive only)
- **New zsh function**: create file in `zsh/fpath/`, add `autoload -Uz name` in `rc.d/04_autoload.zsh`
- **New cargo tool**: add to `rust_tools` array in `deploy.zsh` (~line 276); if pkg name ≠ binary name, add `case` mapping
- **New submodule tool**: `git submodule add <url> tools/<name>`, add install logic to `deploy.zsh`
- **New nvim plugin**: submodule in `nvim/plugins/`, config in `nvim/init/NN_name.lua`
- **Local overrides**: 90-99 prefix files are gitignored (zsh/env.d/, zsh/rc.d/, nvim/init/)
- **New secret**: create `90_*.zsh`, run `dotfiles-encrypt zsh/env.d/90_name.zsh`, commit only the `.enc` file

## File Numbering Conventions
| Range | Purpose |
|-------|---------|
| 00-09 | Core setup (tmux, options, history, paths) |
| 10-19 | Tools (lesspipe, grc, fzf, many-languages) |
| 20-29 | Plugins (autosuggestions, syntax-highlight, autopair) |
| 30-39 | Language-specific (wtp) |
| 90-99 | Local overrides (gitignored, can be encrypted) |
| zz_*  | Runs last (path sanitization) |

## Conventions
- Feature detection: `(( ${+commands[tool]} ))` with modern-first fallbacks (eza>ls, zoxide>z, bat>cat, delta>diff-so-fancy, fd>find, nvim>vim)
- Non-critical zsh plugins deferred via `zsh-defer` (rc.d/24-27)
- Slow inits cached via `evalcache` (20h TTL, see `zsh/fpath/evalcache`)
- All configs symlinked to XDG locations by `deploy.zsh`; never place files directly in `~/.config/`
- Don't edit anything under `plugins/`, `tools/`, or `env-wrappers/` — those are submodules

## Structure
```
├── deploy.zsh          # Main installer + git hooks (lines 236-251: secrets decrypt)
├── scripts/
│   └── install-build-deps.sh  # APT deps for env-wrappers (rbenv, pyenv, etc.)
├── configs/
│   └── mise.toml       # Global runtime versions (node, bun, ruby, python, sops, age)
├── zsh/
│   ├── .zshenv         # Entry point, sets ZDOTDIR
│   ├── env.d/          # ALL shells (export PATH, XDG vars, mise shims)
│   ├── rc.d/           # Interactive only (plugins, completions, prompts)
│   └── fpath/          # Autoloaded functions (evalcache, dotfiles-encrypt, etc.)
├── nvim/               # Lua config (0.11.0+): mini.nvim, mason, blink.cmp
├── vim/                # Legacy VimScript (deprecated)
├── tmux/               # Solarized, vim-aware pane nav
├── tools/              # fzf, diff-so-fancy, git-extras (submodules)
└── env-wrappers/       # goenv, jenv, pyenv, rbenv, etc. (submodules)
```
