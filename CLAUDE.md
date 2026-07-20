# dotfiles — agent instructions

## Shell-script portability (strict)

Scripts under `scripts/`, `scripts/deploy.d/`, `zsh/`, and the top-level
`deploy.zsh` are the **bootstrap layer**. They may run:

- on a fresh macOS where `brew` is not installed yet,
- on Linux (GitHub Actions, eris remote box),
- from non-interactive contexts (git hooks, cron, `bash -c '…'`) where
  `zsh/env.d/03_paths.zsh`'s gnubin PATH prepend has NOT applied.

**Rule:** every shell script in this repo must work with raw BSD userland on
macOS. Do NOT assume GNU sed/awk/date/coreutils. `scripts/deploy.d/75_brew_setup.zsh`
installs `coreutils`, `gnu-sed`, `gnu-tar`, `gawk`, `findutils`, `gnu-getopt`,
`grep`, `diffutils`, `moreutils`, `flock`, and a modern `bash` — and
`zsh/env.d/03_paths.zsh` prepends their gnubin dirs so the **interactive
shell** gets GNU semantics for `sed`/`find`/`xargs`/`awk`/`tar`/`getopt`/etc.
That is NOT a guarantee for scripts: git hooks, cron, launchd jobs, and any
`bash -c '…'` invocation may run before that PATH wiring applies (or under a
sanitised env entirely), so the bootstrap layer (`scripts/`, `scripts/deploy.d/`,
`zsh/`, top-level `deploy.zsh`) must stay BSD-clean.

### BSD-vs-GNU foot-guns to avoid

| Don't write | Reason | Portable alternative |
|---|---|---|
| `sed -e '/x/{cmd1;cmd2}'` (block on one command) | BSD sed needs `{` and `}` on separate `-e`s | split `-e '…{'` `-e '…'` `-e '}'`, or use awk |
| `sed -i …` without arg | BSD requires `-i ''`; GNU rejects the empty arg | write to temp + `mv`, or guard per-OS |
| `date -d 'tomorrow'` / `date -d @1234` | GNU-only | BSD: `date -v +1d` / `date -r 1234`; or branch on `$OSTYPE` |
| `readlink -f path` | only on macOS ≥ 12.3 | hand-rolled symlink walk (see `scripts/generate-commit-msg:14-19`) |
| `realpath --relative-to=…` | GNU-only flag | compute manually with `${path#$prefix/}` |
| `stat -c '%a'` / `stat -f '%Lp'` | totally different flags per OS | branch on `$(uname -s)` (see `scripts/setup-caddy.sh:111-119`) |
| `getopt --long foo bar` | BSD `getopt` has no long-option support | hand-roll a `while/case` parser |
| `base64 -d` (decode) | BSD wants `-D` | `openssl base64 -d` works on both |
| `xargs -d '\n'` | no `-d` on BSD | `find … -print0 \| xargs -0` |
| `find … -printf '…'` | GNU-only | use `-exec printf` or pipe |
| `grep -P` (PCRE) | not in BSD grep | rewrite as ERE, or use `rg` if available |
| `cat -A` (show-all) | GNU-only | BSD: `cat -e` (only end-of-line) or `od -c` |
| `tar --xform` / `--wildcards` | bsdtar uses different flags | use `gtar` explicitly, or refactor |
| `gensub(…)` / `asort(…)` in awk | gawk-only | use `sub`/`gsub`, hand-roll sorting |

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
   `scripts/generate-commit-msg:39-51` (`strip_fences`) for the canonical
   pattern: an awk block replaces a sed pipeline that broke on BSD.
2. **Branch on `$(uname -s)`** — only when behavior genuinely differs. See
   `scripts/setup-caddy.sh:111-119` for the model.
3. **Add a brew install to `eris-macos-bootstrap.zsh`** — last resort, only
   for tools the bootstrap *itself* doesn't need (chicken-and-egg).

### Verifying portability

Before claiming a script change is done:

- `bash -n scripts/the-script` (or `zsh -n` for `.zsh` files) — catches
  parse-time issues without executing.
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
  `deploy.zsh` in lex order. Two-digit prefix = phase.
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
- Raycast *script commands* (Cloud Sync doesn't carry the script files) live in
  [`raycast/`](raycast/README.md) — e.g. `open-in-forklift.sh`. Add the dir once
  in Raycast settings; the files are version-controlled and ride along to every Mac.
