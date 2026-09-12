# Plex Media Server on makemake

Media server since 2026-09-11 (`plexinc/pms-docker`, version-pinned,
host-networked), libraries read-only off the external USB expansion drive,
hardware transcoding fully engaged on the N97's integrated GPU.

- Tracked stack shape: `configs/plex/docker-compose.yaml` → installed to `~/repos/deploy/plex/docker-compose.yaml`
- Tracked env template: `configs/plex/example.env` → seeds `~/repos/deploy/plex/.env` (**the real `.env` is never committed**)
- Installer: `scripts/setup-plex.sh`

**The deep runbook lives in the infra repo** (`~/.local/infra/manifests/makemake.toml`,
`container:docker:plex/plex` entry): the publish/CGNAT saga, the ADVERTISE_IP
and ALLOWED_NETWORKS constraints, BIF sizing, the Optimised Versions writable
hole, the Android client diagnosis. This document covers wiring and
reconstruction only, and points there for operational history.

## Why this lives here

`~/repos/deploy` is not a git repo (only its `rss/` subdir is, with no
remote), so the plex compose — 150 lines of load-bearing decisions — existed
on exactly one disk. Same disease immich had before 2026-09-03; same cure:
byte-identical tracked copies plus a drift-checking installer. The infra
repo's manifests declare and *verify* the deployment but do not reconstruct
the deploy tree; this does. Like immich, this is an interim home pending the
infra carve-out (see docs/immich.md's TODO section — plex is on that
candidate list now too).

## Sources of truth

| Artifact | Owner | Lands at |
|---|---|---|
| `docker-compose.yaml`, `example.env` | **this repo** (public) | `~/repos/deploy/plex/` |
| as-built manifest + services placement | `camerontaylor/infra`, `manifests/makemake.toml` + `services.toml` — **manifest edits are HUMAN-ONLY per infra AGENTS.md**; entry is DRAFT pending owner acceptance as of 2026-09-13 (uncommitted on makemake's clone) | `~/.local/infra/` |
| `plex.wedrifid.dev` vhost | `configs/caddy/` + `docs/caddy-ingress.md` (ceres ingress, dual-upstream wired→tailnet) | ceres caddy |
| `.env` | **machine-local only** — `PLEX_CLAIM` is a one-shot token (consumed and cleared 2026-09-11); `ADVERTISE_IP` must stay exactly `https://plex.wedrifid.dev:443/` or plex.tv rejects the publish (403, CGNAT) | `~/repos/deploy/plex/` |
| library DB + metadata + bundled Intel driver | on-host data, `chattr +C` (nodatacow) — re-apply +C on any recreation BEFORE first start | `~/plex/config` |

`configs/plex/` files are **byte-identical** copies of the live ones,
deliberately. `setup-plex.sh --check` reports any drift; `--force` converges
from the tracked copy.

## Install

```sh
scripts/setup-plex.sh --check     # report state; mutate nothing
scripts/setup-plex.sh             # apply
scripts/setup-plex.sh --prefix /tmp/scratch   # from-nothing proof, no live files
```

Idempotent; never touches a container. Fresh machine in order: run the
installer, prepare `~/plex/config` (+C) and the media binds, fetch
`https://plex.tv/claim` LAST (4-minute expiry), fill `PLEX_CLAIM` in `.env`,
then `docker compose up -d` — the one deliberate step.

## Hardware transcoding

Verified engaged 2026-09-13 (and end-to-end with a forced 4K→720p transcode
on 2026-09-11 — logs in the manifest entry):

1. `/dev/dri` passthrough in the compose (whole dir — the image's `start.sh`
   probes `card0` to pick a render node).
2. `group_add: "992"` — the **host's** `render` gid; PMS runs as `PLEX_UID`
   (1000), not root, so the supplementary group is what opens the node.
   **gid 992 is makemake-specific** (ceres' render gid is 987); the
   installer warns when the host's gid differs from the pinned one.
3. `HardwareAcceleratedCodecs=1` + `HardwareAcceleratedEncoders=1`,
   `HardwareDevicePath` pinned by PCI path to the Alder Lake-N.
4. Plex Pass active (the gate on hw transcoding) — confirmed via
   `myPlexSubscription=1` in the manifest evidence.

Unlike immich, all of this rode in files/prefs from day one — there was no
"passthrough but disabled" gap to close.

## Gaps

Known, deliberate, and not closed by this doc:

- **infra clone WIP**: makemake's `~/.local/infra` carries the plex manifest
  draft uncommitted, pending owner acceptance. Nothing here depends on it,
  but the two should land before the next fleet sweep reads them as drift.
- The live deploy dir holds `docker-compose.yaml.bak-*` files from the
  2026-09-11 bring-up sessions; untracked by design, safe to delete.
- No backup story for `~/plex/config` (the library DB): immich's restic
  tiers do not cover it. Rebuilding means re-claiming and re-scanning; the
  media itself is the source of truth, so this costs time, not data.
