# dotfiles — agent instructions

## Shell-script portability (strict)

Scripts under `scripts/`, `scripts/deploy.d/`, `zsh/`, `bash/`, `bin/`, and
the top-level `deploy.zsh` / `deploy.bash` are the **bootstrap layer**. It is
**dual-shell** (since the bash-compat port — see `docs/bash-compatibility.md`):
zsh 5.x remains the primary driver, and everything both shells read — the
`scripts/deploy.d/` fragment bodies, `zsh/env.d/`, the git hooks — must parse
under **both** `zsh -n` and `/bin/bash -n` (bash 3.2 floor, see below). They
may run:

- on a fresh macOS where `brew` is not installed yet,
- on Linux (GitHub Actions, eris remote box),
- from non-interactive contexts (git hooks, cron, `bash -c '…'`) where the
  interactive gnubin PATH prepends (`zsh/rc.d/02b_gnubin_path.zsh`,
  `bash/rc.d/03_gnubin.bash`) have NOT applied.

**Rule:** every shell script in this repo must work with raw BSD userland on
macOS. Do NOT assume GNU sed/awk/date/coreutils. `scripts/deploy.d/75_brew_setup.zsh`
installs `coreutils`, `gnu-sed`, `gnu-tar`, `gawk`, `findutils`, `gnu-getopt`,
`grep`, `diffutils`, `moreutils`, `flock` — and `scripts/deploy.d/05_bash.zsh`
(hoisted ahead of fragments 10–74) installs a modern `bash`. The interactive
layers (`zsh/rc.d/02b_gnubin_path.zsh`, `bash/rc.d/03_gnubin.bash`) prepend
their gnubin dirs so the **interactive shell** gets GNU semantics for
`sed`/`find`/`xargs`/`awk`/`tar`/`getopt`/etc. — deliberately in rc.d, not
`env.d/`: macOS's `/etc/zprofile` runs `path_helper` after env.d and would
demote env.d prepends back behind `/usr/bin` (see the note in
`zsh/env.d/03_paths.zsh`). That is NOT a guarantee for scripts: git hooks,
cron, launchd jobs, and any `bash -c '…'` invocation may run before that PATH
wiring applies (or under a sanitised env entirely), so the bootstrap layer
(`scripts/`, `scripts/deploy.d/`, `zsh/`, `bash/`, `bin/`, top-level drivers)
must stay BSD-clean.

### BSD-vs-GNU foot-guns to avoid

| Don't write | Reason | Portable alternative |
|---|---|---|
| `sed -e '/x/{cmd1;cmd2}'` (block on one command) | BSD sed needs `{` and `}` on separate `-e`s | split `-e '…{'` `-e '…'` `-e '}'`, or use awk |
| `sed -i …` without arg | BSD requires `-i ''`; GNU rejects the empty arg | write to temp + `mv`, or guard per-OS |
| `date -d 'tomorrow'` / `date -d @1234` | GNU-only | BSD: `date -v +1d` / `date -r 1234`; or branch on `$OSTYPE` |
| `readlink -f path` | only on macOS ≥ 12.3 | hand-rolled symlink walk (see `scripts/generate-commit-msg:20-26`) |
| `realpath --relative-to=…` | GNU-only flag | compute manually with `${path#$prefix/}` |
| `stat -c '%a'` / `stat -f '%Lp'` | totally different flags per OS | branch on `$(uname -s)` (see `scripts/setup-caddy.sh:147-155`) |
| `getopt --long foo bar` | BSD `getopt` has no long-option support | hand-roll a `while/case` parser |
| `base64 -d` (decode) | BSD wants `-D` | `openssl base64 -d` works on both |
| `xargs -d '\n'` | no `-d` on BSD | `find … -print0 \| xargs -0` |
| `find … -printf '…'` | GNU-only | use `-exec printf` or pipe |
| `grep -P` (PCRE) | not in BSD grep | rewrite as ERE, or use `rg` if available |
| `cat -A` (show-all) | GNU-only | BSD: `cat -e` (only end-of-line) or `od -c` |
| `tar --xform` / `--wildcards` | bsdtar uses different flags | use `gtar` explicitly, or refactor |
| `gensub(…)` / `asort(…)` in awk | gawk-only | use `sub`/`gsub`, hand-roll sorting |

### zsh-vs-bash foot-guns to avoid

The bootstrap layer is **dual-shell** (zsh drivers + a bash 3.2 floor), so
zsh-only syntax in shared files is a portability bug, not a style preference
— and the worst failures are the ones where bash runs to completion, exits 0,
and does the wrong thing. First the disagreement that predates the port,
**word splitting**: zsh does not split unquoted parameter expansions; bash
does.

| with `v="a b c"`, `arr=(a b c)` | zsh | bash |
|---|---|---|
| `cmd $v` | **1 arg** (`a b c`) | 3 args |
| `cmd $arr` | 3 args | **1 arg** (`a`) |
| `cmd $(echo a b c)` | 3 args | 3 args |
| `cmd "$arr[@]"` / `"${arr[@]}"` | 3 args, empties kept | 3 args |

So, in this repo's dual-shell files:

- **Build word lists as arrays, never space-joined strings — and expand them
  quoted, `"${arr[@]}"`, always.** `cmd $pkgs` with `pkgs="a b c"` passes ONE
  argument even under zsh; unquoted `$arr` passes 3 args under zsh but ONE
  (`a`) under bash. Canonical pattern —
  `scripts/deploy.d/70_runtime_installs.zsh:75-85`: accumulate into
  `npm_packages+=("$pkg")`, then pass `"${npm_packages[@]}"`.
- **Command substitution is the exception**: unquoted `$(cmd)` *does* split.
  That asymmetry is what makes the broken string case look like it works.
- Unquoted `$arr` drops empty elements; `"${arr[@]}"` keeps them.

#### Silent semantic foot-guns (confirmed by the bash-compat port)

Every row below was hit and verified during the port (commits
`2a30ebd9..4cb67dca`): the construct **parses** under bash — usually
`bash -n`-clean — and does the wrong thing at runtime, exiting 0.

| Don't write | Reason | Portable alternative |
|---|---|---|
| `{ cmd }` / `fn() { … cmd }` — last command not `;`-terminated | zsh accepts `}` as a command terminator; bash wants `…; }` — and `zsh -n` cannot catch it, only the gate's bash leg does | end the body `…; }` (16 sites fixed across scripts/ and the interactive tree) |
| `${x:h}` / `:t` / `:r` / `:A` / `:l` history modifiers | never error under bash — pass through unchanged or come back empty (`${x:l}` no-op'd the linux gate in `50_mise.zsh`, silently skipping the mise install) | `dirname`/`basename`/`${p%.*}`; the symlink walk at `scripts/generate-commit-msg:20-26`; `tr` for case-folding |
| `(( ${+commands[x]} ))` | parses AND runs under bash — expands to `(( 0 ))`, always false, so every install/skip gate silently inverts | `have x` (`command -v` wrapper; `scripts/deploy.d/lib/helpers.zsh:7`) |
| `path=(new $path)` / `typeset -U path PATH` | bash parses it as a scalar `path=` assignment — PATH never changes, and each assignment clobbers the previous | `path_prepend DIR…` (`zsh/env.d/00_path_prepend.zsh:23` — zsh tied-array semantics, identical in both shells) |
| `${a[0]}`; `for (( i=1; i <= ${#a}; i++ ))` | zsh arrays are 1-based (slot 0 reads empty); bash is 0-based (looping from 1 skips row 0 — the secrets scripts skipped the primary credential env file and still wrote the success marker) | element iteration `for x in "${arr[@]}"`; restructure parallel arrays into `src\|dst` rows |
| `(( N++ ))` under `set -e` | arithmetic evaluates to the counter's OLD value — 0 the first time → exit status 1 → abort | `N=$((N+1))` |
| `${(f)…}`, `${(@f)…}`, `${(j:, :)…}`, `${(qq)…}`, `${~…}` | `bash -n` accepts them all; at runtime they are bad substitution or silently empty (host lists vanished, brew upgrades all skipped, exit 0) | hand-rolled splits/joins; POSIX single-quote splice (`scripts/secrets-render.zsh:51-61`) |
| `[[ -o interactive ]]` | unconditionally false in bash — load gates silently invert | `case $- in *i*) ;; *) return 0 ;; esac` |
| `producer \| grep -q …` under `pipefail` | the early-exiting grep SIGPIPEs the producer → 141 → the pipeline fails and the check inverts | `{ producer \|\| true; } \| grep -q`; end tolerant find pipelines `\| sort \|\| true` |
| `[[ $x == [^a-z]* ]]` | bash fnmatch ranges are locale-dependent — `[^a-z]` can match UPPERCASE on macOS | byte-based `tr -Cd 'a-z'` filter, or explicit character classes |
| commentary inside `<( … )` | bash 3.2's process-substitution paren scanner is comment-blind — quotes or backticks in a comment → runtime "no closing `)`" while `bash -n` passes | keep commentary out of procsub bodies |
| `set -eE` around process substitutions | errtrace propagates the ERR trap INTO procsubs, and pipefail turns tolerated `find` misses into bogus aborts | end such pipelines `\| sort \|\| true`; tolerate expected misses explicitly |

Related gotchas from the same port:

- **`-n` is parse-only, in both shells.** No `-n` gate can see word splitting
  or any runtime row above; `zsh -n` even has false positives of its own
  (`${(pl:$((…))::\n:)}` in argument position), which the gate arbitrates
  with `autoload -Uz +X` (`scripts/tests/shell-syntax-gate.sh:78-98`).
  Runtime semantics are covered by
  `diff <(./deploy.zsh --dry-run) <(./deploy.bash --dry-run)` (must be empty
  modulo timestamps) and the CI dry-run legs.
- **zwc completion caches are per-zsh-build.** Two zsh versions sharing a
  worktree (brew vs stock) leave stale `.zwc` files behind — delete them when
  completion misbehaves after a zsh upgrade.

#### The bash 3.2 floor

Fragments ≤74, both drivers, and the git hooks must run on macOS stock
`/bin/bash` 3.2 (asserted at driver startup, `deploy.bash:26-41`). Bash-4+
features are **forbidden** there — each verified failing on 3.2.57:
`globstar` (`**` silently degrades to `*`), `typeset -g`, `declare -A`,
`[[ -v var ]]`, `${var,,}`, `mapfile`, `&!`. Use `find` for recursive
globbing and `case` for assoc-array lookups. The interactive `bash/` tree and
the `bin/` wrappers target brew bash 5.x, where those features are fine.

### Preferred replacements

When the bootstrap is past the point where mise tools are guaranteed
(post-`50_mise.zsh`), prefer:

- `sd` over `sed` for simple substitutions
- `fd` over `find`
- `rg` over `grep -r`
- `bat` over `cat` for highlighting

The Rust replacements have identical behavior on macOS and Linux.

### When you hit a real portability bump

Three options, in this order of preference:

1. **Rewrite to be portable** — usually awk or pure-shell. See
   `scripts/generate-commit-msg:47-61` (`strip_fences`) for the canonical
   pattern: an awk block replaces a sed pipeline that broke on BSD.
2. **Branch on `$(uname -s)`** — only when behavior genuinely differs. See
   `scripts/setup-caddy.sh:147-155` for the model.
3. **Add a brew install to `eris-macos-bootstrap.zsh`** — last resort, only
   for tools the bootstrap *itself* doesn't need (chicken-and-egg).

### Verifying portability

Much of this is automated now — the layers, outermost first:

- **Pre-commit**: `scripts/pre-commit` runs
  `scripts/tests/shell-syntax-gate.sh --staged` over staged files under
  `scripts/` — each must parse under BOTH `zsh -n` and `/bin/bash -n`.
  `/bin/bash` is pinned deliberately: it is 3.2 on macOS (the fleet floor —
  a brew bash 5 first on PATH would accept more syntax than the oldest shell
  the bootstrap must survive) and the distro bash on Linux.
- **CI** (`.github/workflows/shells.yml`): the gate `--all` (whole tree —
  `zsh/`, `bash/`, `bin/`, both drivers, with a documented zsh-only exemption
  list), the `--staged` path replayed over a fully staged index, and both
  drivers' `--dry-run` with `DOTFILES_SKIP_BREW=1` on macOS (the 3.2 floor
  leg) and Ubuntu (bash 5.x + dash).

What no gate can see — still verify by hand before claiming a script change
is done:

- `-n` is parse-only. Word-splitting bugs and the silent semantic foot-guns
  above are runtime, not parse-time. Runtime equivalence is probed with
  `diff <(./deploy.zsh --dry-run) <(./deploy.bash --dry-run)` and the CI
  dry-run legs.
- For a script that builds an argument list, echo the command before running
  it and count the arguments.
- For sed/awk heavy scripts, eyeball-test with `cat -e` to verify newline
  handling (use `cat -e`, not GNU `cat -A`).

### Auditing portability across a repo

**Scan by shebang, not by extension.** Many scripts in this layout are
extensionless executables on PATH (e.g. `generate-commit-msg`,
`rewrite-commits-conventional`). A `rg -g '*.sh'` glob will silently skip
them. Prefer:

```
find scripts/ -maxdepth 2 -type f -exec sh -c \
  'head -1 "$1" | grep -qE "^#!.*(bash|zsh|sh)\b"' _ {} \; -print
```

Then run the foot-gun patterns (BSD sed `{…}`, `date -d`, `realpath
--relative-to`, `stat -c`, `getopt --long`, etc.) against that list.

## Memory / engram

This project is named `dotfiles` in engram. Save bugfixes, decisions, and
gotchas there — see the global memory protocol for cadence.

## Other notes

- `mise.toml` (under `configs/mise.toml`, symlinked to `~/.config/mise/config.toml`)
  is the source of truth for tool versions. Add new tools there, not in
  `deploy.zsh`.
- Brew is used only for things mise can't deliver: GNU userland, casks
  (iTerm2, fonts), `engram` tap. See `scripts/deploy.d/75_brew_setup.zsh`.
- The 1:1 deploy fragments under `scripts/deploy.d/` are loaded by
  `deploy.zsh` (or its bash twin, `deploy.bash`) in lex order. Two-digit
  prefix = phase.
- Keyboard scheme, GUI navigation, and tiling window management are documented in
  [`docs/keybindings/README.md`](docs/keybindings/README.md). macOS: Karabiner
  (`configs/karabiner/karabiner.ts`, generated) + AeroSpace
  (`configs/aerospace/aerospace.toml`, symlinked). Linux: keyd
  (`configs/keyd/default.conf` → `/etc/keyd`, via `79_keyd.zsh`) + Sway
  (`configs/sway/config`, symlinked).
- Other reproducible macOS settings (App Shortcuts like ForkLift ⌘⇧., Finder
  `defaults`, and `duti` default-app associations → VS Code) live in
  [`scripts/macos/`](scripts/macos/README.md) and are applied on macOS deploy by
  `scripts/deploy.d/77_macos_defaults.zsh`. It's change-aware (only relaunches
  Finder on an actual change) and drift-correcting, but backs up each overwritten
  value to `$XDG_STATE_HOME/macos-defaults/` first. `duti` is installed via brew
  (`75_brew_setup.zsh`). macOS doesn't sync these; Raycast/Text Replacements sync
  themselves.
- Office wired LAN: the office switch interconnects the planet boxes but has
  no router uplink, so ethernet gets no DHCP (internet stays on wifi).
  `scripts/setup-office-lan.sh` pins a static, gateway-less `10.77.0.x` on each
  box's wired NIC (last octet mirrors the box's wifi octet) so inter-box
  traffic takes the wire at line rate while the wifi default route is
  untouched. The fast-path `Match` blocks atop `ssh/config` probe wired →
  wifi → Tailscale, so `ssh ceres` etc. pick the fastest live path.
- File sharing: ceres serves `smb://10.77.0.74/downloads` (Samba,
  `configs/samba/smb.conf`, installed by `scripts/setup-ceres-share.sh`;
  `/srv/downloads` is its own btrfs subvolume so snapper root snapshots skip
  it). Mac-friendly via vfs_fruit; auth is the `ctaylor` Samba user
  (`sudo smbpasswd` on ceres to rotate). The laptop (quaoar) two-way syncs
  `~/Downloads` ↔ ceres `/srv/downloads` via Syncthing (pacman-installed for
  its `syncthing@ctaylor.service` unit — the one always-on-daemon exception
  to the mise rule; quaoar dials ceres's static wired/wifi/tailscale
  addresses, so it syncs from anywhere; `.stignore` keeps in-progress
  browser downloads out).
- Raycast *script commands* (Cloud Sync doesn't carry the script files) live in
  [`raycast/`](raycast/README.md) — e.g. `open-in-forklift.sh`. Add the dir once
  in Raycast settings; the files are version-controlled and ride along to every Mac.
