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
| npm global package (pnpm, tsx, AI CLIs, …) | `.default-npm-packages` (installed via mise node's npm by `scripts/deploy.d/70_runtime_installs.zsh`) |
| CLI tool with mise registry backend | `configs/mise.toml` → `[tools]` (preferred — aqua/cargo backends covered for ~13 common CLIs already) |
| Cargo CLI without mise backend (e.g. linear-cli) | `scripts/deploy.d/70_runtime_installs.zsh` |
| Binary via curl/download | new fragment in `scripts/deploy.d/`, or extend an existing one |
| Tool as git submodule | `tools/` → add submodule, link in `scripts/deploy.d/40_tools.zsh` |
| Homebrew formula/cask (macOS-only) | `scripts/deploy.d/75_brew_setup.zsh` |
| brew fallback for mise-installed tool | `scripts/deploy.d/50_mise.zsh` → fallback loop |
| zsh function | `zsh/fpath/` → create file, autoload in `rc.d/04_autoload.zsh` |
| cross-shell CLI wrapper (bash+zsh) | `bin/` → executable; link in `scripts/deploy.d/21_bash_symlinks.zsh` (~/.local/bin) |
| bash function (must cd the caller) | `bash/fpath.d/` → sourced by `.bashrc` (w, fz, ineachdir) |
| AI/LLM tool config | `configs/ai/<tool>/` (claude-code, codex, codewhale, opencode, omx, ccr-router, portkey, litellm, agent-orchestrator) |
| Keybindings / GUI nav / tiling WM | macOS: `configs/karabiner/karabiner.ts` (Hyper + text nav, generated) + `configs/aerospace/aerospace.toml` (tiling). Linux: `configs/keyd/default.conf` (Caps→Esc/Hyper, installed to /etc by `79_keyd.zsh`) + `configs/sway/config` (tiling). Full guide: [`docs/keybindings/README.md`](docs/keybindings/README.md) |
| macOS App Shortcuts / Finder `defaults` / default-app associations | `scripts/macos/macos-defaults.sh` (shortcuts + Finder prefs + `duti` file-type→VS Code; change-aware, backs up to `$XDG_STATE_HOME/macos-defaults/`; applied on deploy by `77_macos_defaults.zsh`, needs `duti` from brew). Capture hand-set shortcuts with `capture-shortcuts.sh`. See [`scripts/macos/README.md`](scripts/macos/README.md) |
| macOS Raycast script command | drop a `*.sh` in `raycast/` (version-controlled; add the dir once in Raycast settings). See [`raycast/README.md`](raycast/README.md) |

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
**Encryption**: `./scripts/save-secrets.zsh` skips overwriting a newer `.enc` (and skips when content already matches) unless `--force`
**Decryption**: `./scripts/restore-secrets.zsh` writes plaintext from tracked `.enc`, but skips a plaintext that is newer than its `.enc` unless `--force` (so local edits aren't clobbered)
**On deploy**: `scripts/deploy.d/65_sops.zsh` restores `ssh/*.enc` with the same date guard; `./deploy.zsh --force` (`DEPLOY_FORCE=1`) overrides it

## Runtime Management (mise)
mise owns ALL runtimes — including Node/npm — plus non-npm CLIs. npm globals
live in `.default-npm-packages` and install through mise node's npm (deploy
fragment `70_runtime_installs.zsh`, and mise's own default-packages hook on
node installs). Never reintroduce a second node manager: systemd units resolve
node through mise shims, and a split-brain (interactive node ≠ service node)
crash-looped three services for a week in 2026-07.
- `npm ls -g --depth=0` — show npm globals installed through mise node's npm
- `mise install` — install all tools defined in config
- `mise ls` — show installed tools and versions
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
- Don't edit anything under `plugins/` or `tools/` — those are submodules

## Structure
```
├── deploy.zsh          # Main installer + git hooks
├── scripts/
│   ├── save-secrets.zsh         # Manual secrets save into tracked .enc files
│   ├── restore-secrets.zsh      # Manual secrets restore from tracked .enc files
│   ├── deploy.d/                # NN_*.zsh install fragments (sourced in order)
│   └── macos/                   # macOS settings: defaults + shortcut capture (README inside)
├── configs/
│   ├── mise.toml       # Global runtime versions (bun, ruby, python, sops, age)
│   ├── karabiner/      # macOS: karabiner.ts → generated karabiner.json (Hyper, text nav)
│   ├── aerospace/      # macOS: aerospace.toml → tiling WM (symlinked)
│   ├── keyd/           # Linux: default.conf → /etc/keyd (Caps→Esc/Hyper, via 79_keyd.zsh)
│   └── sway/           # Linux: config → tiling WM (symlinked)
├── docs/
│   └── keybindings/    # README + printable cheat sheet (keyboard/nav/GUI/WM)
├── zsh/
│   ├── .zshenv         # Entry point, sets ZDOTDIR
│   ├── env.d/          # ALL shells, BOTH zsh and bash (export PATH, XDG vars, mise shims)
│   ├── rc.d/           # Interactive zsh only (plugins, completions, prompts)
│   └── fpath/          # Autoloaded functions (evalcache, dotfiles-encrypt, etc.)
├── bash/               # Opt-in bash twin (zsh stays default; 21_bash_symlinks)
│   ├── env.sh          # Shared env entrypoint: sources zsh/env.d/* + exports BASH_ENV
│   ├── rc.d/           # Interactive bash only (history/setopt/gnubin/completion/paseo)
│   ├── fpath.d/        # Sourced functions that cd the caller (w, fz, ineachdir)
│   └── inputrc         # readline config ($INPUTRC, zero home presence)
├── bin/                # Cross-shell CLI wrappers (cc, psg, lspath, …) → ~/.local/bin
├── nvim/               # Lua config (0.11.0+): mini.nvim, mason, blink.cmp
├── tmux/               # Solarized, vim-aware pane nav
├── yazi/               # Yazi file manager config + plugins
├── raycast/            # macOS: Raycast script commands (add dir in Raycast settings)
└── tools/              # git-diff-pager + vendored submodules
```
(Vim was removed — Neovim is the only editor.)
