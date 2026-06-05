<!-- Generated: 2026-02-17; updated 2026-05-22 -->

# dotfiles

XDG-compliant zsh/neovim/tmux dotfiles. All external code is git submodules (~80). Solarized Dark everywhere. Vim configuration was removed — Neovim is the only editor.

## Commands
- `./deploy.zsh` — full install dispatcher; sources fragments from `scripts/deploy.d/NN_*.zsh` in numeric order
  - `--upgrade` / `-u` — also run brew/mise/cargo upgrades
  - `--dry-run` / `-n` — fragments print intentions without mutating
  - `--only NAME` — run only fragments whose basename matches NAME (repeatable)
- `scripts/eris-macos-bootstrap.zsh` — Day-0 macOS bootstrap (run BEFORE clone via `curl | zsh`); installs Homebrew + baseline, then clones and runs deploy
- `./scripts/save-secrets.zsh` — encrypt plaintext override secrets back into tracked `.enc` files
- `./scripts/restore-secrets.zsh` — decrypt tracked `.enc` files back to plaintext overrides
- Deploy runs automatically on `git pull` via `scripts/post-merge` (guards: `zsh -n` precheck, `timeout 300`, `DOTFILES_SKIP_POSTMERGE=1` opt-out)
- `dotfiles-encrypt <file>` — encrypt a secrets file (autoloaded function; honors `.sops.yaml` recipients)

## Where to Add Commands/Tools
| Want to add... | Location |
|----------------|----------|
| Runtime (ruby, python, bun, etc.) | `configs/mise.toml` → `[tools]` section |
| Node/npm/vp/pnpm or npm global package | `.default-npm-packages` plus `scripts/deploy.d/70_runtime_installs.zsh` |
| CLI tool with mise registry backend | `configs/mise.toml` → `[tools]` (preferred — aqua/cargo backends covered for ~13 common CLIs already) |
| Cargo CLI without mise backend (e.g. linear-cli) | `scripts/deploy.d/70_runtime_installs.zsh` |
| Binary via curl/download | new fragment in `scripts/deploy.d/`, or extend an existing one |
| Tool as git submodule | `tools/` → add submodule, link in `scripts/deploy.d/40_tools.zsh` |
| Homebrew formula/cask (macOS-only) | `scripts/deploy.d/75_brew_setup.zsh` |
| brew fallback for mise-installed tool | `scripts/deploy.d/50_mise.zsh` → fallback loop |
| zsh function | `zsh/fpath/` → create file, autoload in `rc.d/04_autoload.zsh` |
| AI/LLM tool config | `configs/ai/<tool>/` (claude-code, codex, opencode, omx, ccr-router, portkey, litellm, agent-orchestrator) |

## Secrets Encryption (SOPS + Age)
Files in the 90-99 range are gitignored and can hold secrets. Encrypt with `dotfiles-encrypt`:

```bash
# Create a secrets file
echo 'export MY_API_KEY="..."' > zsh/env.d/90_secrets.zsh
# Encrypt it (creates 90_secrets.zsh.enc)
./scripts/save-secrets.zsh
# Restore plaintext later if needed
./scripts/restore-secrets.zsh
```

**Key location**: `~/.config/sops/age/keys.txt` — **BACKUP THIS FILE** to your password manager!
**Encrypted file pattern**: `zsh/env.d/9[0-9]_*.enc`, `zsh/rc.d/9[0-9]_*.enc`, `nvim/init/9[0-9]_*.enc`
**Encryption**: `./scripts/save-secrets.zsh` skips overwriting newer `.enc` files unless `--force`
**Decryption**: `./scripts/restore-secrets.zsh` overwrites plaintext files from tracked `.enc` secrets on demand

## Runtime Management (Vite+ + mise)
Vite+ owns Node/npm/vp/pnpm and npm global packages. mise owns the remaining
polyglot runtimes and non-npm CLIs. See `configs/mise.toml` and
`.default-npm-packages`.
- `vp env doctor` — verify Vite+'s Node/npm shims
- `npm ls -g --depth=0` — show npm globals installed through Vite+'s npm
- `mise install` — install all non-npm tools defined in config
- `mise ls` — show installed tools and versions
- **Config**: `configs/mise.toml` → symlinked to `~/.config/mise/config.toml`
- **env.d/08_mise.zsh**: Sets XDG paths, adds shims to PATH (all shells)
- **env.d/09_vite_plus.zsh**: Sources `~/.vite-plus/env` (all shells)
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
- Don't edit anything under `plugins/` or `tools/` — those are submodules

## Structure
```
├── deploy.zsh          # Main installer + git hooks
├── scripts/
│   ├── save-secrets.zsh         # Manual secrets save into tracked .enc files
│   └── restore-secrets.zsh      # Manual secrets restore from tracked .enc files
├── configs/
│   └── mise.toml       # Global runtime versions (bun, ruby, python, sops, age)
├── zsh/
│   ├── .zshenv         # Entry point, sets ZDOTDIR
│   ├── env.d/          # ALL shells (export PATH, XDG vars, mise shims)
│   ├── rc.d/           # Interactive only (plugins, completions, prompts)
│   └── fpath/          # Autoloaded functions (evalcache, dotfiles-encrypt, etc.)
├── nvim/               # Lua config (0.11.0+): mini.nvim, mason, blink.cmp
├── vim/                # Legacy VimScript (deprecated)
├── tmux/               # Solarized, vim-aware pane nav
└── tools/              # fzf, diff-so-fancy, git-extras (submodules)
```
