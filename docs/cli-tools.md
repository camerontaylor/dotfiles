# CLI tools installed by this repo

A quick "what does what" index of every command this repo puts on your PATH, and
where it comes from. Grouped by purpose; the **Source** column tells you which
installer owns it (and therefore where to go when it's missing or wrong).

Sources, and the file that owns each:

| Source | Owner | Notes |
|---|---|---|
| `mise` | [`configs/mise.toml`](../configs/mise.toml) | Version-pinned; exposed via `~/.local/share/mise/shims`. The ONE tool PATH shared by shells and systemd units. |
| `brew` | [`75_brew_setup.zsh`](../scripts/deploy.d/75_brew_setup.zsh) | macOS only. GNU userland, casks, things mise can't deliver. |
| `npm` | [`.default-npm-packages`](../.default-npm-packages) | Installed through **mise's** node by [`70_runtime_installs.zsh`](../scripts/deploy.d/70_runtime_installs.zsh). |
| `cargo` | [`70_runtime_installs.zsh`](../scripts/deploy.d/70_runtime_installs.zsh) | For crates with no mise/aqua backend. |
| `bun` | [`70_runtime_installs.zsh`](../scripts/deploy.d/70_runtime_installs.zsh) | Only `gjc` (bun-only package), symlinked into `~/.local/bin`. |
| `curl` | [`70_runtime_installs.zsh`](../scripts/deploy.d/70_runtime_installs.zsh), [`install-moor.sh`](../scripts/install-moor.sh) | Vendor install scripts. |
| `pkg` | [`40_tools.zsh`](../scripts/deploy.d/40_tools.zsh), [`41_net_tools.zsh`](../scripts/deploy.d/41_net_tools.zsh) | Platform package manager (brew / apt / pacman / AUR), best-effort. |
| `repo` | [`20_symlinks.zsh`](../scripts/deploy.d/20_symlinks.zsh), [`21_bash_symlinks.zsh`](../scripts/deploy.d/21_bash_symlinks.zsh) | Scripts from this repo, symlinked into `~/.local/bin`. |
| `vendor` | [`tools/vendor/`](../tools/vendor) | Vendored scripts, reached via a zsh alias (not on PATH). |
| `manual` | one-shot scripts under [`scripts/`](../scripts) | Never run by `deploy.zsh`; you run them by hand, once per box. |

`./deploy.zsh --upgrade` refreshes everything. [`85_verify_tools.zsh`](../scripts/deploy.d/85_verify_tools.zsh)
smoke-tests ~24 of these at the end of every deploy.

---

## Everyday shell — search, list, jump, view

| Tool | Source | What it does |
|---|---|---|
| `rg` (ripgrep) | mise | Fast recursive grep. Use instead of `grep -r`. |
| `fd` | mise / brew | Fast, ergonomic `find`. |
| `sd` | mise | Simple find-and-replace. Use instead of `sed s///` for plain substitutions. |
| `eza` | mise | Modern `ls` — icons, git status, tree mode. |
| `bat` | mise | `cat` with syntax highlighting + paging. |
| `fzf` | mise | Interactive fuzzy finder; the engine behind `bag`, `fgb`, `fgd`, `fgl`, `fz`. |
| `zoxide` | mise | Frecency-ranked `cd`. `z <partial>` jumps to a directory you've visited. |
| `yq` | mise | YAML/JSON/XML processor (`jq` for YAML). |
| `moor` | curl | Pager — a friendlier `less`. Installed by `scripts/install-moor.sh`. |
| `htop` | pkg | Interactive process viewer. Config symlinked from this repo. |
| `sponge`, `ts`, `chronic`, `vipe` | brew (moreutils) | Pipeline helpers: in-place rewrite, timestamp lines, silence-unless-failure, edit-mid-pipe. |
| `flock` | brew | File locking for cron/lock scripts. macOS has none natively. |

## Editing

| Tool | Source | What it does |
|---|---|---|
| `nvim` | mise / brew | Neovim. Config in [`nvim/`](../nvim). |
| `tree-sitter` | mise | Parser generator / CLI; backs Neovim highlighting and `ast-grep`-adjacent tooling. |
| `sg` (ast-grep) | mise + npm | Structural, AST-aware code search and rewrite. Far safer than regex for refactors. |

## Git & forges

| Tool | Source | What it does |
|---|---|---|
| `gh` | mise | GitHub CLI — PRs, issues, releases, API. |
| `glab` | mise | GitLab CLI, same shape as `gh`. |
| `gh prreview` | pkg (gh ext) | `chmouel/gh-prreview` — TUI for reviewing PRs. |
| `delta` | mise / brew | Syntax-highlighting diff pager. Wired in as git's pager via `git-diff-pager`. |
| `git-diff-pager` | repo | Thin dispatcher: `delta` if present, else plain. Used by `[pager]` in gitconfig. |
| `wtp` | pkg | Git **w**ork**t**ree **p**lus — create/switch/remove worktrees. `w` and `p` wrap it. |
| `git-extras` | pkg | 80+ extra `git` subcommands (`git summary`, `git ignore`, `git undo`, …). |
| `git-restore-mtime` | pkg | Rewrites file mtimes to their last-commit time after a fresh clone. |
| `git quick-stats` | vendor | Interactive repo statistics (contributors, churn, activity). |
| `commit-conventional` | repo | Stages + commits with a Conventional Commits message. |
| `generate-commit-msg` | repo | Generates a commit message from the staged diff (LLM-backed). |
| `rewrite-commits-conventional` | repo (`scripts/`) | Bulk-rewrites existing history into Conventional Commits form. |
| `linear-cli` | cargo | Linear issue tracker from the terminal. |

## Secrets, crypto, cloud

| Tool | Source | What it does |
|---|---|---|
| `sops` | mise | Encrypts/decrypts structured secrets files in-place. |
| `age` | mise / brew | Modern file encryption; the key backend for sops here. |
| `aws` | mise | AWS CLI v2. |
| `psql` | brew (libpq) | PostgreSQL client only — no local server installed. |
| `pinentry-auto` | repo | Picks the right GPG pinentry (native macOS dialog when available) so background gpg-agent prompts don't ambush a random terminal. |
| `secrets-edit` | zsh fn | Edit a secret in the private secrets repo (`~/.local/secrets`) with sops, then re-render this box. |

## Runtimes & package managers

| Tool | Source | What it does |
|---|---|---|
| `mise` | curl / brew | The tool-version manager itself. Source of truth: `configs/mise.toml`. |
| `node` / `npm` | mise | Pinned major. The one node every shell **and** systemd unit resolves. |
| `bun` | mise | JS runtime + package manager; required by `gjc`. |
| `python` / `uv` | mise | Python 3 and the fast pip/venv replacement. |
| `pnpm` / `pn` | npm | Package manager. `pnpm` is served by corepack, `pn` by npm's own binary — deploy keeps them pointed at the same release. |
| `corepack` | npm | Node's package-manager shim manager. |
| `tsx` | npm | Run TypeScript directly, no build step. |
| `tsc` / `typescript-language-server` | npm | TypeScript compiler + the LSP server nvim's `ts_ls` uses. |
| `oxlint` | npm | Very fast JS/TS linter (Rust-based). |
| `cargo` / `rustup` | curl | Rust toolchain, installed on demand for the cargo tools above. |
| `bash` (5.x) | brew | Modern bash for the interactive tree. macOS stock `/bin/bash` 3.2 stays the script floor. |
| `zsh` (latest) | brew | Registered in `/etc/shells` and set as the login shell. |

## AI / coding agents

| Tool | Source | What it does |
|---|---|---|
| `claude` | curl | Claude Code CLI. |
| `codex` | npm | OpenAI Codex CLI. |
| `opencode` | npm | OpenCode terminal coding agent. |
| `gemini` | npm | Google Gemini CLI. |
| `gjc` | bun | gajae-code — coding/planning agent. See the `gjc-orchestration` skill. |
| `codewhale` / `codewhale-tui` | cargo | DeepSeek-backed coding agent, CLI and TUI forms. |
| `omp` | npm | `@oh-my-pi/pi-coding-agent` — coding agent with read/bash/edit/write tools and session management. |
| `ao` | npm | `@aoagents/ao` — Agent Orchestrator CLI. |
| `omc` / `oh-my-claudecode` | npm | `oh-my-claude-sisyphus` — multi-agent orchestration layer for Claude Code. |
| `happy` | npm | Mobile/web client for Claude Code and Codex. Backs every `*-happy` alias. |
| `t3` | npm (+ cask) | T3 Code — web GUI for coding agents, served on port 3773 and exposed via Caddy. |
| `agent-browser` | npm | Browser automation CLI for agents (drives Chrome over CDP). |
| `grab` | npm | Select page context from a website and hand it to a coding agent. |
| `continues` | npm | Resume an AI coding session across different agent CLIs. |
| `engram` | brew (tap) | Persistent memory store for agents. Save bugfixes/decisions/gotchas here. |
| `portless` | mise + npm | Replaces port numbers with stable named `.localhost` URLs. |
| `happy-dom` | npm | *(library, not a CLI)* Headless DOM implementation, available to the global node. |
| `paseo` | cask / mise | Self-hosted agent orchestrator (app ships its own CLI). Install-only via brew — upgrades belong to the app. See [`docs/paseo.md`](paseo.md). |

### Claude Code routing wrappers

Thin `env` wrappers that launch `claude` against a specific provider. Bash twins
live in [`bin/`](../bin) (symlinked to `~/.local/bin`); zsh gets richer versions
in `zsh/env.d/09_claude_code_aliases.zsh`. Full roster and model tiers:
[`configs/ai/claude-code/skills/agent-orchestration/reference/aliases.md`](../configs/ai/claude-code/skills/agent-orchestration/reference/aliases.md).

| Wrapper | Route |
|---|---|
| `cc` | Anthropic, all overrides unset. The only first-party route. |
| `ccz-direct` | Z.AI GLM. The bulk survey/draft workhorse. |
| `ccd-direct` | DeepSeek V4 (pro + flash tiers). |
| `ccm-direct` | MiniMax M2.7. |
| `ccfw-direct` | Fireworks (kimi / minimax / gpt-oss tiers). |
| `ccz` / `ccd` / `ccm` | Portkey-gateway-routed twins of the above. |
| `*-happy` | Same route, launched through `happy yolo` instead of `claude`. |
| `yolo` | `happy yolo` against real Anthropic. |
| `webfront-root` | Helper: prints the enclosing webfront repo root, or fails. |

## Networking & remote

| Tool | Source | What it does |
|---|---|---|
| `tailscale` | pkg | Mesh VPN; the fleet's private network. Joined automatically by `73_tailscale.zsh`. |
| `mosh` | pkg | Roaming-tolerant SSH replacement — survives sleep and network changes. |
| `nc` / `socat` | pkg | Port probing and socket plumbing. `nc` backs the SSH config's LAN fast-path. |
| `rsync` (3.x) | brew | GNU-parity rsync on macOS (stock openrsync rejects `--info=progress2` etc.). |
| `testssl` | pkg | TLS/SSL configuration scanner. |
| `httpstat` | vendor (alias) | Visualises curl timing breakdown for a URL. |
| `wake-peers` | repo | Sends wake-on-LAN packets to the other fleet boxes. |
| `caddy` | manual | Reverse proxy / TLS terminator. Installed by `scripts/setup-caddy.sh`. |

## GNU userland on macOS

Installed by `75_brew_setup.zsh` so macOS behaves like Linux. The `g`-prefixed
names (`gsed`, `gawk`, `gfind`, `gxargs`, `gtar`, `ggrep`, `gdiff`, `grm`, `gdu`,
`gdf`) are always available; the un-prefixed names win in **interactive** shells
via the gnubin PATH prepend.

`coreutils` · `grep` · `diffutils` · `gnu-sed` · `gnu-tar` · `gawk` ·
`findutils` · `gnu-getopt` (keg-only, symlinked separately) · `ncurses`

> Scripts in the bootstrap layer must **not** rely on these — see the BSD-vs-GNU
> table in [`CLAUDE.md`](../CLAUDE.md).

## Small repo utilities

Symlinked into `~/.local/bin` from [`bin/`](../bin); shared by both shells.

| Command | What it does |
|---|---|
| `bag` | Recursive search → fzf picker with preview → opens `$EDITOR` at the match. |
| `fgb` | fzf branch picker, then checkout. |
| `fgd` | fzf file picker over a diff. |
| `fgl` | fzf git-log browser with commit preview. |
| `psg` | `ps` grep that keeps the header and pages when long. |
| `lspath` | Lists every directory component of a path — finds the one denying access. |
| `p` | Pick a plan branch and cd into its worktree (webfront repos). |

## zsh-only functions

Autoloaded from [`zsh/fpath/`](../zsh/fpath); no bash twin.

| Command | What it does |
|---|---|
| `w` | cd into a git worktree by name (`wtp` wrapper). |
| `fz` | fzf picker over zoxide's directory database. |
| `ineachdir` | Run a command in every subdirectory of the cwd. |
| `evalcache` | Cache the output of an expensive `eval "$(...)"` for shell startup. |
| `compdefcache` | Same idea for generated completions. |
| `secrets-edit` | sops-edit a secret in `~/.local/secrets`, then re-render this box. |
| `spark` | vendor alias — ASCII sparkline from a series of numbers. |
| `spectre-meltdown-checker` | vendor alias — CPU speculative-execution vulnerability check. |

## macOS GUI apps (casks)

Not CLI, but installed by the same deploy — listed so you know where they came from.

`iterm2` · `cmux` · `raycast` · `t3-code` · `paseo` (install-only) ·
`aerospace` (tiling WM) · `karabiner-elements` (key remapping) · `forklift`
(file manager) · `font-jetbrains-mono-nerd-font` · `borders` (JankyBorders focus
ring, runs as a brew service) · `duti` (CLI: sets default apps per file type)

## Manual, one-shot installers

Not run by `deploy.zsh`. Run once per machine, by hand.

| Script | What it provisions |
|---|---|
| [`scripts/eris-macos-bootstrap.zsh`](../scripts/eris-macos-bootstrap.zsh) | Fresh-Mac baseline: brew itself plus git, zsh, bash, GNU userland, make, curl, wget, unzip, gnupg, sops, age, gh, glab, awscli, mise, moor, caddy, jq, ripgrep, fd, ast-grep, neovim, tmux, iTerm2. |
| [`scripts/install-niri-stack.sh`](../scripts/install-niri-stack.sh) | niri Wayland desktop stack (Arch only) — waybar, mako, fuzzel, hypr configs. |
| [`scripts/setup-caddy.sh`](../scripts/setup-caddy.sh) | Caddy reverse proxy + fleet ingress. See [`docs/caddy-ingress.md`](caddy-ingress.md). |
| [`scripts/setup-paseo.sh`](../scripts/setup-paseo.sh) | Per-host Paseo daemon config. See [`docs/paseo.md`](paseo.md). |
| [`scripts/setup-t3.sh`](../scripts/setup-t3.sh) | T3 Code server unit on port 3773. |
| [`scripts/setup-ceres-share.sh`](../scripts/setup-ceres-share.sh) | Samba share for `/srv/downloads` on ceres. |
| [`scripts/setup-office-lan.sh`](../scripts/setup-office-lan.sh) | Static gateway-less `10.77.0.x` on the wired NIC. |
| [`bin/install-agents-slice.sh`](../bin/install-agents-slice.sh) | systemd `agents.slice` with a memory cap. `bin/disable-agents-slice-hook` is the escape hatch. |
