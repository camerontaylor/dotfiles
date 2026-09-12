# Handover addendum 2 — M5 verification, M6 prep, open gates

2026-09-09. Covers the implementation pass over
[`handover-fleet-m6-and-followups.md`](handover-fleet-m6-and-followups.md):
every quick-check re-verified, the M5 settle gate assessed, M6 prep built and
validated on a branch, and the open items sharpened into owner decisions.
Corrections to the handover's own facts are listed — several were stale the
day it was written.

## 1. Handover quick-checks — all PASS (re-verified first-hand)

| Check | Result |
|---|---|
| ceres dotfiles ≥ fb6ee1cd | now `a62caa1a` (pushed; see §3 swap correction) |
| codewhale containers | 0 |
| `cc` | `/usr/bin/cc` (no toolchain links in `~/.local/bin`) |
| makemake at floor `62497fc2` | yes; ~5 behind after the Sep 9 pushes — nightly pull self-heals |
| miniflux / immich on makemake | both HTTP 200 |
| caddy (makemake) | active since Sep 8 15:23:15, no restarts |
| M5 settle gate | **GREEN** — see §2 |
| single-brain | ceres runs zero rss/miniflux/immich containers (re-verified via docker); rollback copies + `MOVED.md` intact |

## 2. M5 settle gate: GREEN

- Sep 9 03:20 restic run succeeded **both tiers**: saturn `aff676c3`
  (parent `bc7ae59a`), B2 `621ec0e4` (parent `ec10bea3`) — clean
  incrementals, `hart-immich-backup.service` Finished (journalctl-verified).
- immich ML: 0 restarts since cutover.
- Consequence: the "after it settles" cleanup gate on ceres's rollback
  copies is now **unblocked but still owner-gated** — no deletion has
  happened; the hard rule stands until the owner clears it.

## 3. Corrections to the handover

- **makemake swap was NOT "fully reverted".** A concurrent session applied
  the full two-tier setup on 2026-09-09 morning: 8G zram (pri 100) + 8G
  swapfile (pri 10, NOCOW via `btrfs filesystem mkswapfile`), root
  `compress=zstd:1` + a one-off `scripts/btrfs-compress-backfill.sh` run.
  The docs/scripts were left **uncommitted**, which had been blocking
  ceres's midnight pulls Sep 6–8 ("cannot pull with rebase: unstaged
  changes"). Now committed and pushed: `734a0b0a` (zram reload fix),
  `a62caa1a` (swap+zstd docs + backfill script).
- **The portkey 500s were already fixed Sep 8** (inline `x-portkey-config`;
  the local-mode fork ignores the old header passthrough). The handover
  item was closed before it was written. The LIVE defect is different and
  still open — §5.
- **pluto `stash@{0}` verified discardable** (the handover's verify-then-drop
  precondition): all three edits are canonical-in-agents-main or stale
  machine-local state. Nothing to port.
- **makemake transcode blockers run deeper than "render group + ffmpeg":**
  ffmpeg IS inside immich_server; the real gap is the CONTAINER — no
  `/dev/dri` passthrough, no `group_add`. Enabling = compose edit
  (`devices: [/dev/dri/renderD128]`, `group_add: [render]`) + recreate, then
  `vainfo` to verify AV1 decode.
- **immich health checks must not use 127.0.0.1** — immich_server binds
  2283 only on 10.77.0.97 + the tailscale IP (loopback refuses). The
  services.toml health line targets loopback and needs a bound address.

## 4. M6 prep — built, validated, on a branch

`infra` branch **`m6-pluto-nixos` @ `dcbd34e`** (pushed; ceres's infra
checkout is back on main). 14 files:

- `nixos/flake.nix` + `flake.lock` — one `nixosConfigurations.pluto`,
  nixpkgs `nixos-25.05` pinned to `ac62194c`. The caddy plugin hash is
  computed against exactly this revision (lock-sensitive).
- `nixos/modules/base.nix` — cattle baseline (ssh keys-only, tailscale
  trusted, docker, zramSwap zstd pri-100, journald caps, gc). Two 25.05
  fixes were forced: `zramGenerator`→`zramSwap`, `environment.noXlibs`
  removed upstream.
- `nixos/modules/seaweedfs.nix` — compose file rendered into the store +
  oneshot `docker compose up -d` unit (25.05 has no compose module;
  oci-containers would drop the labels the manifest ids derive from).
  Real bind dirs on @srv replace the 120G ext4 loop image. Image pinned
  `4.21`. **s3 gateway dropped** (crashed Jun 10; was the stack's only
  credential surface). No secrets anywhere in the module.
- `nixos/modules/t3-serve.nix` — live unit verbatim; t3 binary stays
  mise's. `ConditionPathExists` on the mise binary so first boot skips
  rather than crashloops.
- `nixos/hosts/pluto.nix` — one btrfs label across both SSDs (G2 mirror
  alternative = identical config), systemd-boot + ESP on sda1 (spinner
  stays the bootable rollback), iwd+networkd (`anyInterface`; PSK stays in
  `/var/lib/iwd`, never in-repo), caddy wildcard via `withPlugins`
  cloudflare (`/etc/caddy/env` path only — no token value), portless-proxy,
  flake-rendered pull-dotfiles user timer (linger), commented GH-runner
  revive block.
- `manifests/pluto.toml` — DRAFT ledger, 20 artifacts, every disposition
  agent-proposed pending owner review (H1). `pluto` added to converge's
  HOSTS (additive; test fixture moved to `vesta`).
- `docs/m6-pluto-reinstall.md` — the runbook: backup (docker-export tar
  pipes + sha256 manifest → makemake, no sudo anywhere), USB media,
  partitioning with both G2 variants, wifi PSK carry-over, bootstrap order
  (dotfiles → mise → secrets → seaweed restore → caddy env → services),
  unattended-reboot cattle test, spinner→bulk post-verification, not-carried
  list, verification checklist, plugin-hash re-pin procedure.
- `services.toml` — `[services.seaweedfs]` + `[services.t3-serve]` rows
  only.

Validations (re-run independently by the reviewing session, not just the
authoring agent): `converge validate` OK for all 6 manifests (pluto: 20
artifacts); `pytest` 103 passed; docker-nix flake eval returns
`/nix/store/0cbm6fih…-nixos-system-pluto-25.05…ac62194.drv`; caddy
2.10.0 + cloudflare@v0.2.1 **built for real** with the plugin install-check
passing; rendered unit text inspected (store-pathed compose, RequiresMountsFor,
tolerated pull).

**Nothing has touched pluto.** The reinstall itself is G1.

### Owner gates (runbook index)

| Gate | Decision |
|---|---|
| G1 | the reinstall (physical; wipes both SSDs) |
| G2 | disk layout: default ~238G (data RAID0) vs mirror ~119G — same Nix config, only mkfs changes |
| G3 | GH runner revive vs remove (18G; both paths written) |
| G4 | pull-dotfiles ownership: flake-rendered on NixOS vs dotfiles-owned elsewhere |
| G5 | spinner wipe (destroys the rollback; post-soak only) |
| G6 | confirm nothing consumes the SeaweedFS S3 API before accepting s3's retirement |

Open questions the probe could not answer (runbook appendix): how
Cloudflare reaches `*.pluto.webfront.app` inbound (tunnel? port-forward?);
what (if anything) still writes the `langfuse-events` /
`agent-telemetry-blobs` collections; flake authorized_keys were mirrored
from ceres — diff against pluto's live file before install; pluto's agents
checkout was behind (verify no pluto-only commits pre-wipe); `~/repos/webfront`
is dirty (staged skills/.gitignore).

## 5. Open items for the owner (decision-ready)

1. **Stray `immich_ml` container (makemake)** — non-compose leftover from
   Aug 23; restart=unless-stopped; publishes **unauthenticated
   0.0.0.0:3003** (LAN + bridge peers); holds its own
   `immich-model-cache` volume (hyphen — distinct from the live
   `immich_model-cache` underscore), so `docker rm -f immich_ml` + volume
   cleanup cannot touch the live ML cache. unreferenced by immich_server
   (no override; uses compose-internal ML). Deletion needs owner clearance.
2. **makemake transcode enablement** — compose edit per §3, then vainfo;
   AV1 decode still unverified. Best transcode target in the fleet (only
   box with AV1 decode + HuC authenticated).
3. **portkey** — three separable calls: (a) gateway restart (running
   process holds pre-rewrite provider keys since Sep 8 21:43; restart =
   brief fleet-wide LLM interruption via the cc* aliases); (b) one paid
   debug call for the **0-picks-since-Aug-28** defect (raw reply dump;
   suspect glm-5.3-flash reasoning consuming the 1500 max_tokens; fix
   likely reasoning suppression and/or higher max_tokens); (c) removal of
   ceres's vestigial digest deployment (drift trap — stale digest.py
   pointing MINIFLUX_URL at ceres, unit not loaded).
4. **supervised immich-prune run** before the first unattended fire
   (2026-10-01 05:02 AEST) — hart-immich-prune has zero journal entries,
   never run.
5. **convergence fixes** (all mutating; left per the infra never-enables
   rule): `systemctl --user enable --now converge-check.timer` on makemake
   AND pluto (both linked+enabled but never STARTED — pluto has never
   reported); `launchctl bootstrap gui/$(id -u) …` for neptune's
   com.ctaylor.converge-check; saturn's unmanifested maxfiles LaunchDaemon
   needs a manifest row or waiver; ceres's checker flags docker.service
   MISSING against live state (false-positive or stale manifest row —
   unresolved).
6. **makemake `origin` remote is the upstream fork (z0rc/dotfiles)** —
   the fleet remote is named `ctaylor`. Rename to stop anything keying on
   `origin/main` from reading the wrong repo.
7. **ceres rollback-copy cleanup** — gate now unblocked (settle green,
   §2) but explicitly owner-cleared deletion only.
8. **quaoar** — offline 32 days; check tree + drift on return.
9. **secrets key rotation** — still pending from the older migration;
   tailscale first (leaked), then the rest.
10. **M6 gates** — §4 table.

## 6. Hygiene notes

- The engram CLI is not on PATH on ceres — session memory went to the
  file-based store under the project memory dir instead. Worth wiring
  (mise) if engram journaling from ceres sessions is wanted.
- neptune's Sep 9 00:00 deploy died mid-50_mise (missing exactly
  fb6ee1cd); the fix is pushed, tonight's (Sep 10) pull should self-heal —
  verify tomorrow.
- Wave-1 was a 5-agent read-only sweep (no mutations, secrets REDACTED,
  no paid LLM calls); dispatched-agent claims were independently
  re-verified over ssh/local before being recorded here.

## 7. Same-day resolution (2026-09-09, later)

The owner cleared items 1, 3, and 5 of §5 (plus the immich_ml removal and
the transcode enable) the same morning. Executed + verified:

| §5 item | Resolution | Verification |
|---|---|---|
| immich_ml (makemake) | container + orphan `immich-model-cache` (hyphen) volume removed | live stack intact — 4 containers, ML restarts=0, underscore `immich_model-cache` volume untouched, port 3003 exposure closed |
| makemake transcode | `hwaccel.transcoding.yml` (upstream vaapi leg) + `extends: service: vaapi` on immich-server; `.bak-20260909` kept | container recreated, renderD128 visible in-container, full-path `h264_vaapi` lavfi encode exit 0, `/api/server/ping` 200. Caveat: immich admin UI transcoding toggle still selects usage |
| portkey (a) | gateway restarted | old PID held keys from Sep 8 20:09 (pre-rewrite) → new PID Sep 9 10:29; 401-on-bare-curl = up |
| portkey (b) | paid debug call run (the one authorized) | **0-picks root-caused**: glm-5.3-flash via z.ai anthropic-compat ALWAYS emits reasoning; reasoning counts against `max_tokens` but its text is NOT returned (thinking block len=0). At `--limit 60` the invisible reasoning alone exceeds 1500 → stop_reason=max_tokens with no text block → `extract_json("")` → `{}` → 0 picks, HTTP-successful. Journal Sep 9 06:37 confirms all three streams "60 unread -> 0 picked", latencies 33/29/37 s (pre-Aug-26 runs were 5-6 s — z.ai flipped thinking on ~Aug 26, matching when digest broke). Fix DRAFTED, not applied (live file, awaiting owner word): in `call_glm`'s payload, `"max_tokens": 4096` + `"thinking": {"type": "disabled"}`; re-probe once when applying to confirm the param is honored |
| portkey (c) | ceres vestigial digest deployment removed (user units + `~/repos/deploy/rss/digest/`) | makemake's live copy verified separate first (its MINIFLUX_URL points at makemake). Found en route: ceres `~/repos/deploy/rss` IS a git repo now (.git since Sep 8), and `~/repos/deploy` also hosts hart-immich-backup/prune + appreciation-backup ExecStarts — their live/loaded state unchecked, flagged as follow-up |
| convergence | converge-check.timer `enable --now` on makemake AND pluto (both fired immediately — overdue OnBootSec; pluto's first-ever report); neptune plist bootstrapped; makemake remotes renamed (origin=camerontaylor/dotfiles, upstream=z0rc, main tracks origin/main) | timer status + immediate reports observed |

M6 itself untouched on pluto: branch `m6-pluto-nixos` @ `dcbd34e` pushed,
ceres infra checkout back on main, G1–G6 gates (§4) all still closed.

## 8. Correction — M6 scope settled: seaweedfs/t3 retired (2026-09-09/10, post-§7)

Owner settled M6's scope later on 2026-09-09 (infra `m6-pluto-nixos`
`fde68e5`, since extended to `c7477eb`): **pluto is a blank-slate dev box
that parallel web-dev workers get dispatched to — zero long-term state,
so obliterating it costs only inconvenience.** That premise supersedes
parts of §4 above and of the underlying handover:

- **Retired, not migrated.** This corrects the handover's "must carry:
  SeaweedFS + t3-serve" bullet and §4's module list: `fde68e5` deleted
  `nixos/modules/seaweedfs.nix` and `nixos/modules/t3-serve.nix` and cut
  their `services.toml` / `manifests/pluto.toml` rows. SeaweedFS was the
  telemetry blob store of a defunct project (~61G of leftovers, never backed
  up, and pluto was too slow for the role); t3-serve is replaced by paseo;
  the GH runner is retired (G3 decided: not backed up, not restored —
  provision fresh if CI capacity is ever wanted); zerotier retired on pluto
  only, scoped in `c7477eb` (it was live+enabled but ACCESS_DENIED on both
  networks, with no manifest row).
- **What carries: caddy + portless alone** — the pair that makes the box
  useful (any port a worker starts becomes
  `https://<name>.pluto.webfront.app`). No Cloudflare ingress exists or is
  wanted: the wildcard has always been a LAN/tailnet reference, and DNS-01
  validation is outbound, which is why a wildcard cert works on an otherwise
  unreachable box.
- **Gate table narrowed G1–G6 → G1 + G5.** Decided along the way: G2
  (layout, both variants still in the runbook), G3 (runner: retire), G4 —
  the reusable rule is *user units stay with the repo that generates them*
  (`~/.config/systemd/user` precedes `/etc/systemd/user` in systemd's user
  search path, so a flake-rendered `pull-dotfiles.*` would silently lose;
  the flake owns system units + `linger`), and G6 (s3 consumers — moot with
  the whole stack retired).
- **G1 authorized + pre-flight complete** (`182b0e8`, `fb8c9d0`):
  flake authorized_keys are now the fleet-union (9 keys — the
  ceres-mirrored set would have locked out four hosts); `~/repos/ollie_notes`
  reconciled — exactly one pluto-only file, rescued to
  `ceres:~/backup/pluto-m6/ollie_notes-pluto-only/` sha256-verified. Scan
  lesson folded into runbook §2.1: commit-less repos hide from any sweep
  that assumes a valid HEAD (`git log` fails rather than reporting 0).
  `~/repos/webfront`'s working copy was **discarded** by owner decision
  2026-09-10 (`fc0ef92`) — not rescued, goes with the wipe. No caddy render
  target exists in the secrets repo: the token is `CF_API_TOKEN` in
  `shell/91_cloudflare_secrets.yaml` (sops) and `/etc/caddy/env` is
  assembled by hand — the runbook carries the exact sops→install→shred
  sequence.
- **ISO staged on ceres and sha256-verified** (`c7477eb`):
  `~/backup/pluto-m6/iso/nixos-minimal-25.05.813814.ac62194c3917-x86_64-linux.iso`
  — built from exactly the flake-pinned nixpkgs `ac62194c`, so do NOT bump
  `flake.lock` before the install (the caddy plugin hash is lock-sensitive).
  Runbook §3 carries the dd command. Remaining work is physical: ~~USB media,~~
  F11 boot menu, wifi PSK, console password, `tailscale up`, firmware boot
  order. *(2026-09-10 later: media done — ISO dd'd + byte-verified, and the
  infra clone rides on a third ext4 partition labeled `M6-INFRA`, because a
  stock dd'd image cannot host files; runbook §3 updated as-built, branch tip
  `cf3a334`.)*
- Two live-fact corrections folded into the runbook after the probe: the
  SSDs are ONE whole-device btrfs (no partition table) mounted at
  `/home/ctaylor` with the 120G loop image inside it — so
  `/mnt/ssd-services` dies at **partitioning**, not at the G5 spinner wipe;
  and `enp4s0` has no carrier, so wifi is the only link (any bulk transfer
  plan must assume ~25-40 MB/s).
