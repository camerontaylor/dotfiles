<!-- Generated: 2026-02-17; updated 2026-05-22 -->

# dotfiles

XDG-compliant zsh/neovim/tmux dotfiles. All external code is git submodules (~80). Solarized Dark everywhere. Vim configuration was removed — Neovim is the only editor.

## Commands
- `./deploy.zsh` — full install dispatcher; sources fragments from `scripts/deploy.d/NN_*.zsh` in numeric order
  - `--upgrade` / `-u` — also run brew/mise/cargo upgrades
  - `--dry-run` / `-n` — fragments print intentions without mutating
  - `--only NAME` — run only fragments whose basename matches NAME (repeatable)
- `./deploy.bash` — bash twin of the driver: same CLI, same fragments (fragment bodies are dual-shell by contract); both drivers assert `/bin/bash` ≥ 3.2 at startup
- `scripts/eris-macos-bootstrap.zsh` — Day-0 macOS bootstrap (run BEFORE clone via `curl | zsh`); installs Homebrew + baseline, then clones and runs deploy
- `secrets-edit <path>` — edit a secret in the private secrets repo, then re-render this box (autoloaded function; `secrets-edit` with no args lists what is editable)
- Deploy runs automatically on `git pull` via `scripts/post-merge` (prefers `deploy.zsh`, falls back to `deploy.bash` — each `-n`-checked before running, loud failure when neither is runnable; `timeout 300`, `DOTFILES_SKIP_POSTMERGE=1` opt-out)
- CI: `.github/workflows/shells.yml` — macOS + Ubuntu matrix running the tree-wide dual `-n` sweep (`scripts/tests/shell-syntax-gate.sh`, the same gate `scripts/pre-commit` runs over staged files), and both drivers' `--dry-run` with `DOTFILES_SKIP_BREW=1` (no brew installs on hosted runners; macOS `/bin/bash` 3.2 is the floor leg)

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
| Deployed service (compose file, units, install steps) | `configs/<service>/` for the tracked artifacts + `scripts/setup-<service>.sh` for the idempotent installer + `docs/<service>.md` for the runbook. Hand-run only — **never** wire one into `scripts/deploy.d/`, since the fleet auto-deploys on every pull and two of three boxes are Macs. Models: `setup-caddy.sh`, `setup-paseo.sh`, `setup-immich.sh`. **This is an interim home — see [Infra carve-out](#todo-infra-carve-out) below.** |

## Secrets Encryption (SOPS + Age)
**No secret material lives in this repo.** Ciphertext is canonical, plaintext is derived: encrypted material lives in the private repo `camerontaylor/dotfiles-secrets`, cloned to `~/.local/secrets`. Rendered shell exports live *outside* every worktree at `$XDG_STATE_HOME/secrets/zsh/9*.zsh` (600), sourced by the tracked `zsh/env.d/89_secrets_loader.zsh` — which is numbered 89 so a deliberate local `90-99` override still sorts after it and wins.

```bash
secrets-edit shell/90_secrets.yaml    # sops edit, then re-render this box
git -C ~/.local/secrets commit -am "chore: add MY_API_KEY"
git -C ~/.local/secrets push          # other boxes render it on their next pull
```

**Key location**: `~/.config/sops/age/keys.txt` — **BACKUP THIS FILE** to your password manager!
**On deploy**: `scripts/deploy.d/65_secrets.zsh` clones/pulls `~/.local/secrets` and drives `scripts/secrets-render.zsh`, which renders every target for this box. There are deliberately **no mtime/clobber guards** — re-rendering derived plaintext is always correct — so `--force`/`DEPLOY_FORCE` does not affect secrets at all.
**Degraded mode**: a box missing the age key or GitHub read access prints an instruction block and mutates nothing; deploy stays green. `zsh/rc.d/33_secrets_staleness.zsh` warns in new interactive shells after 14 days without a render.
**Never** edit a rendered file directly (`$XDG_STATE_HOME/secrets/zsh/*`, `ssh/*`, `configs/portless/*.pem`) — the next deploy overwrites it.

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
- **New cargo tool**: add to the cargo block in `scripts/deploy.d/70_runtime_installs.zsh` (no mise backend? same place; if pkg name ≠ binary name, add a `case` mapping)
- **New submodule tool**: `git submodule add <url> tools/<name>`, add install logic to the matching `scripts/deploy.d/` fragment (e.g. `40_tools.zsh`)
- **New nvim plugin**: submodule in `nvim/plugins/`, config in `nvim/init/NN_name.lua`
- **Local overrides**: 90-99 prefix files are gitignored (zsh/env.d/, zsh/rc.d/, nvim/init/)
- **New secret**: add the key to the right `shell/*.yaml` in `~/.local/secrets` via `secrets-edit`, then commit+push there — **not** in this repo. A brand-new render *target* also needs a `_row` in `scripts/secrets-render.zsh`

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
- Feature detection: `have tool` (the `command -v` wrapper in `scripts/deploy.d/lib/helpers.zsh` — parses AND runs in both shells, unlike `${+commands[tool]}` which is always-false under bash) with modern-first fallbacks (eza>ls, zoxide>z, bat>cat, delta>diff-so-fancy, fd>find, nvim>vim)
- Non-critical zsh plugins deferred via `zsh-defer` (rc.d/24-27)
- Slow inits cached via `evalcache` (20h TTL, see `zsh/fpath/evalcache`)
- All configs symlinked to XDG locations by `deploy.zsh`; never place files directly in `~/.config/`
- Don't edit anything under `plugins/` or `tools/` — those are submodules

## Structure
```
├── deploy.zsh          # Main installer + git hooks
├── scripts/
│   ├── secrets-render.zsh       # Renders ~/.local/secrets → this box's plaintext targets
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
│   └── fpath/          # Autoloaded functions (evalcache, secrets-edit, etc.; each needs a line in rc.d/04_autoload.zsh)
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

## TODO: infra carve-out

Deployed-service infrastructure (`configs/immich/`, `configs/caddy/`,
`scripts/setup-*.sh`, `docs/immich.md`, `docs/caddy-ingress.md`, …) lives here
as an **interim home**. Cameron's intent (2026-09-03) is to split infra out of
dotfiles into its own repo, leaving this one to config *preferences* — shell,
editor, keybindings, terminal.

The precedent is the secrets carve-out: ciphertext moved to the private
`camerontaylor/dotfiles-secrets` in 2026-08 with `scripts/secrets-render.zsh`
as the seam. Infra should follow that shape — own repo, own lifecycle, defined
seam back to dotfiles.

Until then, keep new infra to the `configs/<service>/` + `scripts/setup-<service>.sh`
+ `docs/<service>.md` triple so the eventual move is a `git mv`, not a rewrite.
Full candidate list and rationale: [`docs/immich.md`](docs/immich.md#todo-carve-infra-out-of-dotfiles-into-its-own-repo).
