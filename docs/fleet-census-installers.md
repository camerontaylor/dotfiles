# Fleet census: installer pathways

Date: 2026-09-08. Produced by a GLM-5.3 researcher (read-only survey), collected
during the fleet-consolidation direction work (`docs/fleet-consolidation.md`).
Point-in-time snapshot — re-verify line numbers before acting on them.

# Installer-pathway inventory — `/home/ctaylor/.local/dotfiles`

Read-only survey. Line numbers are from the files as they stand on disk today.

---

## 1. Managers and what they own

| Manager | Item count | Examples | Defined at |
|---|---|---|---|
| **mise** (all backends) | 28 tools | `node=24`, `bun`, `python`, `uv`, `rust=1`, `neovim`, `ripgrep`, `gh`, `glab`, `bat`, `eza`, `sd`, `yq`, `zoxide`, `tree-sitter`, `awscli`, `sops`, `ast-grep` | `configs/mise.toml:1-123` (installed by `scripts/deploy.d/50_mise.zsh:140,143`) |
| — mise default registry | 18 | `node`, `python`, `gh`, `sops`, … | `configs/mise.toml:4-70` |
| — mise `aqua:` backend | 2 | `"aqua:dandavison/delta"`, `"aqua:junegunn/fzf"` | `configs/mise.toml:49,67` |
| — mise `github:` backend | 4 | `pnpm-shell-completion`, `age`, `bandwhich`, `samply` | `configs/mise.toml:68,73,96,97` |
| — mise `npm:` backend | 2 | `"npm:portless"`, `"npm:@getpaseo/cli"` (both os-gated) | `configs/mise.toml:60,123` |
| **npm globals** (via mise node's npm) | 21 packages | `@openai/codex`, `opencode-ai`, `t3`, `pnpm`, `corepack`, `typescript`, `oxlint`, `@ast-grep/cli` | list: `.default-npm-packages:5-46`; installer: `scripts/deploy.d/70_runtime_installs.zsh:85`; also auto-run by mise's node backend via the `~/.default-npm-packages` symlink (`configs/mise.toml:12-14`); corepack pnpm refresh at `70_runtime_installs.zsh:100` |
| **brew formulae** | ~30 | `zsh`, `bash`, GNU userland ×8, `fd`, `git-delta`, `age`, `btop`, `htop`, `macmon`, `mosh`, `socat`, `sleepwatcher`, `engram` (tap), `borders` (tap) | `scripts/deploy.d/75_brew_setup.zsh:109,176,184,209,227,236,269-276,292-297,304,315-319,325,483,502,515`; `05_bash.zsh:18`; `41_net_tools.zsh:11`; `76_wake_peers.zsh:53`; `40_tools.zsh:39` |
| **brew casks** | 11 | `iterm2`, `font-jetbrains-mono-nerd-font`, `cmux`, `raycast`, `t3-code`, `paseo` (install-only), `aerospace`, `karabiner-elements`, `forklift`, `tailscale`, `obs` | `75_brew_setup.zsh:361,374,385,396,410,444,456,467,522`; `73_tailscale.zsh:68`; `77_obs.zsh:55` |
| **brew as mise fallback** | 13 tools | `gh ripgrep neovim delta bat eza fd sd zoxide tree-sitter awscli ast-grep glab` — macOS only, only if still missing post-mise | `scripts/deploy.d/50_mise.zsh:166-181` |
| **cargo** | 3 packages | `linear-cli` (git install), `codewhale-cli`, `codewhale-tui` (crates.io); rustup bootstrapped first | `scripts/deploy.d/70_runtime_installs.zsh:182` (rustup), `194,201` (linear-cli), `212-215,234` (codewhale) |
| **curl-piped / release-asset binaries** | 6 | Claude Code (`claude.ai/install.sh`), rustup (`sh.rustup.rs`), mise (GitHub release), `wtp`, `moor`, tailscale (`tailscale.com/install.sh`, non-Arch Linux) | `70_runtime_installs.zsh:18,182`; `50_mise.zsh:32,52`; `scripts/install-wtp.zsh:116-121`; `scripts/install-moor.sh:18-25`; `73_tailscale.zsh:128` |
| **pacman** (Arch) | 11 packages | `tailscale`, `htop`, `mosh`, `openbsd-netcat`, `socat`, `testssl.sh`, `atop`, `iotop-c`, `bpftrace`, `nvtop` | `73_tailscale.zsh:116`; `75_brew_setup.zsh:192,251`; `41_net_tools.zsh:35`; `40_tools.zsh:72`; `42_monitoring.zsh:92` |
| **apt** (Debian) | 7 packages | `mosh`, `git-extras`, `git-restore-mtime`, `testssl.sh`, `atop`, `iotop`, `bpftrace`, `nvtop` | `75_brew_setup.zsh:240`; `40_tools.zsh:62-64`; `42_monitoring.zsh:95` |
| **AUR** (paru/yay) | 2 packages | `git-extras`, `git-tools` (provides `git-restore-mtime`); `keyd` is hint-only | `40_tools.zsh:76-80`; `79_keyd.zsh:28` |
| **bun global** | 1 | `gajae-code` (`gjc`), bridged into `~/.local/bin` | `70_runtime_installs.zsh:148,175` |
| **gh extension** | 1 | `chmouel/gh-prreview` | `40_tools.zsh:140-142` |
| **git submodules** | 48 total | see breakdown below | `.gitmodules:1-144`; synced by `scripts/deploy.d/30_submodules.zsh:20` |
| — nvim plugins | 24 | `blink.cmp`, `codecompanion`, `mason`, `nvim-treesitter`, `mini`, … | `.gitmodules:4-72,136` |
| — zsh plugins | 17 | `powerlevel10k`, `zsh-syntax-highlighting`, `fzf-tab`, `zsh-completions`, … | `.gitmodules:85-135` |
| — tmux plugins | 4 | `colors-solarized`, `prefix-highlight`, `resurrect`, `continuum` | `.gitmodules:73-78,139-144` |
| — yazi plugins | 2 | `githead.yazi`, `yazi-rs-plugins` | `.gitmodules:79-84` |
| — other | 1 | `configs/ranger-plugins/archives` | `.gitmodules:1-3` |
| **vendored scripts** (`tools/vendor/`) | 4 | `git-quick-stats` (on PATH), `httpstat`, `spark`, `spectre-meltdown-checker.sh` (alias-reached) | `tools/vendor/`; PATH link at `40_tools.zsh:12`; aliases per `docs/cli-tools.md:149,192-193` |
| **repo scripts → `~/.local/bin`** | ~27 symlinks | `pinentry-auto`, `git-diff-pager`, `commit-conventional`, `generate-commit-msg`, `wake-peers`, `git-quick-stats`, `gjc` bridge, `bin/*` wrappers (`cc`, `ccz`, `yolo`, `bag`, `fgb`, …) | `20_symlinks.zsh:64,76-78,169`; `21_bash_symlinks.zsh:22,27`; `40_tools.zsh:12`; `70_runtime_installs.zsh:175` |
| **manual one-shot scripts** (never run by deploy) | 9 | `eris-macos-bootstrap.zsh`, `install-niri-stack.sh`, `setup-caddy.sh`, `setup-paseo.sh`, `setup-t3.sh`, `setup-llm-quota.sh`, `setup-ceres-share.sh`, `setup-office-lan.sh`, `bin/install-agents-slice.sh` | indexed at `docs/cli-tools.md:208-218` |
| **external owner** (out of repo, for completeness) | 1 | `openclaw` — installed/repaired only by the ExecStartPre guard on `openclaw-gateway.service` in `~/repos/hart` | documented `configs/mise.toml:15-20`, `.default-npm-packages:24-43` |

Cross-check: `docs/cli-tools.md:9-20` defines the same source taxonomy (mise / brew / npm / cargo / bun / curl / pkg / repo / vendor / manual) and its per-tool table matched everything I found. `85_verify_tools.zsh:17-64` smoke-tests ~28 of these at deploy end.

**Note on the task prompt:** there is **no `rust_tools` array in `deploy.zsh` anymore** — `rg 'rust_tools|cargo install'` over `deploy.zsh` returns nothing. It was migrated into mise (`configs/mise.toml:22-24` documents the migration; only `linear-cli` stayed in cargo). Project memory ("~159 submodules", "rust_tools at deploy.zsh ~202") predates the submodule→binary migration; current count is 48.

---

## 2. Conditional branches that pick the manager per OS / host

**Version-templated inside mise.toml (per OS+arch):**
1. `delta` — `0.18.2` on macOS/x64, `0` elsewhere — `configs/mise.toml:49`
2. `fd` — `10.3.0` on macOS/x64, `10` elsewhere — `configs/mise.toml:52`
3. `btop` — `os = ["linux"]` filter (no darwin assets upstream) — `configs/mise.toml:89`
4. `npm:@getpaseo/cli` — `os = ["linux"]`; Macs get the CLI from the cask's app bundle instead — `configs/mise.toml:105-123`

**OS fan-outs in deploy fragments:**
5. brew-then-asset for **mise itself**: Linux → direct GitHub download (`50_mise.zsh:26-41`); macOS → `brew_install_or_upgrade mise` first, curl fallback (`50_mise.zsh:42-64`)
6. mise→**brew fallback loop** for 13 tools, Darwin-only and only-if-missing — `50_mise.zsh:166-181`
7. **htop**: brew on Darwin (`75_brew_setup.zsh:182-184`) vs pacman on Arch (`75:185-199`)
8. **btop**: brew bottle on Darwin (`75_brew_setup.zsh:207-210`) vs mise on Linux (branch 3 above)
9. **macmon**: Darwin **and arm64 only** (Intel Macs excluded via `uname -m`) — `75_brew_setup.zsh:225`
10. **mosh**: brew (`75:234-236`) / apt (`75:237-247`) / pacman (`75:248-258`)
11. **fd/git-delta/age** via brew on Darwin (`75:313-320`) — the darwin half of branches 1-2 and the `github:age` entry (`mise.toml:71-73`)
12. **git-extras / git-restore-mtime / testssl**: brew (`40_tools.zsh:31-44`) / apt (`40:59-66`) / pacman+AUR with paru/yay detection (`40:67-85`)
13. **nc/socat**: socat-only via brew on Darwin (`41_net_tools.zsh:9-14`); pacman `openbsd-netcat socat` on Arch, hint on other distros (`41:31-45`)
14. **monitoring set** (atop/iotop[-c]/bpftrace/nvtop): Linux-only, pacman vs apt by distro, different package name for iotop — `42_monitoring.zsh:25-27,47-56`
15. **tailscale**: brew cask on Darwin (`73_tailscale.zsh:58-83`) / pacman on Arch (`73:107-118`) / curl `install.sh` on other Linux (`73:120-130`)
16. **wtp**: brew tap on Darwin (with unlinked-keg rescue) — `scripts/install-wtp.zsh:73-111`; GitHub release asset for Linux x64/arm64 + macOS arm64 (`113-127`); macOS x64 is brew-only (`129-131`)

**Host/environment gates that decide whether an install runs at all:**
17. `DOTFILES_SKIP_BREW` — skips all brew mutation in CI — `75_brew_setup.zsh:8-11`, `40_tools.zsh:31`
18. sudo-passwordless-or-TTY guard before every pacman/apt invocation (no-sudo-in-git-hook rule) — `75_brew_setup.zsh:190,238,249`; `40_tools.zsh:113`; `42_monitoring.zsh:86,126`
19. `brew_upgrade_skip=( paseo )` — cask deliberately never upgraded by brew (beta channel owned by the app) — `75_brew_setup.zsh:58`; paired with install-only branch at `75:441-448`
20. gjc requires bun ≥ 1.4.0, else skip with hint — `70_runtime_installs.zsh:140-145`
21. `rust = "1"` mise pin exists so cargo shims resolve to the rustup-installed toolchain (symlink, not a second download) — `configs/mise.toml:31-44`
22. `obsolete_mise_tools` uninstall sweep, with an explicit never-list for `node`/`npm:t3`/`npm:portless` — `70_runtime_installs.zsh:36-60`
23. Vite+ teardown, only after mise node proven working — `70_runtime_installs.zsh:116-120`
24. ghx drift-correcting removal (brew side and non-brew side) so mise's `gh` owns the name — `70_runtime_installs.zsh:250-261`, `75_brew_setup.zsh:345-355`

---

## 3. Tools owned by two or more mechanisms (conflict risk)

**True concurrent dual-installs (same box, two installers):**

| Tool | Mechanism A | Mechanism B | Status |
|---|---|---|---|
| `portless` | npm global — `.default-npm-packages:15` | mise `"npm:portless"` — `configs/mise.toml:60` | **Deliberate** (at census time): the webfront runner needed it via `mise exec` in a non-interactive env; explicit do-not-uninstall note at `70_runtime_installs.zsh:33-35` and `mise.toml:55-59`. **Update 2026-09-08:** webfront retired (owner ruling, `docs/fleet-consolidation.md`); portless stays dual-installed as generic dev tooling, do-not-uninstall unchanged |
| `fd` | mise (version-templated) — `mise.toml:52` | brew `fd` on Darwin — `75_brew_setup.zsh:315` | Both land on Macs; mise shims precede `~/.local/bin`, brew lives in `/opt(homebrew)/bin`. Documented as "mise / brew" in `docs/cli-tools.md:32` |
| `delta` | mise aqua — `mise.toml:49` | brew `git-delta` on Darwin — `75:317` | Same shape as fd (`docs/cli-tools.md:59`) |
| `age` | mise github backend — `mise.toml:73` | brew `age` on Darwin — `75:319` | Same shape (`docs/cli-tools.md:75`) |
| `ast-grep` (`sg`) | mise — `mise.toml:28` | npm globals `@ast-grep/cli` **and** `@ast-grep/napi` — `.default-npm-packages:17-18` | Acknowledged in `docs/cli-tools.md:50` ("mise + npm") |
| `pnpm` | npm global (`pn` binary) — `.default-npm-packages:12` | corepack's own cache serves the `pnpm` name — `70_runtime_installs.zsh:92-104` | Known drift hazard, actively reconciled every deploy by pointing corepack at current pnpm |
| `mise` (manager itself) | curl release asset | brew on macOS (preferred) | Fallback chain, mutually exclusive at runtime — `50_mise.zsh:42-64` |
| 13 mise tools (`gh`, `ripgrep`, `neovim`, `bat`, `eza`, `sd`, `zoxide`, `tree-sitter`, `awscli`, `glab`, + fd/delta/ast-grep above) | mise | brew fallback | Hedge path, fires only when mise failed to deliver — `50_mise.zsh:166-181` |

**Same tool name, split by OS (not concurrent, but two owners fleet-wide):**
- `btop` — mise on Linux (`mise.toml:89`) / brew on macOS (`75:207-210`)
- `htop` — brew (`75:182`) / pacman (`75:185`)
- `mosh` — brew / apt / pacman (`75:234-258`)
- `socat`, `tailscale`, `git-extras`, `testssl`, monitoring set — pkg-manager fan-outs (§2 branches 12-15)
- `paseo` — cask app-bundle CLI on Macs (`75:417-448`) / mise `npm:@getpaseo/cli` on Linux (`mise.toml:123`); deliberately kept off the npm-globals list to avoid two drifting `paseo` binaries (`mise.toml:105-123`, `75:417-425`)
- `t3` — npm global CLI (`.default-npm-packages:10`) + `t3-code` cask desktop app (`75:407-415`) — two artifacts, one name, intentional

**Retired-but-guarded conflicts (cleanup branches, not installs):**
- `ghx` vs mise `gh` — removal branches at `70_runtime_installs.zsh:250-261` and `75_brew_setup.zsh:345-355`
- Vite+ vs mise node — teardown at `70_runtime_installs.zsh:116-120`
- brew `zsh-completions` formula vs the `zsh/plugins/completions` submodule — formula deliberately not installed (`75:287-289`, `.gitmodules:100`)

Two stale facts in project memory surfaced during this survey, worth correcting next time memory is editable: the submodule count is 48 (not ~159) and the `rust_tools` array no longer exists in `deploy.zsh`.
