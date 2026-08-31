# Bash compatibility — execution plans

Companion to [`bash-compatibility.md`](bash-compatibility.md) (the research
report). That doc says *what* is broken; this one sequences the fixes as
independently executable plans, **ordered by how automatic and how simple**
each is. Counts below were re-measured against the tree on 2026-08-31.

## The governing rule: zsh-identical first

Every plan in the numbered sequence (P0–P7) contains only rewrites whose
behavior under zsh is **byte-identical** to today's. That is what makes them
the "easy" tier: they can land immediately, one at a time, verified against
current production usage (`./deploy.zsh --dry-run`, live shells), with no
bash driver existing yet. Anything that requires per-shell divergence or a
parallel layer is deferred to the **lanes** at the end.

Two corrections to the research doc's suggested fixes, discovered while
planning — both would *break zsh* if applied as written, so they are lane
material, not sweep material:

- **Do not rebase index loops to 0.** zsh arrays have no element 0;
  `for (( i = 0; i < ${#a[@]}; i++ ))` under zsh reads an empty slot and
  drops the last element. The dual-shell fix is `for x in "${arr[@]}"`
  where possible, or restructuring parallel arrays into `src|dst` rows
  (→ Lane D).
- **Plain glob + `[ -e ]` guard is not zsh-identical on its own.** zsh's
  default `nomatch` aborts on an unmatched glob (and `deploy.zsh` sets
  `err_exit`); bash passes the pattern through. It needs either the
  nullglob prelude (P7) or a `find`-based rewrite.

## Automation posture

There is no zsh→bash transpiler and cannot be a deterministic one (no
zsh-compatible parser exists outside zsh; shfmt and ShellCheck both refuse
zsh). The workable loop is **enumerate → scripted rewrite of exact shapes →
flagged residue → verify**:

- The two big sweeps (P3, P4) are scriptable because the call sites collapse
  into a handful of exact textual shapes (enumerated per-plan below).
  Scripted `perl -pi` handles the shapes; anything not matching a known
  shape is *flagged, not converted*.
- **ShellCheck becomes usable only after a file's shebang flips** to
  sh/bash — so it verifies P2's hooks/pager rewrites and the eventual
  `deploy.bash`, but not the `.zsh` files. For those, the gates are
  `zsh -n`, before/after `--dry-run` diffs, and the pattern-count metric
  (P0).
- `bash -n` has documented false passes (`${+commands}`, history modifiers
  never parse-error), so "files passing `bash -n`" is a *progress* metric,
  never a done signal.
- Optional runtime probe: run dry-run-safe scripts under
  `zsh -o shwordsplit -o ksharrays -o nomatch` and diff the output — those
  options make zsh act bash-like, so divergence there is a real portability
  bug. Dry-run paths only; the options change live semantics.

## Sequence at a glance

| # | Plan | Sites | Automation | Effort | Risk |
|---|------|------:|------------|--------|------|
| P0 | Measurement harness | — | full (it *is* the automation) | ~30 min | none |
| P1 | One-sitting hand fixes | ~43 | grep-guided hand edits | 1–2 h | none |
| P2 | Three tiny POSIX rewrites (pager, hooks) | 3 files | manual but ShellCheck-verifiable | 1–2 h | low |
| P3 | `${+commands[…]}` → `have` | 182 / 55 files | scripted shapes + residue | ½ day | low |
| P4 | `print` → `printf` | ~600 / ~40 files | scripted shapes + residue | 1 day | medium |
| P5 | `zf_*` → wrappers + plain commands | ~30 + 2 wrappers | sed-able rename | 2 h | low |
| P6 | Array expansion quoting | ~dozens | semi-auto (per-file var census) | ½ day | medium |
| P7 | Formulaic residue (modifiers, globs, flags) | ~85 | manual, formulaic | 1–2 days | medium |
| A–E | Lanes (zsh-feature work) | — | manual / architectural | projects | — |

---

## P0 — Measurement harness (do first)

A `scripts/audit-bash-compat` (or a documented block in this file) that
prints per-pattern counts and per-file `bash -n` status. The sweeps are only
trustworthy if the residue count visibly goes to ~0.

Baseline as of 2026-08-31 (excluding `tools/vendor/`):

```
${+commands[…]}          182 sites / 55 files
print (all variants)     ~600–700 sites / ~40 files
rehash                    18
unfunction                 6
&!                         4
(( x++ )) counters        11
glob qualifiers (N…)      16
expansion flags ${(f)…}…  40
missing ';' before '}'     4
```

Count commands (each is the plan's own verifier):

```sh
rg -o '\$\{\+commands\[' deploy.zsh scripts zsh tools configs | wc -l
rg -o '(^|[;&|{(\s])print( -[A-Za-z-]+)*\b' deploy.zsh scripts zsh tools | wc -l
rg -n '\brehash\b|\bunfunction\b|&!' deploy.zsh scripts zsh tools
rg -n '\(\( *[A-Za-z_]+\+\+ *\)\)' scripts zsh deploy.zsh
rg -n '\(N[.)/@,L0-9]*\)' deploy.zsh scripts zsh
```

---

## P1 — One-sitting hand fixes (~43 sites, zero risk)

All grep-located, all mechanical, all byte-identical under zsh. One commit.

1. **Missing `;` before `}`** — 4 sites: `scripts/prune-tmpdir:40,45`,
   `scripts/deploy.d/40_tools.zsh:102`, `scripts/deploy.d/73_tailscale.zsh:115`.
   bash parse errors; `zsh -n` cannot catch them, so grep is the only net.
2. **`(( x++ ))` → `x=$((x+1))`** — 11 sites (`scripts/secrets-render.zsh`
   ×8, `scripts/deploy.d/82_zsh_completions.zsh` ×3). Under bash `set -e` a
   post-increment from 0 returns status 1 and aborts; the assignment form is
   unconditionally safe in both shells.
3. **`rehash` → `hash -r`** — 18 sites. zsh's `hash -r` is the documented
   equivalent of `rehash`.
4. **`unfunction f` → `unset -f f`** — 6 sites. Identical in zsh.
5. **`&!` → `& disown`** — 4 sites (`zsh/fpath/evalcache:41`,
   `zsh/rc.d/11_portkey.zsh:335,337`, `zsh/rc.d/15_completion.zsh:53`).
   These live in interactive-lane files, but the spelling is identical in
   zsh and free to do now.

Verify: `zsh -n` each touched file; pattern counts → 0.

---

## P2 — The three tiny POSIX rewrites

Not scripted, but each is ≤15 lines, self-contained, and — because the
shebang flips to `sh` — fully **ShellCheck-verifiable**, the only tier where
the lint-then-fix loop applies end-to-end today. These also remove the
worst bash-only-host failures (every `git diff` and every commit).

1. **`tools/git-diff-pager`** → `#!/bin/sh`; body:
   `command -v delta >/dev/null 2>&1 && exec delta …` else
   `exec less --RAW-CONTROL-CHARS --quit-if-one-screen`.
2. **`scripts/pre-commit`** → POSIX; replace `${0:A:h}` with the repo's
   canonical symlink walk (`scripts/generate-commit-msg:14-19`).
3. **`scripts/post-merge`** → POSIX; keep the `exec zsh` handoff but guard
   with `command -v zsh` and **fail loud** when missing (today's failure
   mode is a green-looking `exit 0` that leaves the box drifting forever).

Verify: `shellcheck` clean, `sh -n`, then a real commit + a real
`git pull` on-box.

---

## P3 — `${+commands[…]}` → `have` (182 sites / 55 files, scripted)

The research doc's highest-leverage single substitution. `command -v` is
POSIX and behaves identically in zsh, so this is a pure sweep.

**Helper placement** (verified: only `deploy.zsh` sources `helpers.zsh`, so
fragments inherit; nothing else does):

- `scripts/deploy.d/lib/helpers.zsh` — add once; all fragments get it:

  ```sh
  have()   { command -v -- "$1" >/dev/null 2>&1; }
  isfunc() { typeset -f -- "$1" >/dev/null 2>&1; }
  ```

- `zsh/` interactive files — add the same two lines to a new early
  `zsh/env.d/00_compat.zsh` (loads before everything that uses it).
- Standalone scripts (`secrets-render.zsh`, `prune-tmpdir`, …) — inline the
  one-line `have()` at the top of each; matches the repo's self-contained
  script pattern.

**Scripted shapes** (measured; these cover all but a handful of sites):

| shape | rewrite |
|---|---|
| `(( ${+commands[X]} ))` | `have X` |
| `(( ! ${+commands[X]} ))` | `! have X` |
| `(( ${+commands[$v]} ))` | `have "$v"` (incl. `have "g$name"` interpolations) |
| `${commands[x]:-/fallback}` | `$(command -v x || printf '%s' /fallback)` |
| `(( ${+functions[X]} ))` | `isfunc X` |

**Flagged residue** (hand work): compound arithmetic joining two probes
(`(( a && b ))` → `have a && have b`); `${+terminfo[…]}`
(`zsh/rc.d/05_keys.zsh:106`, `20_cursor_shape.zsh:5`) has no bash analogue →
defer to Lane C.

Verify: pattern count → 0 (minus deferred terminfo sites); `zsh -n`;
`./deploy.zsh --dry-run` output diff is empty.

---

## P4 — `print` → `printf` (~600 sites, scripted with a hard guard)

Measured variant distribution — the doc's 4-row table covers ~99%:

```
print <args>       ~85%     print -u2 --   21     print --   3
print -r --          64     print -u2      10     print -n   2
print -rn --          7     print -Pn       1
```

| zsh | bash/zsh-identical |
|---|---|
| `print "msg"` | `printf '%s\n' "msg"` |
| `print -u2 [--] "msg"` | `printf '%s\n' "msg" >&2` |
| `print -r -- "$x"` | `printf '%s\n' "$x"` |
| `print -rn -- "$t"` | `printf '%s' "$t"` |
| `print -n "msg"` | `printf '%s' "msg"` |

**The one hard rule that bounds automation:** `printf` repeats its format
per argument. `print a b` prints one space-joined line; `printf '%s\n' a b`
prints **two lines**. The sweep script therefore auto-converts only
**single-argument** calls (one quoted string or one word) and *flags*
multi-arg calls for hand conversion (usually `printf '%s\n' "a b"` or
`"$*"`). And never `printf "$msg"` — a `%` in a secret value becomes a
format directive (47 of the `print -r --` sites author files, including the
rendered-secrets env body).

Do it **file-by-file with diff review**, not one repo-wide sed:
`helpers.zsh` first (sourced before everything), then fragments in lex
order, then standalone scripts, then `zsh/`.

**Residue:** `print -Pn` (`zsh/rc.d/07_terminal_title.zsh:9`, prompt
escapes) → hand-written escape sequence, or defer to Lane C.

Verify: `zsh -n`; `--dry-run` diff empty; for the file-authoring sites,
byte-compare a rendered secrets env / systemd unit before vs after.

---

## P5 — `zf_*` builtins → wrappers + plain commands (~30 sites)

`deploy.zsh:84`'s `zmodload` injects `zf_mkdir`/`zf_ln`/`zf_chmod`/`zf_rm`
— the only filesystem mutations in the deploy. Two edits:

1. In `scripts/deploy.d/lib/helpers.zsh:8-22`, change the wrapper
   passthroughs `zf_ln "$@"` → `command ln "$@"` (same for mkdir). All
   flags in use (`-p`, `-sfn`, `-m 700`) are BSD-clean.
2. Route the ~30 *direct* `zf_*` call sites through the `deploy_*` wrappers
   (add `deploy_chmod`/`deploy_rm` if needed) — a sed-able rename that also
   extends `--dry-run` coverage to those sites as a side benefit.

Leave the `zmodload` line in `deploy.zsh` until Lane A retires it (harmless
under zsh once nothing calls `zf_*`).

Verify: `rg -n '\bzf_'` → helpers only, then nothing; `--dry-run` diff
(will legitimately *grow* by the newly covered sites — eyeball those).

---

## P6 — Array expansion quoting (semi-automatic)

Rewrite `cmd $arr` → `cmd "${arr[@]}"` and `for x in $arr` →
`for x in "${arr[@]}"`. In zsh the quoted form is identical except empties
are **kept** — which is the robustness direction the research doc wants
anyway. This is the CLAUDE.md-documented divergence, live at the policy's
own canonical site (`scripts/deploy.d/70_runtime_installs.zsh:50,75`) and
destructive under bash at `scripts/prune-tmpdir:108`.

Why only semi-automatic: no regex can know which names are arrays. Per
file — census the array vars (`typeset -a`, `local -a`, `+=(`, `=(`), then
rewrite *those names'* unquoted expansions; review the diff. Scalar `$var`
sites stay untouched (quoting them is good hygiene but out of scope here).

Also: update CLAUDE.md's zsh-vs-bash table to state `"${arr[@]}"` as the
**required** spelling, not just an option.

Verify: `zsh -n`; `--dry-run` diff; the runtime-probe trick
(`zsh -o shwordsplit -o ksharrays` on dry-run paths) is at its most useful
in this plan.

---

## P7 — Formulaic manual residue

Each class has a canonical replacement; none is scriptable; all are
zsh-identical *if done as specified*.

1. **History modifiers in fragments** (~10 sites in `scripts/deploy.d/`):
   `${x:t}` → `${x##*/}` · `${x:h}` → `${x%/*}` (or `dirname`) ·
   `${x:r}` → `${x%.*}` · `${DOTFILES_OS:l}` → `tr '[:upper:]' '[:lower:]'`
   (this one un-breaks mise install on a future bash driver —
   `50_mise.zsh:7-8`). Leave standalone scripts' `${0:A:h}` self-location
   alone for now: their shebangs are zsh and stay so until their lane; the
   hooks that need it now are handled in P2.
2. **Glob qualifiers** (16 sites): prefer `find … -print0 | while IFS= read
   -rd '' …` (or `-exec`) in the bootstrap layer — fully portable, and
   sidesteps bash 3.2's missing `globstar` for the `**` sites
   (`30_submodules.zsh:37`). Where a plain loop reads better, it needs the
   dual prelude first: `setopt null_glob 2>/dev/null || shopt -s nullglob`
   (in `helpers.zsh`); the bare `[ -e ]` guard alone is not zsh-safe under
   `nomatch` + `err_exit`.
3. **Expansion flags** (40 sites): `${(f)"$(cmd)"}` → `while IFS= read -r`
   loop (not `mapfile` — bash-4+ and not zsh) · `${(j:, :)arr}` → a small
   `join_by()` helper · `${a:|b}` set-difference (`75_brew_setup.zsh:54`) →
   a loop filter · `${(q)…}`/`${(qq)…}` in the secrets renderer belongs to
   Lane D's quoting contract, don't touch here.

---

## Lanes — the zsh-feature work (after or parallel, as separate projects)

These require per-shell divergence, new files, or contract decisions — the
research doc's §A/C/D/E territory. Rough dependency: A unblocks testing
fragments under bash at all; B and C are independent; D has its own
correctness stakes; E rides along everything.

- **Lane A — deploy driver twin.** `deploy.bash` (or POSIX-ized driver)
  over the same fragments: nullglob dispatch loop, `case` membership for
  `--only`, `set -eE -o pipefail` + trap contract, the fragment
  function-wrap decision (fixes file-scope `local`, ~220–255 lines / 26
  files, in one move), `05_bash.zsh` hoist + version-floor assert
  (bash 3.2 for fragments ≤74).
- **Lane B — remaining pin points.** `configs/ai/claude-code/settings.json`
  `CLAUDE_CODE_SHELL` (delete or render per-host), launchd/systemd runner
  paths from env (`99_periodic.zsh:67`, `56_tmpdir_prune.zsh:32`), ranger
  `z` → zoxide, `chsh` behind a `DOTFILES_SHELL` knob, `cc-worker.sh` port
  to actual bash.
- **Lane C — interactive `bash/` tree.** `.bash_profile`/`.bashrc` +
  `bash/env.d`/`rc.d`, `path_prepend()` replacing the 10 no-op `path=(…)`
  sites, the 29-option setopt→bash mapping, fpath split (pure CLI wrappers
  → `bin/` executables serving both shells; zle/prompt ones stay zsh),
  `.inputrc`, `[[ -o interactive ]]` → `case $- in *i*)`, anonymous
  functions → named+`unset -f`, `always` blocks → explicit restore,
  README zero-home-presence rewrite.
- **Lane D — secrets correctness.** The quoting contract (render POSIX
  single-quote `'\''` form both shells source identically, replacing
  `${(qq)…}`), the 1-vs-0 parallel-array restructure of
  `secrets-render.zsh`/`save`/`restore`/`sops-add-recipient` (rows, not
  index rebasing), the `extended_glob` dotenv-alias pattern → `[[ =~ ]]`
  ERE. Highest correctness stakes in the repo; do as one reviewed project
  with byte-compare fixtures.
- **Lane E — enforcement.** Dual `zsh -n && bash -n` gate in the hooks
  (only once P1–P5 make it green), a CI shell matrix, and growing
  CLAUDE.md's foot-gun table with the confirmed rows: trailing `;` before
  `}`, the `:h/:t/:r/:A/:l` family (never errors), `${+commands}`,
  `path=(…)`, 1-vs-0 indexing, `set -e` + `(( x++ ))`, `bash -n` false
  passes, and `printf`'s repeat-format trap.
