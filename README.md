# dotfiles

XDG-first dotfiles for a small fleet of machines — two Macs and a couple of
graphical Linux boxes (CachyOS desktop + laptop), plus headless servers. One
repo drives the shell, editor, terminal, **graphical desktop** (tiling WM +
keyboard remapping), and an extensive **AI/LLM tooling** layer, kept in sync
across every host by a single `deploy.zsh` (or its bash twin, `deploy.bash`).

Battle-tested on macOS and Linux (Debian/Ubuntu, Arch/CachyOS). On a headless
server the graphical bits are simply inert, so the same checkout works on a Mac
laptop and a remote box alike.

> Forked long ago from [z0rc/dotfiles](https://github.com/z0rc/dotfiles); the
> shell/Neovim/deploy bones are descended from it, the rest has diverged.

## License

[WTFPL](COPYING)

## Layout philosophy

Everything follows the [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/latest/):
configs live under `~/.config` (symlinked from the repo) and the **shell keeps a
near-zero `$HOME` footprint** — with `ZDOTDIR` set, not even `~/.zshenv` is
needed (see [Zero home presence](#zero-home-presence)). The exceptions are tools
that hardcode their own dotfile paths: the AI CLIs (`~/.claude`, `~/.codex`,
`~/.codewhale`, `~/.omx`, …) and a handful of app configs get their own `$HOME`
entries, all symlinked back into the repo by deploy.

All external code is vendored as **git submodules** (~48 of them — Neovim
plugins, zsh plugins, tmux/yazi/ranger plugins), so there's no plugin manager to
bootstrap.

## Features

* **Zsh** — [`zsh/`](zsh) (`env.d/` for all shells, `rc.d/` interactive only,
  `fpath/` autoloaded functions), with:
  * [powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt (instant prompt + warmed cache)
  * [zsh-completions](https://github.com/zsh-users/zsh-completions), [async autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [syntax highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
  * [autopair](https://github.com/hlissner/zsh-autopair), [zsh-z](https://github.com/agkozak/zsh-z) (+ zoxide), [fzf-tab](https://github.com/Aloxaf/fzf-tab), [zsh-abbr](https://github.com/olets/zsh-abbr), [you-should-use](https://github.com/MichaelAquilina/zsh-you-should-use), history-substring-search
  * non-critical plugins lazy-loaded via [zsh-defer](https://github.com/romkatv/zsh-defer); slow inits cached via `evalcache`
* **Neovim** — [`nvim/`](nvim) Lua config (0.11+): the [mini.nvim](https://github.com/echasnovski/mini.nvim) ecosystem, [blink.cmp](https://github.com/Saghen/blink.cmp) completion, [mason](https://github.com/williamboman/mason.nvim) + LSP, treesitter, [conform](https://github.com/stevearc/conform.nvim), Solarized, and [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) (Claude in-editor). Plugins are submodules under [`nvim/plugins/`](nvim/plugins) loaded via native `packpath` — no plugin manager.
* **Tmux** — [`tmux/`](tmux) Solarized, vim-aware pane nav, resurrect + continuum for session persistence across restarts.
* **Terminals** — [Ghostty](configs/ghostty) (primary) and [Waveterm](configs/waveterm).
* **File managers** — [Yazi](yazi) (primary) and [ranger](configs/ranger).
* **Keyboard, navigation & tiling window management** — one scheme on every
  machine: macOS via Karabiner + AeroSpace, Linux via keyd + Sway. See
  **[`docs/keybindings/README.md`](docs/keybindings/README.md)** (with a
  printable cheat sheet).
* **AI / LLM tooling** — [`configs/ai/`](configs/ai): Claude Code, Codex, CodeWhale,
  OpenCode, OMX, agent-orchestrator, and the Portkey / LiteLLM / CCR gateways.
  See [AI tooling](#ai--llm-tooling).
* **Other configs** — [Git](configs/gitconfig), [tig](configs/tigrc), [htop](configs/htoprc), [btop](configs/btop.conf), [bat](configs/bat), [quilt](configs/quiltrc), [starship](configs/starship.toml) (available as a p10k alternative).
* **Runtime/tool management** — [mise](https://mise.jdx.dev/) for polyglot
  runtimes and CLIs ([`configs/mise.toml`](configs/mise.toml)), including Node
  and the npm globals in [`.default-npm-packages`](.default-npm-packages).
  See [Runtime management](#runtime-management).
* **Networking** — Tailscale mesh join ([`73_tailscale.zsh`](scripts/deploy.d/73_tailscale.zsh))
  and wake-peers screen-wake fanout for Universal Control across the Macs.
* **Secrets** — SOPS + age, see [Secrets](#secrets).

## Keyboard, GUI & window management

A single keyboard scheme spans every machine, built on four disjoint modifier
planes (Cmd = native macOS, Ctrl = emacs/terminal nav, Hyper = Caps Lock launch
layer, Alt/Super = tiling WM). It's implemented by **Karabiner + AeroSpace** on
macOS and **keyd + Sway** on Linux, with Super sitting where `⌥` does on a Mac so
the planes stay 1:1.

Full write-up, per-binding tables, and a printable cheat sheet:
**[`docs/keybindings/README.md`](docs/keybindings/README.md)**.

## AI / LLM tooling

[`configs/ai/`](configs/ai) holds configs for the AI CLIs and gateways used
across the fleet, each symlinked to the `$HOME`/XDG path its tool expects:

| Tool | Config dir | Lands at |
|------|-----------|----------|
| Claude Code (+ oh-my-claudecode) | `configs/ai/claude-code/` | `~/.claude/` |
| Codex (+ OMX) | `configs/ai/codex/` | `~/.codex/` |
| CodeWhale | `configs/ai/codewhale/` | `~/.codewhale/` |
| OMX | `configs/ai/omx/` | `~/.omx/` |
| OpenCode | `configs/ai/opencode/` | `~/.config/opencode/` |
| agent-orchestrator | `configs/ai/agent-orchestrator/` | `~/.agent-orchestrator*` |
| Portkey gateway | `configs/ai/portkey/` | systemd user service |
| LiteLLM / CCR router | `configs/ai/litellm/`, `configs/ai/ccr-router/` | shell-integrated |

In Neovim, [CodeCompanion](nvim/init/17_llm.lua) provides Claude in-editor.
Add a new AI tool config under `configs/ai/<tool>/` and a symlink in
[`20_symlinks.zsh`](scripts/deploy.d/20_symlinks.zsh).

## Runtime management

One manager owns runtimes (see [`AGENTS.md`](AGENTS.md) for the full table):

* **mise** ([`configs/mise.toml`](configs/mise.toml)) owns Node (and npm/npm
  globals via [`.default-npm-packages`](.default-npm-packages)), polyglot
  runtimes (Python, Ruby, Bun, …) and non-npm CLIs (ripgrep, fd, bat, eza, sd,
  zoxide, fzf, sops, age, …). It's the source of truth for tool versions, and
  its shims dir is the ONE tool PATH shared by interactive shells and systemd
  units alike.
* **Homebrew** (macOS only, [`75_brew_setup.zsh`](scripts/deploy.d/75_brew_setup.zsh))
  provides the GNU userland, casks (Ghostty, fonts, AeroSpace, Karabiner,
  JankyBorders), and the `engram` tap — i.e. only what mise can't deliver.

## Installation

> [!NOTE]
> Neovim is the only supported editor — Vim has been removed. On a remote
> server without Neovim, install `nvim` via your package manager or `mise`.

### Requirements

* `zsh` 5.9 or newer strongly recommended
* `git` — all external components are git submodules

### Install

Dotfiles can live anywhere; I use `$HOME/.local/dotfiles`:

```sh
git clone https://github.com/camerontaylor/dotfiles.git "$HOME/.local/dotfiles"
"$HOME/.local/dotfiles/deploy.zsh"
command -v brew >/dev/null 2>&1 && chsh -s "$(brew --prefix)/bin/zsh"  # macOS/Homebrew zsh
```

Deploy pins brew's zsh as the login shell on macOS. To keep a different
one, run `DOTFILES_SHELL=/bin/bash "$HOME/.local/dotfiles/deploy.zsh"` (or
`export DOTFILES_SHELL=…` before the post-merge hook's auto-deploys): with
the knob set, `chsh` only ever targets that path and only when it exists on
disk and is listed in `/etc/shells`. Unset — the default — behaves exactly
as before (opt-in knob, not a silent switch). A bash twin of the driver,
[`deploy.bash`](deploy.bash), runs the same fragments; both are preceded by
a `/bin/bash` ≥ 3.2 version assert.

[`deploy.zsh`](deploy.zsh) sets up symlinks, inits submodules, installs git
hooks, runs `mise install`, wires brew (macOS), and schedules a daily `git
pull`. It dispatches into [`scripts/deploy.d/NN_*.zsh`](scripts/deploy.d)
fragments (sourced in numeric order), each handling one install concern; shared
helpers live in
[`scripts/deploy.d/lib/helpers.zsh`](scripts/deploy.d/lib/helpers.zsh). The
[`scripts/post-merge`](scripts/post-merge) hook auto-re-runs deploy after every
`git pull` (it prefers `deploy.zsh` under zsh, falls back to `deploy.bash`
under bash — syntax-checked before running — wraps the deploy in a 300s
`timeout`, and fails loud when neither driver is runnable; opt out per-pull
with `DOTFILES_SKIP_POSTMERGE=1`).

`deploy.zsh` accepts:

| Flag | Meaning |
|------|---------|
| `--upgrade` / `-u` | run brew/mise/cargo upgrades in addition to installs |
| `--dry-run` / `-n` | fragments print intentions via `[dry-run]` without mutating |
| `--force` / `-f` | bypass fragment safety guards — no fragment currently reads it |
| `--only NAME` | run only fragments whose basename matches NAME (e.g. `--only 30_submodules`); repeatable |
| `--help` / `-h` | show flag summary |

### macOS bootstrap (Day 0, before clone)

[`scripts/eris-macos-bootstrap.zsh`](scripts/eris-macos-bootstrap.zsh) is the
fresh-Mac entry point: it installs Homebrew + a baseline (sops, age, mise, …),
then clones this repo and runs `deploy.zsh`. Since the repo isn't cloned yet,
fetch it directly:

```sh
curl -fsSL https://raw.githubusercontent.com/camerontaylor/dotfiles/main/scripts/eris-macos-bootstrap.zsh -o ~/eris-macos-bootstrap.zsh
zsh ~/eris-macos-bootstrap.zsh
```

It prints the manual System Settings grants (Full Disk Access, etc.) needed.

## Secrets

No secret material lives in this repo. Ciphertext is canonical and plaintext is
**derived**: everything encrypted lives in the private repo
`camerontaylor/dotfiles-secrets`, cloned to `~/.local/secrets`, and every deploy
re-renders this machine's plaintext targets from it —
[`65_secrets.zsh`](scripts/deploy.d/65_secrets.zsh) drives
[`scripts/secrets-render.zsh`](scripts/secrets-render.zsh). Shell exports land
**outside every worktree** at `$XDG_STATE_HOME/secrets/zsh/9*.zsh` (mode 600)
and are sourced by the one tracked file, `zsh/env.d/89_secrets_loader.zsh`.
Other targets (`ssh/*`, `configs/portless/*.pem`, service env files) render to
their usual paths and are gitignored.

Edit a secret with `secrets-edit` — never edit a rendered file, since the next
deploy overwrites it:

```sh
secrets-edit shell/90_secrets.yaml    # sops edit, then re-render this box
git -C ~/.local/secrets commit -am "chore: rotate MY_API_KEY"
git -C ~/.local/secrets push          # other boxes render it on their next pull
```

The age key lives at `~/.config/sops/age/keys.txt` — **back it up to your
password manager.** A box missing that key, or missing GitHub read access to
the private repo, gets a printed instruction block and the deploy mutates
nothing rather than failing. `zsh/rc.d/33_secrets_staleness.zsh` warns in new
interactive shells if this box has not rendered for 14 days.

## Deployed services

Beyond shell/editor config, this repo also carries the deploy artifacts for a
few self-hosted services: tracked files in `configs/<service>/`, an idempotent
installer at `scripts/setup-<service>.sh`, a runbook in `docs/<service>.md`.

| Service | Installer | Runbook |
|---|---|---|
| Immich (photo library + nightly restic backup, ceres) | [`scripts/setup-immich.sh`](scripts/setup-immich.sh) | [`docs/immich.md`](docs/immich.md) |
| Caddy (TLS ingress, ceres) | [`scripts/setup-caddy.sh`](scripts/setup-caddy.sh) | [`docs/caddy-ingress.md`](docs/caddy-ingress.md) |
| Paseo (agent orchestrator) | [`scripts/setup-paseo.sh`](scripts/setup-paseo.sh) | [`docs/paseo.md`](docs/paseo.md) |

These are **hand-run**, never wired into `scripts/deploy.d/` — the fleet
auto-deploys on every pull and two of three boxes are Macs with none of these
stacks. Each supports `--check` / `--dry-run` first.

> **Interim home.** Infra is slated to move out of dotfiles into its own repo,
> the way secrets were carved out into `camerontaylor/dotfiles-secrets`. See
> [AGENTS.md § infra carve-out](AGENTS.md#todo-infra-carve-out).

## Zero home presence

**zsh** can be installed without even a `~/.zshenv` symlink: set `ZDOTDIR` to
`<install dir>/zsh` early in login, before zsh sources the user's `.zshenv` —
e.g. add to `/etc/zsh/zshenv`:

```sh
export ZDOTDIR="$HOME/.local/dotfiles/zsh"
```

(Or set it via a PAM environment module.) Deploy detects this and skips the
`~/.zshenv` symlink.

**bash** has no ZDOTDIR — it reads `~/.bash_profile` (login), `~/.bashrc`
(interactive), and `$BASH_ENV` (non-interactive) by absolute home paths, so
three symlinks are the floor `21_bash_symlinks.zsh` installs:
`~/.bash_profile`, `~/.bashrc`, and `~/.config/bash → <install dir>/bash`.
Everything else (env.sh, rc.d/, inputrc) lives under that one dir link, and
`bash/env.sh` exports `BASH_ENV`/`INPUTRC` pointing into it so non-interactive
children and readline resolve there too. A truly link-free install works the
same way as zsh's: set `BASH_ENV=<install dir>/bash/env.sh` early in login
(e.g. a PAM environment module) and start bash as
`bash --rcfile <install dir>/bash/.bashrc`.

Note this applies to the shells; AI CLIs and GUI apps still create their own
`$HOME` dotfiles.

## Configuration

### Git

Put your identity in `~/.config/git/local/user`:

```ini
[user]
    email = jdoe@example.com
    name = John Doe
```

Additional local config can go in `~/.config/git/local/stuff`.

### Zsh

Zsh skips every global config file except `/etc/zsh/zshenv`. Add local config in
`$ZDOTDIR/env.d/9[0-9]_*` (sourced always) or `$ZDOTDIR/rc.d/9[0-9]_*`
(interactive only). `$ZDOTDIR/.zlogin` and `.zlogout` are also honored.

### Neovim

Local config loads from:

* `nvim/init/0[1-9]_*` (e.g. `01_local.lua`) — after options, before plugins
* `nvim/init/9[0-9]_*` (e.g. `99_local.lua`) — after plugins

Neovim config tracks the latest released version (currently 0.11).

### Local paths & ignoring config churn

Local binaries go in `$HOME/.local/bin` (on `PATH`); man pages in
`$XDG_DATA_HOME/man`. For configs a tool rewrites itself (e.g. htop, btop), stop git
from tracking local churn:

```sh
git update-index --assume-unchanged configs/htoprc   # ...and --no-assume-unchanged to restore
```

## For agents

[`AGENTS.md`](AGENTS.md) and [`CLAUDE.md`](CLAUDE.md) document the deploy
architecture, where to add tools, file-numbering conventions, and the strict
shell-script portability rules (the bootstrap layer must stay BSD-clean).
