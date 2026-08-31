# Bash compatibility — what it would take

Research report (2026-08-31) on making this repo work under **bash as well as
zsh**. Produced by a fan-out research workflow: 5 researchers over disjoint
angles → 50 raw findings → 49 unique → 3 lens-diverse adversarial verifiers
(citation / semantics / impact; a finding dies at 2+ refute votes).
**48 findings confirmed, 1 refuted.** Every confirmed claim was re-checked
against its cited `file:line`; parse-level claims were reproduced with
`bash -n` vs `zsh -n`, runtime claims with probes against bash 3.2.57
(macOS stock) and bash 5.3 (brew).

> **Reading guide:** parse-error = `bash -n` fails outright.
> runtime-divergence = parses, runs, does the wrong thing (the dangerous
> class — most exit 0). architectural = zsh-only by design; bash support
> needs a parallel file/layer, not an edit.

---

## Executive summary

The repo is coupled to zsh at **four layers**, and the correct shape of the
work is *not* editing every file to be dual-shell. It is:

1. **A parallel bash deploy driver** — `deploy.zsh` itself is unparseable by
   bash at 7 independent points, so nothing in `scripts/deploy.d/` is even
   *reachable* under bash today.
2. **A mechanical sweep of fragment bodies** — ~1,000 call sites across ~50
   files, concentrated in 5 repeating idioms, all sed-able.
3. **A new `bash/` interactive layer** — the repo has **no** `.bashrc`,
   `.bash_profile`, or `.inputrc` at all (`find . -iname '*inputrc*'` →
   nothing), and `zsh/` is unportable by design in places (fpath/autoload,
   setopt).
4. **Depointing ~10 external pin points** — git hooks, launchd plists, the
   git pager, `CLAUDE_CODE_SHELL`, `chsh`, ranger's `z`-via-`zsh -ic`,
   README flows.

The single most important architectural decision: **keep fragment *bodies*
shell-agnostic so one set of fragments serves either driver; push zsh-only
state (`zmodload`, `setopt`, glob qualifiers) up into the drivers.**

Two meta-facts shape everything below:

- **Parse errors are the friendly failure class.** The dangerous findings are
  the ones where bash runs to completion, exits 0, and does the wrong thing
  (empty strings from history modifiers, skipped secret rows from 0-vs-1
  array indexing, no-op `path=(...)` assignments). A port that only chases
  `bash -n` failures ships all of these.
- **`bash -n` has false passes.** `tools/git-diff-pager` passes `bash -n` but
  dies at runtime on `${+commands[delta]}`; history modifiers
  (`:h :t :r :A :l`) never error at all. The repo's documented `-n`
  verification protocol (CLAUDE.md) needs a runtime-probe class for these.
- **Everything fails *silently* because `setopt err_exit` has no bash
  equivalent in effect** — the fail-fast contract vanishes, so every 127 /
  bad-substitution becomes a no-op instead of an abort.

---

## A. The deploy driver — parse-blocked at the entry point

`bash -n deploy.zsh` → `line 119: syntax error near unexpected token '('`
(the `(N)` glob qualifier in the fragment dispatch loop); `zsh -n` is clean.
The file stacks seven zsh-only layers, any one of which is fatal:

| Line | Construct | bash behavior |
|---|---|---|
| 33 | `setopt extended_glob err_exit typeset_silent` | `setopt: command not found` |
| 36 | top-level `local upgrade_mode=false` | `local: can only be used in a function`, **assignment discarded** (var = `""`) |
| 42 | `typeset -ga deploy_only=()` | bash 3.2: `typeset: -g: invalid option` (`-g` arrived in bash 4.2) |
| 84 | `zmodload -F zsh/files b:zf_*` | no module system → all `zf_*` become 127s |
| 86 | `SCRIPT_DIR=${0:A:h}` | silently **empty** → `cd $SCRIPT_DIR` becomes `cd $HOME` |
| 119 | `$~fragment_glob(N)` | parse error — kills the whole file |
| 121 | `${deploy_only[(r)${frag_name}]:-}` | reverse-index subscript flag |

**Fix shape:** a `deploy.bash` twin driver (or POSIX-ized driver) reusing the
same fragments. Portable dispatch:

```sh
shopt -s nullglob
for fragment in "$SCRIPT_DIR"/scripts/deploy.d/[0-9]*.zsh; do
  base=${fragment##*/}; frag_name=${base%.zsh}
  ...
```

with a `case` membership test replacing `${deploy_only[(r)…]}` for `--only`.

---

## B. Fragment bodies — the mechanical sweep

Five idioms account for the overwhelming majority of sites. Ordered by
leverage:

### B1. `${+commands[x]}` → `have()` helper — ~172 sites / 48 files

First breaks at `scripts/deploy.d/lib/helpers.zsh:25`, sourced before any
fragment runs. bash: `bad substitution`, and inside `if` it aborts the entire
compound command — **neither branch runs**, so every install/skip gate
(`brew` ×24 in `75_brew_setup.zsh`, `mise`, tool detection) silently no-ops.

```sh
have() { command -v -- "$1" >/dev/null 2>&1; }   # POSIX, identical in both shells
```

Rewrite `(( ${+commands[x]} ))` → `have x`, `(( ${+functions[x]} ))` →
`isfunc x` (`typeset -f` probe). `${commands[zsh]:-/bin/zsh}` →
`zsh_bin=$(command -v zsh || printf /bin/zsh)`. Verifiers called this the
highest-leverage single substitution in the port. `${+terminfo[…]}`
(`05_keys.zsh:106`, `20_cursor_shape.zsh:5`) has no bash analogue — use
`infocmp -1` / `tput` probes.

### B2. `print` → `printf` — ~570–590 sites / 36 files

All variants break (`-u2`, `-r --`, `-rn --`, `-l`, `-Pn`). **47
`print -r --` sites author files rather than log**: the rendered-secrets env
body (`scripts/secrets-render.zsh:60` — every secret target ends up
zero-byte), the systemd unit + timer (`56_tmpdir_prune.zsh:59,70` →
daemon-reloads a broken unit), the render-ok marker.

| zsh | bash |
|---|---|
| `print msg` | `printf '%s\n' msg` |
| `print -u2 msg` | `printf '%s\n' msg >&2` |
| `print -r -- $x > f` | `printf '%s\n' "$x" > f` |
| `print -rn -- $t` | `printf '%s' "$t"` |

Never `printf $msg` — it reinterprets `%` in secret values. `print -Pn`
(prompt escapes, `zsh/rc.d/07_terminal_title.zsh:9`) needs a hand-written
escape sequence.

### B3. File-scope `local`/`typeset` — ~220–255 lines / 26 files

Fragments are sourced at file scope (`deploy.zsh:125`); zsh treats `local`
as `typeset`, bash rejects it **and discards the assignment** (measured:
empty). Fix: strip `local` from fragment bodies, or wrap each fragment in
`fragment_main() { … }; fragment_main` — which also fixes the scoping leak
`typeset_silent` exists to silence.

### B4. `zf_mkdir`/`zf_ln`/`zf_chmod`/`zf_rm` → plain commands — ~30 sites / 10 fragments

These are the *only* filesystem-mutating calls in the deploy, injected by
`deploy.zsh:84`'s `zmodload`; under bash the deploy **installs nothing while
printing status messages**. Fix inside the existing `deploy_mkdir`/`deploy_ln`
dry-run wrappers (`scripts/deploy.d/lib/helpers.zsh:8-22`) — covers ~40 call
sites for free. All flags in use (`-p`, `-sfn`, `-m 700`) are BSD-clean.

### B5. Glob qualifiers → nullglob guard loops / `find` — 7+ files fail `bash -n`

- `scripts/deploy.d/73_tailscale.zsh:32` — `(N)`
- `scripts/deploy.d/20_symlinks.zsh:149` — `*~*.enc(N.)` (`~` exclusion + qualifiers)
- `scripts/deploy.d/30_submodules.zsh:37` — `**/*.zsh{-theme,}(#q.)`
- `scripts/deploy.d/55_evalcache_prune.zsh:26` — `(N.L0)`
- `scripts/restore-secrets.zsh:47`, `scripts/save-secrets.zsh:109`,
  `scripts/sops-add-recipient.zsh:77`

Replacement idiom:

```sh
shopt -s nullglob
for f in "$dir"/*.zsh; do
  [ -f "$f" ] || continue
  ...
```

or `find … -print0` pipelines. **Version trap:** bash 3.2 has no `globstar`
at all (`shopt: globstar: invalid shell option name`), so `**` silently
degrades to `*` — recursive globbing must use `find` in the bootstrap layer.

### B6. The semantic class (parses, runs, wrong)

- **1-based vs 0-based arrays** — `scripts/secrets-render.zsh:235`,
  `scripts/restore-secrets.zsh:99`, `scripts/save-secrets.zsh`,
  `scripts/sops-add-recipient.zsh:60`: bash's loop skips row 0
  (`shell/90_secrets.yaml`, the primary credential env file) and `${#arr}` is
  the *strlen of element 0*, not the count. Exits 0, writes the success
  marker. Fix: `for (( i = 0; i < ${#MAP_SRC[@]}; i++ ))`.
- **Unquoted array expansion** — the CLAUDE.md-documented divergence, live at
  the policy's own canonical site `scripts/deploy.d/70_runtime_installs.zsh:75`
  (`npm install -g $npm_packages` installs only the first package; `:50`
  uninstalls only the first of 18 obsolete tools). Destructive at
  `scripts/prune-tmpdir:108` (`rm -rf -- ${stale}` deletes one entry, reports
  the full count). Fix: `"${arr[@]}"` everywhere; CLAUDE.md should list
  `cmd "$arr[@]"` as the *required* spelling.
- **History modifiers `:h :t :r :A :l`** — never error; `${x:h}` returns the
  input unchanged, `${x:A:h}` yields empty, `${DOTFILES_OS:l}` keeps `Darwin`
  (so `50_mise.zsh:7-8` never matches `linux` and mise is silently not
  installed). ~10 sites including every script's self-location. Fix: reuse
  the repo's portable symlink walk (`scripts/generate-commit-msg:14-19`) and
  `dirname`/`basename`/`${p%.*}`/`tr`.
- **Expansion flags** — `${(f)…}` and `${a:|b}` (`75_brew_setup.zsh:54`: brew
  upgrades silently all skipped, exit 0), `${(j:, :)…}`, `${(q)…}`,
  `${(D)…}`, `${(@f)…}` (`76_wake_peers.zsh:30`, `77_obs.zsh:33` — host
  lists silently become empty).
- **`setopt err_exit pipefail` → `set -eE -o pipefail`** — with a real trap:
  bash `set -e` aborts on `(( N_FAILED++ ))` when the counter is 0
  (arithmetic 0 → status 1); the codebase increments counters that way at
  `scripts/secrets-render.zsh:242,249,331,361`. Pre-increment or
  `N_FAILED=$((N_FAILED+1))`.
- **Missing `;` before `}`** — 4 sites (`scripts/prune-tmpdir:40,45`,
  `scripts/deploy.d/40_tools.zsh:102`, `73_tailscale.zsh:115`); zsh accepts
  `}` as a terminator, bash doesn't — and **`zsh -n` cannot catch these**.
- **extended_glob patterns** — `scripts/secrets-render.zsh:57`'s
  `\$[A-Za-z_]##…`: under bash the pattern only matches a literal `##`, so
  the dotenv alias `$PORTKEY_LOCAL_API_KEY` gets single-quoted into a dead
  literal. Silent credential corruption. Fix: `=~` ERE
  (`[[ $val =~ ^\$[A-Za-z_][A-Za-z_0-9]*$ ]]`) or a `case` prefix test.
- **Small builtins** — `rehash` → `hash -r` (~14–18 sites);
  `emulate -L zsh` → delete; `autoload -Uz is-at-least` → shim (its 127
  currently makes the `elif ! is-at-least 1.4.0` branch true at
  `70_runtime_installs.zsh:125`, so **gjc is silently never installed**);
  `&!` → `& disown`; `unfunction` → `unset -f`.

---

## C. The interactive layer — a parallel `bash/` tree, not edits

There is no bash interactive config in the repo. The work is creating
`bash/` (`.bash_profile` → `.bashrc` → `bash/env.d/*` + `bash/rc.d/*`),
wired by a new `scripts/deploy.d/21_bash_symlinks.zsh`.

- **`path=(...)` tied array — 10 sites, all silent no-ops**
  (`zsh/env.d/03_paths.zsh:20,42,46,50`, `zsh/.zshenv:79`,
  `rc.d/02b_gnubin_path.zsh:23,35`, `rc.d/07_semantic_integration.zsh:5`).
  Verified in bash 5.3: PATH is never modified *and* each assignment clobbers
  the previous one. Includes the fragment CLAUDE.md cites as the canonical
  array pattern — the fragments that look most portable fail hardest. Fix: a
  shared `path_prepend()` with a `case`-based dedup, replacing
  `typeset -U path PATH` (which bash rejects outright).

```sh
path_prepend() {
  local d
  for d in "$@"; do
    case ":$PATH:" in *":$d:"*) ;; *)
      [ -d "$d" ] && PATH="$d:$PATH" ;;
    esac
  done
  export PATH
}
```

- **`.zshenv:66` / `.zshrc:45` `(N)` loops are parse errors** — since
  `10_dirs.zsh:29` symlinks this to `~/.zshenv`, a bash login can't even
  reach the *portable* env.d layer. The fix (plain glob + `[ -e ]` guard) is
  byte-identical in both shells and should become the shared template.
- **`[[ -o interactive ]]` is unconditionally false in bash** — silent
  inversion; the 179-line agent-alias set (`09_claude_code_aliases.zsh:5`)
  and agents.slice / worktree-scope gates (`rc.d/00b_agents_slice.zsh:42`,
  `rc.d/04c_worktree_scope.zsh:41`) never load. Fix
  `case $- in *i*) ;; *) return 0 ;; esac` — safe in the zsh files too.
- **Anonymous functions `() {`** — parse error in the secrets loader
  (`zsh/env.d/89_secrets_loader.zsh:20`), so under bash no credential is
  exported. Fix: named function, invoked, `unset -f`. **`always` blocks** —
  zsh try/finally; in `04c_worktree_scope.zsh:105` the idempotency latch
  never clears, so the second `cd` into a worktree silently does nothing.
  For `09_claude_code_aliases.zsh:28` (stty/terminal-mode restore) an
  explicit `ret=$?` … restore … `return $ret` sequence is equivalent.
- **fpath/autoload has no bash analogue** — 33 files in `zsh/fpath/`, 20
  already fail `bash -n`. Split by kind: pure CLI wrappers (`cc*`, `ccm*`,
  `p`, `w`, `bag`, `fgb`, `fgd`, `fgl`, `fz`, `psg`, `ineachdir`…) → `bin/`
  as bash executables so *both* shells get them via PATH with zero per-shell
  code; prompt/zle/stateful ones (`clear-screen-soft-bottom`, `evalcache`,
  `compdefcache`…) → `bash/fpath.d/` sourced eagerly (bash has no lazy
  autoload — the cost moves to shell init).
- **`02_setopt.zsh` is a rewrite, not a translation** — 29 zsh option names
  → explicit mapping:

  | zsh | bash |
  |---|---|
  | `HIST_IGNORE_DUPS` | `HISTCONTROL=ignoredups` |
  | `HIST_IGNORE_SPACE` | `HISTCONTROL=ignorespace:ignoredups` |
  | `INC_APPEND_HISTORY` | `shopt -s histappend` + `PROMPT_COMMAND='history -a'` |
  | `EXTENDED_HISTORY` | `HISTTIMEFORMAT` |
  | `AUTO_CD` | `shopt -s autocd` |
  | `CLOBBER` | `set +o noclobber` |
  | `NOTIFY` | `set -b` |
  | `BRACE_CCL`/`EXTENDED_GLOB` | `shopt -s globstar extglob` (5.x only — not bootstrap) |
  | completion options (AUTO_PARAM_SLASH, LIST_TYPES, …) | `.inputrc` settings (`visible-stats`, `mark-directories`, …) |
  | `CORRECT`, `RM_STAR_SILENT`, `LONG_LIST_JOBS`, `AUTO_RESUME` | no equivalent — drop |

  Fragments reusable as-is by a bash layer (once §B fixes land):
  `env.d/02_locale.zsh`, `02_exports.zsh:44-72`, `04_editor.zsh`,
  `05_tmp_dir.zsh`, `07_claude.zsh`, `10_opencode.zsh`,
  `11_ccr_default.zsh`, plus the env-only halves of `08_mise.zsh` and
  `12_paseo.zsh`.
- **Zero-home-presence is zsh-only by design** (README §"Zero home
  presence"): zsh reads exactly one global file (`/etc/zsh/zshenv`) for
  login, interactive, and non-interactive invocations alike; bash's three
  disjoint hooks (`/etc/profile`, `/etc/bash.bashrc`, `$BASH_ENV`) cannot
  replicate it. A bash port needs a parallel loader (e.g.
  `bash/env.d/*.sh` from `~/.config/bash/profile.d`) plus an optional
  `$BASH_ENV` pointer for non-interactive use, and the README section
  rewritten to state both mechanisms side by side.

---

## D. Pin points outside `scripts/` and `zsh/`

| Surface | Location | Failure under bash-only | Fix |
|---|---|---|---|
| post-merge hook | `scripts/post-merge:1,22,25,39` | worst case: `print` 127 + empty `repo_root` → `zsh -n "/deploy.zsh"` fails → "skipping" branch → `exit 0` — **git pull looks green, box drifts forever** | rewrite ~10 lines POSIX `sh`; keep `exec` but guard `command -v zsh` and fail *loud* |
| pre-commit hook | `scripts/pre-commit:13` | `${0:A:h}` → `exec /enforce-codex-defaults.zsh` → **every commit blocked** | POSIX-ize 5 lines; reuse `generate-commit-msg:19-25` walk |
| git pager (repo-wide) | `tools/git-diff-pager:3` + `configs/gitconfig:44-48` | every `git diff/show/log/blame` → `env: zsh: No such file` | two-line POSIX file (`command -v delta` → `exec delta` / `exec less --RAW-CONTROL-CHARS --quit-if-one-screen`) |
| Claude Code shell | `configs/ai/claude-code/settings.json:7` (`"CLAUDE_CODE_SHELL": "zsh"`, symlinked to `~/.claude/settings.json`) | harness pinned to zsh on every box; on a bash-only host every Bash tool call fails to launch | delete the key (inherit `$SHELL`) or render it per-host |
| cc-worker.sh | `configs/ai/claude-code/skills/agent-orchestration/scripts/cc-worker.sh:39` | `bash -n` fails — and this script's documented purpose is being run *from the Bash tool* | port to bash (the one script that must be) |
| ranger `z` | `configs/ranger-plugins/z.py:12,22` | `FileNotFoundError: 'zsh'` on `:z` and TAB | go through zoxide (already a mise tool, shell-agnostic) |
| launchd/systemd units | `99_periodic.zsh:67` (`/bin/zsh` hardcode), `56_tmpdir_prune.zsh:32` | units can't exec | take the runner path from an env var |
| secrets quoting contract | `secrets-render.zsh:60` `${(qq)val}` ↔ `89_secrets_loader.zsh` | zsh-quoted output sourced by bash (and vice versa) | render POSIX single-quote with `'\''` escaping — byte-identical in both; give `docs/tailscale-migration-runbook.md:89` a bash-runnable twin |
| login shell | `README.md:126` + `75_brew_setup.zsh:92,112-116` | deploy **re-pins every fresh Mac to zsh** behind the user's back | `DOTFILES_SHELL` deploy-time knob; `chsh` only when the value is on disk and in `/etc/shells` |

---

## E. Version floor and ordering constraints

- **The floor is a decision, not a fact.** A census claiming "zero bash-4+
  features, so 3.2 suffices" was **refuted** during verification:
  `scripts/rewrite-commits-conventional:111` uses `mapfile -t` under
  `#!/usr/bin/env bash` — the repo *today* already has bash-4+ code on a
  `#!/bin/bash` path. Meanwhile the bootstrap fragments must target **3.2**
  (no `globstar`, no `typeset -g`, no `declare -A` / `[[ -v ]]` /
  `${var,,}` — all verified failing on 3.2.57). Recommended Requirements
  bullet: *"bash 3.2 (macOS stock) is the floor for fragments ≤74; brew
  bash 5.x is for interactive and standalone use."*
- **Chicken-and-egg on the direct-install path** — bash is installed at
  fragment **75**, after 10–74 run. On the README's
  `git clone && ./deploy.zsh` path anything ≤74 resolves to `/bin/bash`
  3.2, while `scripts/eris-macos-bootstrap.zsh:80` installs bash earlier —
  the same class of path-dependent skew CLAUDE.md documents for BSD
  userland. Fix: hoist to a `scripts/deploy.d/05_bash.zsh` (or guard in
  `10_dirs.zsh:4` next to `ensure_homebrew_path`) + a hard version assert
  in the driver.
- **No CI coverage** — `.github/workflows/automerge.yml` is the only
  workflow; no shell matrix.

---

## Recommended sequencing

Order the phases so each converts *silent* failures into either correct
behavior or loud ones. The mechanical sweep first removes ~1,000 sites of
noise; only then does driver work have a trustworthy signal to test against.

1. **Decide the contract** — dual drivers over shared fragments; secrets
   rendered in POSIX single-quote form both shells source identically;
   bash 3.2 floor for fragments ≤74.
2. **Mechanical sweep** — `have()` + `${+commands}` rewrite → `print` →
   `printf` → brace-group `;` → `zf_*` through the wrappers. Add a **dual
   `zsh -n && bash -n` gate** to the hooks.
3. **Semantic fixes** — 0-based loops + `"${arr[@]}"`, history modifiers →
   POSIX, expansion flags, `set -eE` with the counter fix, glob qualifiers →
   nullglob/`find`, extended_glob patterns → ERE.
4. **Driver + pin points** — `deploy.bash` twin, post-merge/pre-commit
   POSIX rewrites, launchd / `settings.json` / `chsh` / ranger depinning,
   `05_bash.zsh` hoist + version assert.
5. **Interactive layer** — `bash/` tree, `path_prepend`, fpath split
   (wrappers → `bin/`), setopt mapping, README/docs rewrite, CI shell
   matrix.
6. **Throughout** — grow CLAUDE.md's foot-gun table with the confirmed
   rows: brace-group trailing `;`, the `:h/:t/:r/:A/:l` modifier family
   (never errors), `${+commands}`, `path=()`, 1-vs-0 array indexing,
   `set -e` + `(( x++ ))`, and the `bash -n` false-pass caveat.

## Effort shape

~1,000 mechanical sites across ~50 files (concentrated in five idioms,
scriptable) + four discrete architectural projects: the driver split, the
`bash/` interactive layer, the secrets quoting contract, and pin-point
depinning.
