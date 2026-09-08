# M2/M3/M4 consolidation — implementation report

**Branch:** `fleet-m234` (dotfiles, base `a932e6f3`) · `m2-manifest-census` (infra)
**Date:** 2026-09-08 · **Scope:** owner-approved moves M2, M3, M4 of
[`docs/fleet-consolidation.md`](../docs/fleet-consolidation.md). M1/M5/M6 were
out of scope and untouched. No merges to main; no deploys run; hosts probed
read-only.

## Commit map

| Repo | Commit | Stage |
|---|---|---|
| dotfiles | `74f01869` fix(setup-caddy): install the tracked caddy.service, not just the drop-in | M2 |
| dotfiles | `4fea7f03` feat(tests): ownership gate — mechanical single-owner enforcement (M2b) | M2 |
| dotfiles | `73b822ee` ci(shells): run the ownership gate on both matrix legs | M2 |
| dotfiles | `d47367b4` docs(tests): agents.slice reason — probe evidence, not a manifest promise | M2 |
| dotfiles | `2be28c49` feat(plugins): replace 48 submodules with pinned-clone lockfile (M3) | M3 |
| dotfiles | `dec3256b` feat(mise): move claude/codewhale/moor/wtp-Linux installs to mise backends (M4) | M4 |
| infra | `1bde7c2` feat(manifests): makemake — litellm retired on-host, portkey owner->agents | M2 |
| infra | `ce60d93` feat(manifests): ceres — fold M2 census strays | M2 |

---

## Stage M2 — census strays → manifests + ownership enforcement

**As built.** Every stray the unit/installer censuses surfaced got exactly one
of: a real install path in this repo, an infra manifest entry on
`m2-manifest-census`, or a declared exception.

- `scripts/tests/ownership-gate.py` + `ownership-declared.toml` — the
  enforcement. Fails on (1) an artifact installed by ≥2 mechanisms with no
  declaration (or a declared mechanism set no longer observed), (2) a
  service artifact shipped/referenced by this repo that is in no infra
  manifest and has no declared reason. Full mode locally (reads
  `~/.local/infra/manifests`); on CI it degrades to skip-with-notice because
  the infra repo isn't checked out there. Wired into both matrix legs of
  `.github/workflows/shells.yml` (`73b822ee`).
- Genuine duals declared with reasons, not papered over: the macOS
  brew-fallback loop in `50_mise.zsh` (awscli, bat, eza, gh, glab, neovim,
  ripgrep, sd, tree-sitter, zoxide, ast-grep), Intel-Mac release drops
  (delta, fd, age), per-OS splits (btop, htop, mosh, tailscale, paseo),
  bootstrap-order (mise, rust), and same-package-two-surfaces (portless,
  ast-grep, wtp).
- Caddy census gap was a real bug and got the real fix (`74f01869`):
  `setup-caddy.sh` defined `TRACKED_CADDY_UNIT` and never used it — the doc
  claimed an install that didn't exist. The script now installs the tracked
  unit; the drop-in remains the env-only piece.
- makemake's dangling litellm symlink: verified gone via read-only ssh
  (retired on-host, manifest updated to match reality).

## Stage M3 — 48 submodules → pinned clones

**As built** (`2be28c49`, 65 files). `.gitmodules` deleted, all 48 gitlinks
(24 nvim / 17 zsh / 4 tmux / 2 yazi / 1 ranger) removed, and:

- **`plugins.lock`** — 48 rows `<sha> <path> <clone-url>`, sorted by path.
  SHAs lifted verbatim from the gitlinks they replace, so the transition is
  behavior-neutral by construction.
- **`scripts/deploy.d/30_plugins.zsh`** (replaces `30_submodules.zsh`) —
  idempotent convergence: at-pin → skip; off-pin git repo → fetch + detached
  checkout of the pin; broken/missing → blob-filtered clone + checkout, with
  a `fetch origin <sha> --depth 1` fallback for pruned history. Carries over
  the `.zwc` compile block unchanged. Dual-parse clean; `_pl_*` variable
  prefix.
- **`.gitignore`** vendoring patterns per tree, negating repo-owned content
  back in (`zsh/plugins/abbreviations-store`, `pnpm-shell-completion`,
  `configs/ranger-plugins/{ipc,z}.py`, the two tracked yazi symlinks).
- 13 files of reference updates: both drivers, `shells.yml` (submodule
  checkout dropped — plugin fetch never runs under `--dry-run`, so CI stays
  minutes-fast and network-free), `dependabot.yml` (gitsubmodule stanza
  deleted), `gitconfig` (submodule sections removed), AGENTS/README/zsh
  docs, `75_brew_setup.zsh`, the syntax gate's scope comment, and
  `zsh/fpath/ftb-tmux-popup` (pin-bump instructions now point at the lock).

**Manager decision — fallback clause invoked.** No lockfile-capable manager
fit any of the four trees, so the brief's sanctioned fallback (thin committed
lockfile + idempotent fetch fragment, preserving current paths) was used:

- **lazy.nvim rejected**: plugins load via the `nvim/plugins →
  $XDG_DATA_HOME/nvim/site/pack/plugins/start` symlink (`20_symlinks.zsh`),
  giving time-0 runtimepath — `init/10_colorscheme` and friends need
  plugins before any manager's `setup()` could run. lazy's shared-data-dir
  install model and setup-ordering would be a regression, and it cannot
  pin per-checkout (worktree isolation).
- **tpm rejected**: no revision pinning at all.
- **sheldon / zinit rejected**: both want to own sourcing; this tree's
  interleaved `rc.d` ordering (fpath population before `compinit`,
  powerlevel10k first, zsh-defer wrappers) is the load-bearing part.

## Stage M4 — installer leftovers → mise backends

**As built** (`dec3256b`, 7 files). Kill criterion applied per tool:

| Tool | Was | Now | Why |
|---|---|---|---|
| `claude` | claude.ai/install.sh curl | `aqua:anthropics/claude-code` | same native binaries; `DISABLE_AUTOUPDATER=1` in mise `[env]` keeps mise the only writer; drift-corrector retires the old `~/.local/share/claude` layout |
| `codewhale` / `-tui` | cargo block | `cargo:codewhale-cli` / `-tui` | mise cargo backend; drift-corrector removes `~/.cargo/bin` copies |
| `moor` | `install-moor.sh` curl | `ubi:walles/moor` | all-platform release assets; script deleted |
| `wtp` (Linux) | release-asset curl | `ubi:satococoa/wtp`, `os=["linux"]` | upstream ships **no darwin-x86_64** asset — ungated would hard-fail Intel Macs (the delta/fd/age trap); macOS keeps `install-wtp.zsh` (brew tap first); `[dual_install.wtp]` now declares mise/brew/curl |
| `linear-cli` | cargo-of-git | **stays** | no mise/aqua/ubi backend exists (crates release stale; only git master builds) — documented exception |
| `rustup` | curl | **stays** | designated toolchain owner; mise's `rust = "1"` symlinks through it |

`eris-macos-bootstrap.zsh` brew baseline minimized to what mise cannot
deliver (GNU userland, casks, mise itself) — the removed dual-installs
(ripgrep/fd/gh/glab/awscli/sops/age/neovim/ast-grep/moor) arrive with the
deploy's `50_mise.zsh`, exactly as the ownership gate demands.
`docs/cli-tools.md` rows and the declaration registry updated in lockstep
(plus the stale "`w` and `p` wrap it" → `w`, `p` having been retired on main).

**Curl-of-binary installs remaining after M4** — all justified: rustup
(toolchain owner), linear-cli (no backend), mise + tailscale (bootstrap /
per-OS), wtp macOS arm64 fallback, caddy (setup script, version-matched to
the config).

---

## Evidence

Run on the final tree unless noted.

1. **Syntax gate**: `bash scripts/tests/shell-syntax-gate.sh --all` → rc 0
   (whole tree, dual `-n`).
2. **Ownership gate, full mode**: `PASS (94 tools mapped, 23 service
   artifacts declared, mode=full)`. Negative control on the same tree:
   injected `brew install yq` into `75_brew_setup.zsh` →
   `FAIL: duplicate ownership: 'yq' installed by ['brew', 'mise']
   (configs/mise.toml; scripts/deploy.d/75_brew_setup.zsh:531)` rc 1;
   reverted → PASS rc 0.
3. **Dual-driver dry-run equivalence** (sequential, `DOTFILES_SKIP_BREW=1`):
   `diff` = 8 lines, start/finish timestamps only
   (`20:08:58`/`20:09:01` zsh vs `20:09:02`/`20:09:03` bash). Output shows
   the new drift-cleanup preview and no wtp/moor install lines on Linux, as
   intended.
4. **Fresh-machine proof (M3)**: fresh clone of the branch to `/tmp`,
   fragment run → 48/48 fetched at pinned SHAs, exit 0, `.zwc` compiled;
   bash-driver re-run idempotent ("48 at pin, 0 converged"); drift
   simulation (`zsh/plugins/z` at HEAD~1) re-converged to pin; zsh
   `--dry-run` on the converged tree silent.
5. **Deployed-box transition is a no-op**: ceres `~/.local/dotfiles` at
   `a932e6f3` probed read-only — 48/48 plugin dirs already at the pinned
   SHAs, so the owner's merge + next deploy converges nothing.
6. **Backend resolution (M4)**: `cargo:codewhale-cli`/`-tui` → 0.9.12,
   `aqua:anthropics/claude-code` → 2.1.263 (matches the native install
   found on ceres), `ubi:satococoa/wtp` → 2.10.3, `ubi:walles/moor` →
   2.19.0; `configs/mise.toml` parses clean (tomllib), fleet mise
   (2026.5.15 here) far postdates `ubi:` backend support.

## Deviations register

| # | Deviation | Reason |
|---|---|---|
| 1 | No lockfile-capable plugin manager adopted; committed `plugins.lock` + fetch fragment instead | brief's explicit fallback clause — see rejection rationale above |
| 2 | `git submodule foreach git clean -ffd` (ran on `--upgrade`) dropped | it only ever deleted `.zwc` artifacts the same fragment re-creates one section later |
| 3 | Old fragment mutated state under `--dry-run` (`git submodule update` was unconditional); new fragment guards every mutation behind `DEPLOY_DRY_RUN` | strict improvement; keeps the dual-driver dry-run diff meaningful |
| 4 | `.git/modules` metadata left on deployed hosts | hard fence (no host mutation); harmless, reclaimed by the owner's post-merge deploy or manually |
| 5 | wtp stays triple-mechanism (mise/brew/curl) rather than consolidated | upstream publishes no darwin-x86_64 asset — consolidation is physically impossible on Intel Macs; declared instead |
| 6 | Census docs left citing `install-moor.sh` etc. | `docs/fleet-census-*.md` are point-in-time records that fed this work; rewriting them would falsify the audit trail |

## Follow-ups (owner / out-of-fence)

1. **hart / agents repo gaps** (census §"no installer"): `openclaw-gateway-10-state-dir.conf`
   has no install path; `docker-10-after-tailscale.conf` drop-in is hand-deployed and
   `wait-for-tailscale-ip.sh` hand-copied to `/usr/local/bin`; `appreciation.service` is a
   tracked orphan whose `/etc/tmpfiles.d/appreciation.conf` is tracked nowhere (export/backup
   pairs are manual `ln -s`); rss-digest units remain tracked in no repo (running copies moved
   to makemake by M5 with manifest entries added — the tracking gap is what's left).
2. **Infra side**: adopt `ownership-gate.py` full mode into infra's CI (it already reads
   `~/.local/infra/manifests`); refresh the stale codexbar evidence strings in
   `manifests/ceres.toml` — live symlinks verified 2026-09-08 to point at
   `~/.local/agents/configs/ai/codexbar/`, not the dotfiles path the evidence quotes;
   `portless-proxy.service` (system shape) still awaits a ceres manifest entry — the declared
   exception stands until then.
3. **Agents repo**: adopt the gate for its installer surfaces. (The codexbar two-owner
   concern resolved itself via the carve-out — config is agents-owned now, verified.)
4. **Docs candidates for owner**: the zsh tied-`path` foot-gun — assigning to a variable
   named `path` silently replaces PATH mid-script (cost a false "0/48 at pin" during M3
   verification; every loop now uses `_pl_*` names). Worth a CLAUDE.md table row at merge
   review. The move-table flip in `docs/fleet-consolidation.md` is likewise deferred to
   merge review per the fence.
5. **Gate limitation, conservative**: `BREW_CALL` captures one token after `brew install`,
   so multi-line continuation lists (eris bootstrap) are unobserved — it can miss a dual,
   never false-fail one. Worth a multi-token pass if the bootstrap list ever grows meaning.
