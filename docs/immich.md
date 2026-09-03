# Immich deployment on ceres

Self-hosted photo library. Four containers on ceres, ML inference offloaded to
saturn, library snapshotted nightly to two restic tiers.

- Tracked stack shape: `configs/immich/docker-compose.yaml` → installed to `~/repos/deploy/immich/docker-compose.yaml`
- Tracked env template: `configs/immich/example.env` → seeds `~/repos/deploy/immich/.env` (**the real `.env` is never committed**)
- Installer: `scripts/setup-immich.sh`

## Why this lives here

Until 2026-09-03 `~/repos/deploy` was not a git repo at all. The compose file
that defines the photo library, and the systemd units that drive its nightly
backup, existed on exactly one disk — so losing ceres lost the ability to
rebuild the thing doing the backing up. The compose file and env template are
now tracked here; everything else already had a home and is pointed at, not
copied (see *Sources of truth*).

`configs/immich/docker-compose.yaml` is a **byte-identical** copy of the live
file, deliberately. Restoring it is a copy, not a merge, and
`setup-immich.sh --check` reports any drift between the two.

## Sources of truth

Four repos own pieces of this. The installer wires them together and owns none
of them.

| Artifact | Owner | Lands at |
|---|---|---|
| `docker-compose.yaml`, `example.env` | **this repo** (public) | `~/repos/deploy/immich/` |
| `immich-backup.sh`, `immich-prune.sh` | `camerontaylor/photo-steward` (private) `ops/` | symlinked into `~/repos/deploy/immich/bin/` |
| `hart-immich-*.timer`, `hart-immich-prune.service`, `hart-immich-backup.service.template` | same, `ops/` | copied/rendered into `~/.config/systemd/user/` |
| `dev.hart.immich-ml.plist`, `immich-ml-saturn.sh` (saturn's ML offload) | same, `ops/` | saturn's `~/Library/LaunchAgents/` and `~/.local/bin/` |
| `.restic-password`, `.b2-env` | `camerontaylor/dotfiles-secrets` (private) `services/immich/` | rendered into `~/repos/deploy/immich/` by `scripts/secrets-render.zsh` |
| `.env`, `.api-key` | **machine-local only** — see *Gaps* | `~/repos/deploy/immich/` |

The backup and prune scripts are **symlinks** into photo-steward, matching
ceres' fleet-wide convention that a unit and its script live in their owning
repo with `~/.config` pointing at them. A copy here would fork on first edit.

`hart-immich-backup.service` is the one unit in `~/.config/systemd/user` that
is a real file rather than a symlink into a repo: it carries `IMMICH_API_KEY`
inline, so it is rendered from `.template` at install time with the key
substituted, mode 600. A symlink would publish the key into a git repo.

## Install

```sh
scripts/setup-immich.sh --check     # report state; mutate nothing
scripts/setup-immich.sh             # apply
scripts/setup-immich.sh --force     # also converge a drifted compose/example.env
scripts/setup-immich.sh --prefix /tmp/scratch   # lay down a tree anywhere, no systemd
```

Idempotent. On a configured machine `--check` exits 0 with *"already installed
and consistent"*; anything else is drift or a missing credential, named.

**It never touches a container.** No up, down, restart, recreate or pull.
Timers are enabled (which schedules the next run) but no service is ever
started — starting `hart-immich-backup.service` would fire a 42 GiB backup
because a config script ran. Applying a changed compose file is a deliberate
human `docker compose up -d`.

Linux-only without `--prefix`: saturn and neptune run no Immich containers, and
saturn's ML offload is installed by photo-steward's launchd plist, not by this.
The script is **not** wired into `scripts/deploy.d/`, so a Mac `./deploy.zsh`
never reaches it; the OS guard is for a hand-run.

### Fresh machine, in order

1. `./deploy.zsh --only 65_secrets` — clones `~/.local/secrets`, renders what it can.
2. `git clone git@github.com:camerontaylor/photo-steward.git ~/repos/photo-steward`
3. `scripts/setup-immich.sh` — creates the deploy tree. Reports `.restic-password`
   and `.b2-env` missing, because `secrets-render.zsh` gates those rows on the
   deploy dir *already existing* (`_gate_open immich`). That is a chicken-and-egg
   this step breaks, not a bug.
4. `./deploy.zsh --only 65_secrets` again — now the gate is open and both render.
5. Fill `DB_PASSWORD` in `~/repos/deploy/immich/.env` (the installer seeds it
   with `CHANGEME` and blocks until it is gone).
6. `cd ~/repos/deploy/immich && docker compose up -d` — the one deliberate step.
7. Mint an API key in Immich (Account Settings → API Keys), write it to
   `.api-key` mode 600, re-run `setup-immich.sh` to render the backup unit.

## Backup

`hart-immich-backup.timer` at 03:15 nightly (+ up to 600s jitter).
`immich-backup.sh` triggers a database dump via the Immich API *first*, then
snapshots the filesystem — dumping second would let an asset land on disk that
the captured database has never heard of. Both tiers run even if one fails.

- local: `sftp:saturn:/Volumes/bigload/backup/immich`
- offsite: `b2:wedrifid-photos:immich`
- excluded: `thumbs/`, `encoded-video/` — regenerable from the originals.

The script hard-fails if saturn is unreachable or bigload is unmounted, rather
than writing a half snapshot or a silent no-op. `hart-immich-prune.timer` runs
`forget --prune` monthly.

## Gaps

Known, deliberate, and not closed by this doc:

- **`.env` and `.api-key` are machine-local.** `DB_PASSWORD` is baked into the
  postgres data directory at first init; `IMMICH_API_KEY` gates the pre-backup
  DB dump. Neither is in `dotfiles-secrets`, so a bare-metal rebuild of ceres
  cannot reproduce them — the library and the DB dump survive in restic, but
  the credentials that tie them together do not. Closing this means adding
  `services/immich/env.yaml` and `services/immich/api-key.enc` to
  `camerontaylor/dotfiles-secrets` plus two `_row` lines in
  `scripts/secrets-render.zsh` (gate `immich`). Not done here because it moves
  ownership of a live stack's `.env` to the renderer, which deserves its own
  change.
- **`DB_PASSWORD` cannot be rotated by editing `.env`.** It is the password
  postgres was initialised with. Changing it requires an `ALTER USER` inside
  the running container *and* the edit, in that order.
- The published port in the compose file is pinned to ceres' Tailscale address
  `100.82.17.115`. Another host needs that line changed.

## TODO: carve infra out of dotfiles into its own repo

**This directory is an interim home, not the intended one.** `configs/immich/`
and `scripts/setup-immich.sh` are *infrastructure* — the shape of a deployed
service — sitting inside a repo whose subject is *config preferences*: shell,
editor, keybindings, terminal. Those are different things with different
audiences, different change rates, and different blast radii. A broken keybinding
is an annoyance; a broken compose file is a photo library that will not start.

The precedent is already set: secrets were carved out of this repo into
**`camerontaylor/dotfiles-secrets`** in 2026-08, with `scripts/secrets-render.zsh`
as the seam between them. Infra should follow the same shape — its own repo,
its own lifecycle, a defined seam back to dotfiles — rather than accumulating
here indefinitely.

Candidates to move when that happens, i.e. everything in this repo that is
"how a machine is deployed" rather than "how I like my tools":

- `configs/immich/` + `scripts/setup-immich.sh` (this document)
- `configs/caddy/` + `scripts/setup-caddy.sh` + `docs/caddy-ingress.md`
- `scripts/setup-paseo.sh`, `scripts/paseo-watchdog`, `docs/paseo.md`
- `scripts/setup-t3.sh`, `scripts/setup-ceres-share.sh`, `scripts/setup-office-lan.sh`
- `configs/samba/`, `configs/portless/`, `configs/openclaw-mcp/`

Also unversioned and in scope for that repo when it exists: `~/repos/deploy/rss`
(a git repo with **no remote** — Miniflux + RSSHub + rss-bridge + the digest
timer, plus an unsnapshotted Postgres feed database) and `neptune:~/omc-browser`
(not a repo at all). The `setup-*.sh` + `configs/<service>/` pattern used here
extends to both without modification.

Recorded 2026-09-03, from Cameron: *"probably the script in immich and a setup
install script in dotfiles for now. (With another todo note that I intend to
split out infra from config preferences into separate repos, like secrets
already got a carve out.)"*
