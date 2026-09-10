# offload-home — neptune's Unix-side `$HOME` on the external drive

**Status:** decided 2026-09-08; fragment + runbook landed 2026-09-09; hardened
the same day after review (fail-fast at `08`, rsync verifier, tiered soak,
runtime-disconnect risk). **Executed 2026-09-10: 9 of 10 rows migrated.
`.local` is BLOCKED** — launchd cannot read the volume at all (see *The launchd
/ TCC wall*), which would take down every LaunchAgent on the host. Its 24G copy
is staged on the volume and verified; the fragment reports the row as CONFLICT
until the gate is resolved.
**Implementation:** [`scripts/deploy.d/08_offload_home.zsh`](../scripts/deploy.d/08_offload_home.zsh) — neptune-only, drift-correcting, runs **before `10_dirs`**.
**Scope:** neptune only — the always-on iMac with the WD SN810 NVMe (Thunderbolt, powered enclosure) at `/Volumes/offload`. **Never a laptop**: a drive absent at login breaks every agent and shell that resolves through `~/.local`.

## Decision

The Unix half of `$HOME` lives on the external volume behind compatibility
symlinks; the Mac half stays internal.

- **Move** (behind `~/<name> → /Volumes/offload/neptune/<name>`): `repos`,
  `.npm`, `.local`, `.cache`, `.config`, `.vscode`, `.colima`, `.gradle`,
  `.rustup`, `.cargo` — the dotdirs a Linux box would recognize.
- **Stay** on the internal disk: `~/Library` untouched, plus the macOS
  canonical folders (`Desktop`, `Documents`, `Downloads` (11G), `Movies`,
  `Music`, `Pictures`, `Public`, `Applications`), `.ssh` (36K — zero size
  upside, and the one directory where symlink + permission semantics must
  never have a bad day), `.Trash`.
- The symlinks are **declared state**, not scar tissue: the fragment verifies
  and drift-corrects them on every deploy, and prints the exact migration
  commands for anything not yet moved. No hand-added links accumulate.

The alternative — repointing the account itself (`NFSHomeDirectory` →
external volume) — was considered and rejected; see *Rejected alternatives*.

## Invariants

1. **`/Volumes/offload/neptune/<name>` is canonical forever.** pnpm, `uv`,
   venvs, and node bake absolute paths and `realpath` aggressively. Everything
   works as long as the `~/` link is created once and never re-pointed. If the
   canonical path ever has to change, that's a migration, not an edit.
2. **The manifest is the single source of truth.** The `offload_rows` array in
   `08_offload_home.zsh` defines the farm (plus per-row flags: `nocopy` —
   caches, the volume side is disposable; `regen` — regenerable, short soak);
   the PENDING output derives the migration commands from the same rows.
   Adding a directory = adding a row.
3. **`~/Library` and the macOS canonical folders never leave the internal
   disk.** That boundary is what retires the whole-home risk list: no
   login-on-external dependency, no SQLite/File-Provider databases on
   removable storage, no case-collision exposure (Apple's own warning about
   case-sensitive volumes), no path-keyed TCC re-grant storm.
4. **Case-sensitivity is a feature here.** `offload` is case-sensitive APFS —
   wrong for `~/Library`, right for XDG/Linux-faithful trees (matches CI and
   the Linux boxes). This is only coherent because of invariant 3.

## The partition (measured 2026-09-08)

| dir | size | tier | state | notes |
|---|---|---|---|---|
| `repos` | — | data | **migrated** (hand-linked 2026-09-06) | predates the fragment |
| `.npm` | ~0 | data | **migrated** (hand-linked 2026-09-08) | predates the fragment |
| `.local` | 24G | data | **BLOCKED** (copied + verified, not swapped) | mise 20G, pnpm 3G, claude 791M; the dotfiles + agents repos live under it — migrate last |
| `.colima` | 7.5G | data | **migrated 2026-09-10** | docker VM disk (container state — not regenerable without losing it); `colima stop` first. **SPARSE — copy with `rsync -aHAXS`, never `ditto`** (see Notes) |
| `.config` | 6.3G | data | **migrated 2026-09-10** | the hidden bulk is `.config/.android` at 5.5G (not raycast) — so `.android` is already inside this row, not a long-tail candidate |
| `.gradle` | 6.2G | regen | **migrated 2026-09-10** | `gradle --stop` first (daemon registry) |
| `.rustup` | 3.9G | regen | **migrated 2026-09-10** | |
| `.cache` | 2.4G | regen (`nocopy`) | **migrated 2026-09-10** | disposable — no copy at all; first row, proves the mechanics |
| `.vscode` | 1.1G | regen | **migrated 2026-09-10** | extensions; close VS Code first |
| `.cargo` | 483M | regen | **migrated 2026-09-10** | |

≈ 52G moves off the internal disk. Staying internal: `Library`,
`Downloads` (11G), the canonical folders, `.ssh`, and the long tail of agent
dirs (`.claude`, `.codex`, `.paseo`, `.gemini`, `.happy`, `.gjc`, `.omx`,
`.omc`, `.android`, `.docker`, …) — those join the manifest row-by-row once
they prove stable. `~/.tmp` is deliberately excluded (ephemeral;
`56_tmpdir_prune.zsh` owns it).

The tiers drive the soak (runbook step 7): **regen** rows keep their fallback
only until one good tool run; **data** rows keep it ≥ 1 week.

## Preconditions

**Ownership must be enabled on the volume.** With `Owners: Disabled`, APFS
mounts `noowners`: permission *enforcement* is off — mode bits are advisory,
`chmod 600` stops meaning anything, `chown` fails. Tolerable for repos;
untenable for a volume holding `~/.config/gnupg` and the `mise` shims that
front 20G of toolchains. (This is also why ssh/gpg get flaky on such volumes:
they stat the resolved file and enforce mode/owner checks themselves.)

```sh
sudo diskutil enableOwnership /Volumes/offload
sudo chown -R ctaylor:staff /Volumes/offload/neptune   # sanity pass over noowners-era writes
# replug or reboot once, then verify it persisted:
diskutil info /Volumes/offload | grep Owners            # must say Enabled
```

The fragment warns on every deploy until this is fixed. **Re-verify after any
replug/reboot, before the `.config` row moves** — mount options can revert,
and the warning fires only *after* a deploy has already written keys to a
`noowners` volume.

**The irreplaceable set must be handled before `.config` and `.local` move.**
Measured reality (2026-09-09): this Mac has *no* Time Machine destination at
all (`tmutil destinationinfo` → "No destinations configured"), and
`tmutil isexcluded /Volumes/offload` reports `[Excluded]` — so the repos
already on `offload` are single-copy **today**. Whole-volume TM is not a
blocker for this migration (most of the 52G is regenerable toolchain), but
these three are not:

- `~/.config/gnupg` — private keys. Export to the internal disk (`.backup` is
  not a farmed row, so it stays internal):
  ```sh
  mkdir -p ~/.backup/offload-prep && chmod 700 ~/.backup
  gpg -o ~/.backup/offload-prep/secret-keys.asc --armor --export-secret-keys
  chmod 600 ~/.backup/offload-prep/secret-keys.asc
  ```
- `~/.local/state` — agent logs/state: `tar -czf
  ~/.backup/offload-prep/local-state.tgz -C "$HOME" .local/state`
- Uncommitted work under `~/repos` (already on the volume, already
  single-copy — worth resolving regardless of this migration):
  ```sh
  for d in ~/repos/*/; do [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ] && printf 'DIRTY %s\n' "$d"; done
  ```

**The launchd / TCC wall — the gate that blocks `.local` (measured 2026-09-10).**
A process spawned by **launchd** cannot read *anything* on `/Volumes/offload`.
Not the program, not its data, not its log file. `diskutil info` reports
`Device Location: External`, which puts the whole volume in a TCC-protected
class, and a LaunchAgent has no TCC grant and no way to prompt for one (there
is no UI behind it). The denial is silent.

Reproduced with pairs of otherwise-identical agents:

| agent | result |
|---|---|
| `/bin/echo` → `StandardOutPath` on the volume | exit **78** (`EX_CONFIG`), log file never created |
| `/bin/echo` → `StandardOutPath` internal | exit 0, output written |
| `/bin/bash <script on volume>`, logs internal | `Operation not permitted` |
| `/bin/cat <plain text file on volume>`, logs internal | `Operation not permitted` |

The last row is the important one: an Apple-signed binary reading an ordinary
text file is denied, so this is **not** about exec bits, ownership, `nosuid`,
or symlink resolution — it is a blanket volume-scoped deny. Note the two
failure shapes: a bad *log* path kills the job in `xpcproxy` **before exec**
(78, empty stderr, no output at all), while a bad *program or data* path fails
after exec and does leave `Operation not permitted` in stderr — provided
stderr itself is internal.

This already bit the fleet: it is why the four `telemetry-ingest` agents and
`com.webfront.reap` have been dead since `repos` moved on **2026-09-06**, at
exit 78 with empty logs. Nothing announced it.

Migrating `.local` would extend that to the rest of the automation layer —
`prune-tmpdir`, `dotfiles.pull`, `neptune-swap-watchdog`, `smb-mount`,
`paseo-daemon`, `paseo-watchdog` — because their programs, their mise shims,
or both live under `~/.local`. **So `.local` does not move until one of these
is settled:**

1. **Grant Full Disk Access** to every binary launchd execs for these jobs
   (`/bin/bash`, `/bin/zsh`, and the mise shims' interpreter). GUI-only, per
   binary, not reproducible from this repo, and broad — FDA on `/bin/bash`
   is FDA for every bash on the machine.
2. **Keep `.local` internal permanently** and revise the Decision above. It is
   24G of the ≈52G, but it is also the only row the launchd layer depends on.
3. **Move the affected agents off `~/.local`** — programs and logs pinned to
   internal paths — so nothing launchd touches resolves onto the volume.

Partial mitigation already landed: `launchd_log_dir()` in
`scripts/deploy.d/lib/helpers.zsh` pins dotfiles-owned LaunchAgent
`StandardOutPath`/`StandardErrorPath` to `~/Library/Logs/dotfiles`
(internal by invariant 3) instead of `$XDG_STATE_HOME`. That fixes the *log*
half only; the program half still needs one of the three above.

**Idle spindown does not apply to this drive — do not set `disksleep`.**
`pmset -g` does report `disksleep 10`, which looks alarming, but that timer is
a *spindown* for rotational media and there is no motor here: `diskutil info
/Volumes/offload` reports `Protocol: PCI-Express`, `Solid State: Yes`. The
failure the setting normally guards against belongs to USB↔NVMe **bridge**
enclosures running their own idle timer under UAS, or to the host sleeping —
neither applies. This enclosure is an ACASIS TBU405AIR negotiated in
`Mode: Thunderbolt 3` at 40 Gb/s (`system_profiler SPThunderboltDataType`), so
the NVMe device is tunnelled PCIe with no SCSI translation layer, and system
sleep is off (`pmset -g` → `sleep 0`; `pmset -g log` records no sleep or wake
events at all across the current uptime).

Measured on 2026-09-09, 8d 9h uptime: **zero** `disk2`/`offload` mount or
unmount events in `log show --last 8d`, and the block driver reports 0 read
errors, 0 write errors and 0 retries across ≈504 GB read / ≈516 GB written.
`~/repos` has resolved through this volume continuously since 2026-09-06.

So `sudo pmset -a disksleep 0` is cargo cult here: `-a` is a global,
all-power-source change whose benefit on NVMe is zero, and it would also
disable spindown for any rotational drive later attached to this Mac. Re-open
the question only if the drive is ever moved into a USB enclosure — the
`log show` query above is the check that would show it going the other way.

**The verifier must be brew rsync 3.x.** `/usr/bin/rsync` on macOS is
openrsync, which misreports its version and differs in `-X`/`-A` behavior
(`docs/cli-tools.md`). Interactively `/usr/local/bin/rsync` (3.5.0) is first
on PATH; sanity-check with `rsync --version | head -n 1` before trusting any
`-n` output.

**Space is not a constraint** (measured 2026-09-09): internal `/` has 68Gi
available; `offload` has 354Gi of 373Gi free. The `~/<name>.pre-offload`
fallbacks will hold ≈52G on the internal disk during the soak — it fits, but
it is the tightest moment; clearing the regen-tier fallbacks early (runbook
step 3) relieves most of it. If Time Machine is ever configured, exclude
`~/*.pre-offload` or the first backup will walk all 52G of them.

## Fragment contract

`08_offload_home.zsh` runs per deploy, gated Darwin → hostname `neptune`,
**before `10_dirs.zsh`**. The ordering is load-bearing: both drivers run
`err_exit`, and `mkdir -p` through a dangling symlink exits 1 — with rows
migrated and the volume absent, `10_dirs` would abort the deploy with a bare
`mkdir: /Users/ctaylor/.config: No such file or directory` long before any
offload code ran. At 08 the volume state is handled first:

| volume state | farm state | action |
|---|---|---|
| `<dst>` root absent | no dangling `~/<name>` links | notice + skip (nothing to verify against) |
| `<dst>` root absent | links dangle | **fatal** — deploy stops at 08, naming every dangling row and the fix (remount) |
| mounted | — | ownership check (warns while `Owners: Disabled`), then the row walk |

Row walk (summary line counts each):

| `$HOME/<name>` | `<dst>` on volume | action |
|---|---|---|
| symlink → `<dst>` | exists | **ok** (counted, silent) |
| symlink → elsewhere | exists | **drift**: `deploy_ln -sfn` re-point |
| symlink (any target) | missing | **BROKEN** — printed, then the deploy **aborts** after the summary. Never auto-repointed: the target is canonical, so missing target = missing data |
| real dir (`nocopy`) | any | **PENDING [nocopy]**: prints `rm -rf <dst>` → `mv` aside → `mkdir` → `ln` — the volume side is declared disposable, so an existing dst is never a CONFLICT here |
| real dir | missing | **PENDING**: prints the two-pass commands (`caffeinate ditto` → quiesce → `rsync -n` → `rsync` → `mv`+`ln`) |
| real dir | exists | **CONFLICT**: prints an `rsync -aHAXn --itemize-changes` delta hint, touches nothing |
| absent | exists | **relink** (post-soak cleanup or restore-from-backup) |
| absent | absent | nothing — row not applicable yet |

After the walk, a **fallback nag pass**: any `~/<name>.pre-offload` present
prints `soak fallback present` (with the tier hint — regenerable rows say
"delete after one good tool run") and is counted, so the deploy keeps saying
it until the runbook's last step is actually done.

## Migration runbook

The per-row commands are exactly what the fragment prints when PENDING. Order
matters: `.cache` first to prove the mechanics, regenerables next, `.local`
last.

1. **Preflight** — ownership (above, verified *after* replug), backups
   (above), `rsync --version` (above), and enumerate
   `.config`'s hidden bulk: `du -sh ~/.config/.[!.]* 2>/dev/null | sort -h`.
   The fragment reports `.cache` as `PENDING [nocopy]` whose first command is
   `rm -rf /Volumes/offload/neptune/.cache`. **Do not run that command blindly
   — the "stale orphan" claim was falsified on 2026-09-10.** `~/.cache/npm` had
   since become a hand-added *symlink* onto the volume, so
   `/Volumes/offload/neptune/.cache/npm` was the LIVE 3.6G npm cache (7450
   files written in the preceding 5 days). `npm config get cache` returns the
   internal path only because it resolves *through* that link, which is exactly
   why the original check read as "nothing references the volume path". The row
   was migrated by running the `[nocopy]` commands **without** the `rm -rf`:
   the final path resolution is identical and the warm cache survives.
   Generally: before any `nocopy` `rm -rf`, check for child symlinks pointing
   into the volume —
   `find ~/<row> -maxdepth 3 -type l -exec readlink {} \; | grep /Volumes/`.
2. **Prove the mechanics on `.cache`** — run the fragment's printed
   `[nocopy]` commands verbatim: discard the orphan, move the internal cache
   aside, link a fresh dir. Then run something cache-warming (any npm/build)
   and `~/.local/dotfiles/deploy.zsh --only 08_offload_home` — the row should
   read `ok`, the summary `0 pending`. Delete `~/.cache.pre-offload` after a
   day of normal use (regen tier). Rollback if anything feels off:
   `rm ~/.cache && mv ~/.cache.pre-offload ~/.cache`.
3. **Regenerable tier — `.cargo`, `.vscode`, `.rustup`, `.gradle`** — per
   row, the printed two-pass commands:
   ```sh
   caffeinate -dimsu ditto ~/<name> /Volumes/offload/neptune/<name>   # bulk copy, live system
   # …quiesce the row (gradle --stop; close VS Code; exit builds)…
   rsync -aHAXn --delete --itemize-changes ~/<name>/ /Volumes/offload/neptune/<name>/ | head   # drift since the ditto
   rsync -aHAX --delete ~/<name>/ /Volumes/offload/neptune/<name>/   # catch up
   mv ~/<name> ~/<name>.pre-offload && ln -s /Volumes/offload/neptune/<name> ~/<name>
   ```
   Why two passes: a `ditto` of 6G `.gradle` runs for minutes, and anything
   written after it starts would be silently dropped by the `mv`. The
   quiesce → `rsync -n` → `rsync` sandwich narrows the loss window to
   seconds. The soak for this tier is one good tool run per row (`cargo
   build` in any Rust repo, launch VS Code, a rustc build, `gradle build`
   with the daemon restarted) — then the fallback goes; the fragment nags
   `soak fallback present … (regenerable)` until it does.
4. **Data tier — `.colima`, `.config`** — same two-pass shape, full quiesce
   first: `colima stop`; `gpgconf --kill gpg-agent` (gnupg lives under
   `.config`); close editors and apps reading `~/.config`. After the swap,
   verify `~/.config/gnupg` is still mode 700 on the volume —
   `stat -f '%Lp' ~/.config/gnupg` — ditto/rsync preserve it (Notes), check
   anyway.
5. **`.local`, last** — 24G, and the repo + every mise shim lives under it.
   - Quiesce hard: exit agent CLIs and editors; `cd /tmp` in every terminal
     (the `mv` renames the tree your shell lives under); optionally
     `launchctl bootout gui/$(id -u)/<label>` the periodic agents
     (telemetry-ingest ×4, prune-tmpdir, dotfiles.pull, swap-watchdog) for
     the window and `bootstrap` them back after. Even without that, the
     catch-up pass covers a mid-copy agent fire; only writes between the
     final `rsync -n` (empty) and the `mv` are at risk — a seconds-wide
     window.
   - The bulk `caffeinate -dimsu ditto` can run while you keep working; do
     the quiesce → catch-up → swap at a quiet moment. Repeat `rsync -aHAXn`
     until it prints nothing, then swap immediately.
   - **Run the swap from a cwd outside `~/.local`.** The existing dotfile
     farm needs nothing else — `~/.zshenv →
     /Users/ctaylor/.local/dotfiles/…` and friends resolve straight through
     the new `~/.local` symlink.
6. **Deploy + verify** — `~/.local/dotfiles/deploy.zsh` (path resolves
   through the link); the offload-home section should read `0 pending`.
   Reboot, then check the agents actually **ran**, not just that they're
   registered — `launchctl list` shows `PID  Status  Label`, and a job with
   no PID and a non-zero Status is failing (a TCC-ungranted job fails exactly
   this way, silently):
   ```sh
   launchctl list | grep -E 'telemetry-ingest|prune-tmpdir|dotfiles\.pull|swap-watchdog|colima'
   tail -n 20 ~/.local/state/<agent>.log     # one per agent — fresh lines post-boot
   colima status && docker ps
   mise ls && uv --version                   # shims resolve through the symlink
   echo $HOME                                # /Users/ctaylor — unchanged, by design
   ```
7. **Soak & rollback semantics** — data-tier fallbacks (`.config`, `.local`,
   `.colima`, plus the already-migrated `repos`/`.npm` trust) stay ≥ 1 week;
   the fragment nags, with the tier hint, until they're gone.

   > **TODO 2026-09-17 — delete the soak fallbacks.** The seven rows migrated
   > on 2026-09-10 left 27.9G of `~/<name>.pre-offload` on the internal disk:
   > `.cache` 2.4G, `.config` 6.3G, `.vscode` 1.1G, `.colima` 7.5G,
   > `.gradle` 6.2G, `.rustup` 3.9G, `.cargo` 483M. One week of normal use is
   > the agreed soak for all seven (longer than the `regen` tier strictly
   > needs — deliberately uniform, so there is one date to remember). On or
   > after 2026-09-17, if nothing has misbehaved:
   >
   > ```sh
   > for d in .cache .config .vscode .colima .gradle .rustup .cargo; do
   >     rm -rf "$HOME/$d.pre-offload"
   > done
   > ~/.local/dotfiles/deploy.zsh --only 08_offload_home   # expect: 0 fallbacks
   > ```
   >
   > Until then the fragment prints `soak fallback present` for each on every
   > deploy — that nag *is* the reminder, and it stops on its own once the
   > dirs are gone. Do **not** clear `.config` or `.colima` early: they are
   > `data` tier, and `.colima` holds container state that is not regenerable.
   > `.local` is not in this list — it never swapped (see Status).

   **Rollback is discard, not merge**: `rm ~/<name>` then `mv ~/<name>.pre-offload
   ~/<name>` — safe precisely because the fallback is untouched. Never sync
   volume-side changes *back* into a fallback before restoring: `offload` is
   case-sensitive and the internal disk is not, so two volume-side names
   differing only by case collide into one on the way back, silently.
8. **TCC** — first launches will prompt for removable-volume access (its own
   TCC category, distinct from Documents/Desktop). One grant per app.

## Risk register

| risk | exposure | mitigation / acceptance |
|---|---|---|
| login-time mount dependency | every agent that resolves through `~/.local` + all interactive shells: four `telemetry-ingest` agents (not five — `openclaw` is ceres-only) run `~/.local/share/mise/shims/uv`; `prune-tmpdir` and `dotfiles.pull` run from `~/.local/dotfiles` and log to `~/.local/state`; `neptune-swap-watchdog` runs `~/.local/bin/saturn-swap-watchdog.sh`; `homebrew.mxcl.colima` boots its VM from `~/.colima` | the enclosure is expected to mount before the login UI — **assumed, not yet measured**; the reboot in runbook step 5 is the test, and the agent status check there is how it reports. All listed agents are periodic/watched, not login-critical — worst case one missed interval, self-healed on next fire. Deploy-time: fragment 08 fails fast (naming the dangling rows + the fix) when the volume is absent — before `10_dirs` can abort cryptically. Once `.local` itself has migrated, a detached volume also makes the deploy *uninvocable* (the repo lives under the link) — recovery is remount, nothing to repair. Boundary: never extend to a laptop |
| **runtime volume loss** | a Thunderbolt bus reset, a physical unplug, or an enclosure power interruption unmounts the volume mid-session: every `~/.local` hot path — shims, agents, launchd jobs, shells with cwd under it — fails until remount; in-flight writes lost. Explicitly **not** idle-spindown: `disksleep` does not apply to NVMe (see Preconditions) | measured zero unmount events and zero I/O errors/retries across the 8-day uptime, so the residual is physical/link-level, not policy-level — there is no setting to turn off. Links are stable, so a remount heals it with no repair; worst case is the in-flight writes. This is the standing cost of the scheme and the reason it stays neptune-only |
| ownership off | see Preconditions | fragment warns every deploy until `enableOwnership`; re-verify after replug, before `.config` moves |
| **launchd cannot read the volume at all** | EVERY LaunchAgent whose program, data or log path resolves onto `/Volumes/offload` | **Not a prompt — a hard deny.** See *The launchd / TCC wall* under Preconditions. This is the gate blocking `.local`, and it already broke 5 agents when `repos` moved on 2026-09-06 |
| TCC removable-volume prompts (interactive apps) | GUI/terminal apps touching `/Volumes/*` | one-time per app; net prompts may *drop* (files leaving `~/Documents` leave that protected class). Interactive processes CAN prompt and be granted; launchd jobs cannot — that is the row above |
| path instability | venvs/pnpm/node bake absolute paths | invariant 1: links created once, never re-pointed; the volume path is canonical forever |
| EXDEV | `mv ~/f ~/.cache/x` crosses filesystems → copy+unlink instead of atomic rename | handled silently by gnubin `mv` and git; cosmetic |
| stale daemon/registry state after move | `.gradle` daemon registry, `.colima` VM | quiesce before the copy (runbook steps 3–4); worst case delete `~/.gradle/daemon/` and let it rebuild |
| Spotlight churn | indexing 50G of toolchain churn | optional: `mdutil -i off /Volumes/offload`; `rg` is unaffected either way |
| backups | **no TM destination configured at all** (2026-09-09); the volume is `[Excluded]` regardless | preflight covers the irreplaceable set (gnupg export, `.local/state` tar, repo dirty-sweep); decide TM scope separately — don't block the migration on 52G of regenerable toolchain |

## Rejected alternatives

- **Whole-home `NFSHomeDirectory` → external volume** (the original ask):
  login breaks if the drive is absent at auth; `~/Library` on external brings
  SQLite/File-Provider corruption exposure, case-collision breakage (Apple
  explicitly warns against case-sensitive volumes for homes), and a TCC
  re-grant storm; and the current disk split (400G `offload` + 112G empty
  container) would need container surgery to fit a Library-bearing home. The
  hybrid retires all of it — no `dscl` edit, no resize, case-sensitivity
  becomes correct.
- **`synthetic.conf` / symlinking `~` itself**: wrong grain, same
  login-on-external dependency.
- **Symlinking `~/Library/Caches` to the volume**: violates invariant 3 for a
  few GB; Library surgery for cache is the worst risk-per-byte trade on the
  table.
- **A dedicated per-host volume instead of the `/Volumes/offload/neptune/`
  subdir**: the subdir is already established by the repos migration; a
  separate volume buys nothing without Library living on it (which invariant 3
  forbids).
- **`diff -rq` as the post-copy verifier**: it follows symlinks and exits 2
  on any dangling link — and `~/.config` deliberately contains them
  (`20_symlinks.zsh` links `sway/config` on macOS as an inert dangling file),
  so the check would spew errors on the rows that matter most and give no
  signal. It also can't distinguish a preserved symlink from a dereferenced
  copy.

## Notes

- **Sparse files: `ditto` expands them, `rsync -S` does not (measured
  2026-09-10).** `.colima` is 7.5G by `du` but holds two sparse VM disks —
  `_lima/colima/disk` (20 GiB apparent / 1.53 GiB allocated) and
  `_lima/_disks/colima/datadisk` (100 GiB / 5.9 GiB). `ditto` writes every
  hole out in full, so the copy landed at **120G** and pushed the volume from
  19Gi to 158Gi used. `du` on the source reports *allocated* blocks, which is
  why the partition table's "7.5G" was accurate and yet useless as a copy
  estimate. Fix: delete the bloated files and re-copy with `rsync -aHAXS`
  (`-S` writes holes; `-H` still preserves hardlinks, so it covers what
  `ditto` was chosen for). Recovery brought it to 16G. Scan any new row before
  copying:
  ```sh
  find ~/<row> -type f -size +256M -exec stat -f '%z %b %N' {} \; \
    | awk '$2*512 < $1*0.9 {print "SPARSE", $3}'
  ```
- **The rsync verifier's pass condition is "zero non-xattr-only deltas", not
  "empty output".** Two things make empty unachievable:
  - `com.apple.provenance` is kernel-managed and records the code-signing
    identity of the *writing* process, so a copy always inherits the copier's
    identity and can never match a source written by a different signed app.
    `.vscode` (written by VS Code) reported 48,312 deltas, every one of them
    `x`-only and unfixable; `.cargo` (written by rustup, same identity as the
    copier) converged to empty. Zero `>f` transfers is the real signal.
  - Sockets cannot be created by any copier (`cS+++++++++`). Expect one delta
    per live socket — `~/.config/iterm2/sockets/secrets` is permanent.

  Filter with `grep -vE '^\.[fdLDS]\.{8}x '` (note the trailing space — the
  filename follows the flags, so a `$` anchor silently matches nothing).
- **`ditto` does not preserve symlink mtimes**, so the first drift check after
  a `ditto` always reports `.L..t......` on every symlink. The rsync catch-up
  pass has `lutimes` and clears it. Not drift.
- **Do not pipe the verifier into `head`.** The runbook printed
  `rsync … | head`, and `head` closing the pipe makes rsync die on EPIPE with
  `rsync error: … (code 13)` / `SIGUSR1 (code 19)` — a *fake* failure that
  looks like a broken copy (this is CLAUDE.md's `producer | grep -q` foot-gun).
  Redirect to a temp file and read that instead.
- **Copier/verifier behavior, measured 2026-09-09** (don't re-derive):
  `ditto` preserves symlinks *as* symlinks, intra-tree hardlinks (fresh
  inode, correct link count — this is why the 3G pnpm store survives the
  move), and modes including `700`. The verifier is the rsync dry-run
  (`rsync -aHAXn --delete --itemize-changes`; empty output = clean) — and it
  must be **brew rsync 3.x**, not `/usr/bin/rsync` (openrsync — see
  Preconditions).
- `20_symlinks.zsh` renders `gpg-agent.conf` into `$XDG_CONFIG_HOME/gnupg`
  with temp+`mv` — deliberately safe once `.config` lives on the volume (it
  already avoids following a stale symlink back into the repo).
- The deploy drivers themselves live in `~/.local/dotfiles`; after the
  `.local` row migrates, deploys run through the symlink, and the `abspath`
  walker in `lib/helpers.zsh` already resolves symlinked `SCRIPT_DIR`.
- Long-tail candidates to add as rows once stable: `.claude`, `.codex`,
  `.paseo`, `.gemini`, `.happy`, `.android`, `.docker`.
