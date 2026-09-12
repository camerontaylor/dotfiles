# Handover — fleet consolidation, post-M5 (2026-09-09)

**For:** the next session (agent or human) picking up the fleet plan.
**State:** M1–M5 complete, merged, deployed, and independently verified.
M6 (pluto NixOS) is the remaining board item — owner-gated. Everything
below is current as of 2026-09-09 ~05:00 +10:00.

## Where main stands

| Repo | main | Carries |
|---|---|---|
| dotfiles | `62497fc2` | fleet-m234 merge `95444d6a` → paperwork `bdcfa764` (board flip, tied-`path` foot-gun row) → mise `"0"`-prefix fix `d1f56ad1` → codewhale drop `62497fc2` |
| infra | `b9912ca` | `m2-manifest-census` + `m5-services-toml` (m5 as-built won the manifest conflicts); `services.toml` = the service placement map |
| agents | `8c4d2ef` | carve-out + `b3ae795` cc delink + drift-corrector, `7f0f8cf`/`58759c8` webfront/ccr dead-code sweep + exec-bit fixup, `8c4d2ef` AGENTS.md note |
| hart | `ded6fea4` | `ORIGIN_MF` miniflux origin fix (re-provision can't regress ingress) |

**Hosts:** ceres is the live dotfiles checkout (commits happen there; it is
always current). makemake pull-deployed through `62497fc2`. saturn /
neptune / pluto converge via auto-pull timers. quaoar picks everything up
on return via the updated reader bootstrap (owner uses it again — just
check its tree then). eris is excluded from the cutover by design.

**Live services (makemake):** rss/Miniflux at `:8090` (pgvector/pg18),
immich stack (`immich.wedrifid.dev` 200 via caddy dual-upstream,
`10.77.0.97:2283` wired-first + tailnet fallback), restic timer 03:20
(first backups verified: `bc7ae59a` saturn + `ec10bea3` B2).
`miniflux.wedrifid.dev` rides hart's Cloudflare Tunnel (remotely-managed
ingress → `http://100.87.185.24:8090`), NOT caddy.

## What just finished (context, so state doesn't surprise you)

1. **Codewhale dropped from mise** (`62497fc2`, owner decision). The cargo
   backends compile from source; a single `codewhale-tui` rustc peaked
   **11.9 GB RSS** and the kernel OOM-killed it twice on makemake (16 GB,
   no swap — see below). Hosts that deployed since M4 (ceres, makemake)
   have no codewhale binary; others keep legacy `~/.cargo/bin` copies.
   Nothing installs or removes it now. Do not re-add without a prebuilt
   backend (tombstone note in `configs/mise.toml`).
2. **makemake swap question answered:** nothing tuned it off — it was
   never created. The 2026-04-18 Ubuntu Desktop install used a hand-built
   GPT layout (EFI + single btrfs root; no swap partition/file anywhere in
   the autoinstall storage config). No cmdline token / sysctl.d / masked
   unit / zram. A swapfile attempt was made and **fully reverted** at
   owner direction (fstab line, `/swapfile`, swappiness all restored). If
   ever wanted: btrfs needs `chattr +C` + `dd` — `fallocate` files fail
   `swapon` with EINVAL.
3. Earlier same evening: `cc` compiler-shadow delink, mise `"0"`-prefix
   majors pinned, webfront/ccr dead code swept, `wtp 0.4.0` orphans pruned
   on ceres + makemake. All committed/pushed per the table above.

## Next steps

### 1. M6 — pluto NixOS reinstall (owner-gated; the main remaining item)

Do not start without explicit owner authorization — it is a reinstall.

- Venue decided: pluto (GS60 2QE laptop). See `docs/fleet-consolidation.md`
  M6 row + the hardware notes (session memory: EC-owned fans untunable —
  msi-ec rejects E16H5; root fs currently on a 7200 rpm HDD that can never
  spin down; dead GitHub runner stopped 2026-09-08 — decide revive-vs-
  remove during the reinstall).
- **Must carry across the reinstall:** SeaweedFS + t3-serve (owner
  requirement recorded when M6 was nominated).
  **Superseded 2026-09-09** — owner retired seaweedfs, t3-serve, the GH
  runner, and zerotier; only caddy + portless carry. See
  [addendum-2 §8](handover-addendum-2.md).
- pluto carries `stash@{0}` from the Phase-1 cutover (3 edits: a
  locally-duplicated langfuse-host fix already canonical in the agents
  repo, stale codex prefs, hooks.state write-through). Almost certainly
  discardable — verify against current agents main before dropping.
- NixOS config venue: infra repo. Manifests validate via
  `uv run converge validate ../manifests/<host>.toml` (explicit MANIFEST
  args required) from the converge CLI dir.

### 2. Post-settle cleanup on ceres (owner-gated by "after it settles")

- The rollback copies ARE the rollback path until the owner clears them:
  49 G immich data copy + volumes, quiesced rss containers, disabled
  timers. No deletion before that gate — hard rule.
- `~/repos/deploy/rss/MOVED.md` split-brain guard stays until the copies
  are gone.
- Confidence signals to check first: restic timer still succeeding
  (`journalctl -u restic-*` on makemake), immich ML jobs stable, no
  rollback events since 2026-09-08.

### 3. Small open items (owner-side, any cadence)

- **Stray `immich_ml` container on makemake** — predates the move, ~2 GB
  RAM duplicate of the compose-managed ML worker. Stop/remove when owner
  confirms nothing references it.
- **portkey 500s breaking digest scoring** — pre-existing (≥ Sep 6),
  agents-repo domain. Uninvestigated.
- **makemake transcode enablement** — best AV1-decode transcode target in
  the fleet, but blocked: `render` group is empty (`usermod -aG render
  ctaylor`) and ffmpeg/vainfo aren't installed.
- **Secrets key rotation** (standing security item from the secrets-repo
  migration): tailscale key leaked — rotate that first; quarantine purge
  pending after.

### 4. Fleet hygiene (any session, opportunistic)

- quaoar on return: check tree, pull, deploy, confirm `cc` resolves to the
  compiler and aliases still work interactively.
- codewhale is unmanaged by decision — if a prebuilt/aqua backend appears
  upstream, that reopens the question (mise.toml tombstone note has the
  criteria).
- Keep saving decisions/gotchas to engram + session memory per protocol.

## Hard rules (carry forward verbatim)

- **Deploy ceres-first** on merges; the post-merge hook only deploys for
  pull-initiated merges (`GIT_REFLOG_ACTION` check, `timeout 300`).
- **No data deletion anywhere.** Stop/disable only, unless the owner has
  explicitly cleared it.
- **Never commit plaintext secrets** — sops/age flow, rendered at deploy.
- **hart is concurrent-agent-heavy** — stage single files only.
- **Verify dispatched-agent claims independently** before relaying them
  as fact; paseo/system notifications are not owner input.
- **mise majors are pinned**; `"0"` only means track-latest for major-0
  tools; `mise ls` needs the config-source column checked (orphans sit
  beside `(missing)` rows and look resolved at a glance).
- **Never link toolchain names** (`cc`, `ar`, `ld`, …) into
  `~/.local/bin` — the carve-out's `cc` shadow broke every cargo build
  fleet-wide for an afternoon.
- makemake specifics: 16 GB soldered, no swap, passwordless sudo over ssh;
  USB bus power can't sustain bus-powered SSD writes (use a powered hub).

## Docs map

- Board + placement tree: `docs/fleet-consolidation.md`
- Censuses: `docs/fleet-census-installers.md`, `docs/fleet-census-units.md`
- Execution reports: `plans/phase1-cutover-report.md`,
  `plans/m234-consolidation-report.md`, `plans/m5-service-moves-report.md`
- Prior handovers: `plans/handover-agents-carveout.md` (+ addendum-1)
- Service placement: `services.toml` in the infra repo

## Quick state checks for a fresh session

```
git -C ~/.local/dotfiles log --oneline -3          # ≥ 62497fc2
ssh makemake 'git -C ~/.local/dotfiles log --oneline -1 && docker ps --format "{{.Names}}"'  # rss + immich stack
curl -sI https://miniflux.wedrifid.dev | head -1   # 200
mise ls | grep -ci codewhale                       # 0
command -v cc                                      # /usr/bin/cc, not ~/.local/bin
```
