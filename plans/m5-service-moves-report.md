# M5 service moves — execution report (RSS → makemake, immich → makemake)

Date: 2026-09-08. Executor: GLM-5.3 agent session on ceres, ssh to makemake.
Brief: M5 of `docs/fleet-consolidation.md` — stand up `services.toml`, rehearse a
real service move, then move immich gated on a tested backup restore.
Companion docs: `~/.local/infra/services.toml` (branch `m5-services-toml`),
manifest drafts in `~/.local/infra/manifests/{ceres,makemake}.toml` (same branch).

Fences honored: no data deleted anywhere (all ceres state retained as the
rollback path); no changes on saturn/neptune/pluto/quaoar/eris; no plaintext
secret values in this report (paths only); `docs/fleet-consolidation.md` move
table untouched; `git status` re-run before every commit (concurrent agents
were active in `~/repos/deploy` and photo-steward during this session).

## Outcome in one paragraph

RSS moved to makemake and the rollback path was exercised end-to-end (M5's
"a real service, ceres → makemake, and back"). The immich restore drill
passed on every axis, which opened the immich move; immich was then moved with
a pre-seeded transfer that held total service downtime to **22 seconds** (the
downtime copy was just the delta + a quiesced pgdata re-tar). `services.toml`
exists and carries both services with as-built runbooks. Ceres retains full
rollback copies of both stacks; their deletion is deferred to the owner as
follow-ups.

## Phase 0 — services.toml + inventory

- `~/.local/infra/services.toml` created (schema_version 1) with `[services.rss]`
  and `[services.immich]`: assigned host, implementation refs, declared state
  paths, secret refs (paths only), ports/dependencies, health checks,
  backup+restore procedure, migration constraints + runbook + rollback. Header
  states what it deliberately is NOT (scheduler, second ledger, secrets store).
  Commits `bb016bd`, `a19ac46` on branch `m5-services-toml` (pushed).
- Manifest drafts on the same branch: ceres rss containers → `retire`/`absent`
  (5 containers + 2 digest units); makemake rss containers → `adopt`/
  `present-enabled` + digest units. Both manifests pass `converge validate`.
- Brief corrections found by verification (all confirmed against live state):
  - RSS has **no valkey** — the stack is db + miniflux + rsshub + rss-bridge +
    digest-web, plus the host-side `rss-digest.{service,timer}`.
  - The running rss-bridge image is `rssbridge/rss-bridge:latest` (hyphen);
    the no-hyphen `rssbridge/rssbridge:latest` tag is gone from Docker Hub.
  - An uncommitted local edit had rewritten the ceres compose to the dead
    no-hyphen tag; it was a **phantom dirty file** (concurrent agent,
    reverted mid-session) — ceres HEAD always had the correct hyphen tag.
    My makemake copy normalized to the live tag.
  - Pre-existing, not fixed (out of scope, reported below): portkey gateway on
    ceres answers 500 to the digest scoring leg (`rss-digest.service` failing
    since ≥ Sep 6). Reproduced from makemake over the tailnet, which doubles
    as proof the cross-host PORTKEY_URL path works.

## Phase 1 — RSS move (the rehearsal)

As-built (full detail in `services.toml` `[services.rss.migration]`):

- Stack rsynced to `makemake:~/repos/deploy/rss`; host edits: ports bind +
  `BASE_URL` → `100.87.185.24`, db image → `pgvector/pgvector:pg18` (owner
  ruling: RSS ends up on latest postgres with pgvector), db volume mount →
  `/var/lib/postgresql` (postgres 18 images reject `.../data` — discovered
  live, recorded as a constraint), `digest.py` `MINIFLUX_URL` → makemake,
  `PORTKEY_URL` stays on ceres.
- `docker-compose-v2` installed on makemake via apt (the brief's predicted
  blocker — real, resolved without owner action).
- Data: 31 MB `pg_dump` from ceres `postgres:17-alpine` → restored into the
  new pg18 container with **0 errors**; `CREATE EXTENSION vector` (0.8.6).
  Counts: feeds 25/25 exact, users 1/1 exact, entries 3073 vs 3071 (+2 live
  drift — ceres was still polling at dump time, expected).
- Verification: `compose ps` all healthy; `curl :8090` → 200; HTTP Basic
  `/v1/me` → 200 (admin, 25 feeds) — Basic auth, NOT the bearer/login probe
  the brief assumed; manual poll via `miniflux -refresh-feeds` refreshed a
  feed in 450 ms; digest-web answers 200.
- `rss-digest.{service,timer}` copied, timer enabled **and started**
  (enable alone arms at next login — learned live); next run Wed 2026-09-09
  06:37.
- Boot-race drop-in installed on makemake
  (`/etc/systemd/system/docker.service.d/10-after-tailscale.conf` +
  `/usr/local/bin/wait-for-tailscale-ip.sh`, `WAIT_TS_IP=100.87.185.24`),
  matching the ceres rollout; daemon-reload done, effective next boot.
- Ceres: `docker compose down` (volume `rss_miniflux-db` INTACT), digest
  timer `disable --now`.
- **Rollback exercised** (M5's "and back"): ceres `compose up -d` → full
  stack healthy, 200 on `100.82.17.115:8090` within ~30 s → `down` again.
  makemake serves.

## Phase 2 — immich restore drill (gate for Phase 3): PASSED

Every axis green; the gate was real, not ceremonial:

- B2 repo integrity: `restic check` — **no errors** (19 snapshots).
- Selective restore of latest snapshot `14d4aa73` (1.918 GiB test subset) in
  5:40 — newest DB dump in `library/backups/` byte-identical; **14/14 sampled
  library files checksum-match** (sizes 5 KB → 1.1 GB, includes a
  spaces-in-name file and videos).
- Dump loaded into a throwaway pinned-postgres container in 35 s, **zero
  errors**; row counts exact vs live (asset 26118, asset_file 78104,
  asset_exif 26115, user 1); extensions intact (`vector` 0.8.1, `vchord`
  0.4.3).
- Saturn local tier alive: 19 snapshots, latest `1fd6ad33` 2026-09-08 03:18.
- All drill artifacts cleaned up (throwaway container + volume + scratch dir).

## Phase 3 — immich move

Preconditions verified before any downtime:

- Prep on makemake (all before ceres stopped): 4 pinned images pulled
  (digest-pinned postgres + valkey, `:v3` server + ML); restic 0.19.1 binary
  scp'd; photo-steward cloned at `f1ee6d8` (carries this session's
  `IMMICH_URL` parameterization, pushed to photo-steward main); dotfiles +
  secrets checkouts current; `./deploy.zsh --only 65_secrets` rendered
  `.restic-password` + `.b2-env` (21 rendered, 0 failed); `.env` + `.api-key`
  scp'd (mode 600); `setup-immich.sh` installed compose + units + rendered
  backup service (API key substituted), timers **enabled** (not started);
  `IMMICH_URL=http://100.87.185.24:2283` drop-in installed on the backup
  service; **both restic tiers probed read-only from makemake — saturn
  `1fd6ad33`, B2 `14d4aa73`, same heads the drill verified**.
- Wired-LAN facts checked before binding `10.77.0.97`: the `office-lan` NM
  profile is persistent (`/etc/netplan/90-NM-1a3b9dc7….yaml`), and the
  docker boot-race drop-in's tailscale wait dominates NM's earlier wired
  activation, so a dual bind (tailnet + wired) is boot-safe.

Cutover (downtime bounded by a pre-seed):

1. Live pre-seed pass (immich still serving on ceres): model-cache volume
   (4.5 GiB) tar'd host-to-host; library (49 GiB, 150,123 files) rsynced
   `-a` over the wired LAN at 41.8 MB/s (~20 min); pgdata (793 MiB)
   tar-piped with sudo both ends (root-owned uid 999/700). First attempt
   taught a lesson recorded under deviations: `sudo rsync` fails host-key
   verification because root's ssh has neither the user's known_hosts nor
   config — the fix was running rsync as the user (library is fully
   user-readable) with `--rsync-path="sudo rsync"` for the remote writes.
2. Ceres `docker compose down` (volumes + bind mounts INTACT) at 20:16:53.
3. Delta pass (quiesced): library delta rsync transferred **nothing new**
   (no uploads during the pre-seed); pgdata re-tar'd whole into a fresh
   dest dir (a tar overlay never deletes stale files, so the dest was
   cleared first — quiesced source, so full consistency by construction).
   Sizes match both ends (49 G + 793 M); sample sha256s MATCH.
   **Copy portion of the downtime window: 22 seconds** (20:16:53 → 20:17:15).
4. Makemake `docker compose up -d` → **all four containers healthy**
   (postgres healthy on first try — pin held); `pong` on both binds
   (100.87.185.24 + 10.77.0.97) and from ceres over the wire; compose
   gateway detected 172.19.0.1 → `IMMICH_TRUSTED_PROXIES` updated from
   ceres's 172.22.0.1, server container recreated; **x-api-key auth 200**
   (the machine-local key matches the DB-carried one, as predicted).
5. Caddy repoint (`configs/caddy/Caddyfile` immich block):
   `reverse_proxy 10.77.0.97:2283 100.87.185.24:2283 { lb_policy first;
   fail_duration 30s }` — wired preferred, tailnet fallback; validated,
   installed with timestamped backup (`Caddyfile.bak-2026-09-08`),
   **reloaded** (never restart); `immich.wedrifid.dev` → `pong` + UI `200`
   from the tailnet. URL contract preserved.
6. One manual `hart-immich-backup` run on makemake: fresh API-triggered
   dump `immich-db-backup-20260908T202034` (227 MB — the IMMICH_URL
   drop-in worked, no WARN), **saturn snapshot `bc7ae59a`** (52232 files,
   42.7 GiB processed, 39.6 MiB added — "no parent snapshot" because
   parents match on hostname; content dedup held), **B2 snapshot
   `ec10bea3`**; service Finished clean. Timers then STARTED (not just
   enabled): backup next 03:20 AEST, prune 2026-10-01.
7. Ceres: `hart-immich-{backup,prune}` timers `disable --now` (unit files
   left in place; ceres copy is the rollback path).

**Rollback state for immich: retained, not exercised.** The rss rehearsal
proved the "and back" mechanics; the drill proved data integrity end-to-end;
exercising immich's rollback would mean a second caddy flip plus a
controlled split-brain window with the family photo library — cost without
new information. The ceres stack is one `docker compose up -d` away (state
intact) and `/etc/caddy/Caddyfile.bak-2026-09-08` restores the old upstream.

## Phase 4 — records

- `docs/caddy-ingress.md` routes table: immich row backend updated to
  makemake. (Only the immich row touched.)
- `configs/caddy/Caddyfile`: immich block repointed (same commit set).
- This report on dotfiles main. Infra branch `m5-services-toml` pushed with
  `services.toml` as-built + manifest drafts (both services).

## Post-cutover incident: concurrent session re-upped ceres RSS (resolved)

At **19:59:02** — mid-immich-move, ~3.5 h after the Phase-1 cutover — a
concurrent agent session on ceres (4 claude + 2 codex processes were live on
the box; no interactive shell history in the window) ran `docker compose up`
on the ceres rss tree and re-enabled `rss-digest.timer`. That re-lit the
rollback copy against its own retained database: a split-brain (two live
stacks, two DBs, the old ceres URL answering, state forking). Detected during
the final verification sweep at ~20:32; ceres re-downed and the timer
re-disabled within minutes of detection; makemake's stack never wavered
(200 throughout). **Countermeasure:** `~/repos/deploy/rss/MOVED.md` now sits
on the ceres copy telling any local actor the stack lives on makemake and
that a running ceres copy is a split-brain to re-down. Root cause worth
noting for M6: nothing in the ceres-local state said "this moved" — the
manifests live on an unreviewed branch, so a session without fleet context
had no way to know. The marker file is the interim guard; merging the
dispositions is the real fix.

## Owner follow-ups (deliberately not done by the agent)

1. **Re-point RSS clients**: Capy Reader (GReader URL) and any phone
   shortcuts → `http://100.87.185.24:8090` (Basic creds unchanged — the DB
   moved with them). ceres `:8090` is down by design.
2. **Ceres data cleanup after a settle period** (all rollback copies; delete
   only when makemake has served well): docker volume `rss_miniflux-db`,
   `~/repos/deploy/rss` tree, `rss-digest.*` unit files,
   `~/immich/{library,postgres}` (49 G + 793 M), `~/repos/deploy/immich`
   tree + rendered units, immich docker volume `immich_model-cache`, stale
   images.
3. **Stray `immich_ml` container on makemake** — pre-existing (Up 2 days,
   healthy, no compose labels), now duplicating the stack's own
   `immich_machine_learning`. Left running (not mine to stop); it holds
   ~1.5–2 GB RAM on a 16 GB N97.
4. **Portkey 500s** (pre-existing): digest scoring has been failing since
   ≥ Sep 6; the makemake timer will keep hitting it until fixed.
5. RSS image pin discipline (`:latest` × 3) — pre-existing; tighten if desired.

## Deviations from the brief

- **No valkey in the RSS stack** (brief said there was one); corrected after
  inspection.
- **rss-bridge tag archaeology**: the brief's compose showed a dead tag; live
  image uses the hyphenated name. The dirty tree that showed otherwise was a
  concurrent agent's transient edit (phantom), not repo state.
- **postgres 18 volume path**: `pgvector/pgvector:pg18` mounts at
  `/var/lib/postgresql`, not `.../data` — the pg18 image init fails with the
  old path. Recorded in `services.toml` constraints.
- **probe correction**: Miniflux's API wants HTTP Basic auth, not
  `/v1/auth/login` — the brief's probe 401s.
- **photo-steward edit**: `ops/immich-backup.sh` gained `IMMICH_URL` env
  parameterization (default = ceres, so ceres behavior is unchanged);
  pushed to photo-steward main as `f1ee6d8`. Makemake supplies its address
  via a systemd drop-in rather than a script fork.
- **caddy dual upstream** rather than a single wired target: honors "prefer
  wired, tailscale fallback" without a second edit when the cable is out.
- **`sudo rsync` + ssh foot-gun**: root's ssh lacks the user's
  `known_hosts`/config, so the first library/pgdata rsync passes failed
  "Host key verification failed" **while the wrapper script still echoed its
  success line** (exit-status discipline in that one-off script was wrong;
  caught by verifying bytes on the far end, not trusting the echo). The
  working shape: rsync as the user + `--rsync-path="sudo rsync"` remote.
- **enable ≠ start, again**: `setup-immich.sh` only ENABLES the backup/prune
  timers; an enabled-but-never-started timer does not fire until the next
  login session reloads timers.target. Both timers were started explicitly
  on makemake (same lesson as the rss timer, now recorded in the runbook).
- **caddy-ingress.md row pointers**: besides the immich row (mine), the
  other rows' `Caddyfile:NN-MM` ranges had drifted stale (some before this
  edit); all were re-measured and corrected in the same commit — pointer
  accuracy, no content changes to rows I don't own.
