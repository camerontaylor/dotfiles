# Phase 1 cutover — execution report

Date: 2026-09-08. Executor: Claude (GLM via ccl). Brief:
`/tmp/phase1-cutover-brief.md` (owner-authorized 2026-09-08). Everything below
was executed live against the fleet in brief order.

## Outcome at a glance

| step | result |
|---|---|
| A1 merge `agents-carveout` → main | ✅ `95dd4fd3`, pushed — **after a stop-and-report** (see §1) |
| A2 ceres backup + deploy + restarts | ✅ exit 0, units active, links flipped |
| A3 makemake / saturn / neptune | ✅ all deployed, links flipped, Mac watchdogs repointed |
| A3 pluto | ⚠️ **dirty tree — not pulled, not forced** (§4) |
| A3 quaoar / eris | ⏭️ skipped (away) / excluded (brief) |
| A4 `filter.codex-clean.clean` unset on ceres | ✅ |
| B5 retire `bin/webfront-root` + `bin/p` | ✅ `25c06098`, pushed; live links swept |
| B6 retire ccr-router (agents repo) | ✅ `41e9488`, pushed; tests 75/75; live links swept |
| B7 ceres webfront stack archived + retired | ✅ two backups taken first (§7) |
| B8 litellm strip fleet-wide | ✅ ceres/saturn/neptune already clean; makemake + pluto cleaned |

## 1. Merge — conflict stop, owner ruling, resolution

The merge produced **three** conflicts, so per the brief's hard rule the merge
was aborted (`git merge --abort`, main restored to `97c723f6`, tree clean) and
reported before any resolution was attempted.

- `configs/ai/codexbar/codexbar-serve.service` — modify/delete, the §9-predicted
  one (main `97c723f6` modified / branch deleted; delta already ported into
  agents `0bc95f1`).
- `docs/llm-quota.md` — same shape, same pre-resolution.
- `docs/caddy-ingress.md` — **content conflict §9 did not predict**: main's
  `97c723f6` updated the usage/ntfy table rows (Caddyfile `95-128`/`130-142`
  ranges, bearer-injection note, new `appreciation` row) while the branch
  (`09ac6f51`) repointed those rows' `docs/llm-quota.md` references at the
  agents repo. §9 only audited branch-*deletes* vs main-modifies, so this
  shared-doc edit was out of its scope.

Owner ruling (2026-09-08, via UI + dispatcher relay): resolve all three —
`git rm` the two modify/delete files; union `docs/caddy-ingress.md` (main's
rows + branch's repoint); `97c723f6`'s caddy artifacts must survive intact.
Resolution recorded in the merge commit message. Verified after merge:
`configs/caddy/Caddyfile`, `configs/caddy/env.example`,
`configs/appreciation/appreciation.conf` byte-identical to `97c723f6`;
`scripts/setup-caddy-usage-site.sh` differs by exactly one error-message line
(its "run scripts/setup-llm-quota.sh" hint repointed at
`~/.local/agents/scripts/setup-llm-quota.sh` — same repoint class as branch
commit `09ac6f51`, rode along deliberately). No conflict markers anywhere.

## 2. Phase A2 — ceres

- **Straggler backup (before deploy):** the four §10.4 write-through paths were
  real files/dirs, moved (not deleted) to
  `~/.local/state/carveout-backup-20260908/` preserving structure:
  `.claude/settings.json`, `.codex/agents/` (24 agent TOMLs), `.codex/prompts/`
  (bp-*/ck-* sets), `.codex/rules/default.rules`. Nested `agents`/`prompts`/
  `rules` marker files inside two of them are write-through artifacts, kept
  as-is.
- **Deploy** (`/tmp/ceres-deploy-phase1.log`): exit 0. Fragment 67 pulled the
  sibling and ran its deploy: skills pins installed, links.conf rows planted —
  including the four ex-straggler paths, now symlinks into `~/.local/agents`.
- **systemd:** `daemon-reload`; `codexbar-quota-cues.timer` and
  `portkey-gateway.service` restarted — both `active`; portkey
  `SubState=running`, `NRestarts=0`, responds (308 redirect on the probe,
  i.e. listening + serving).
- **Spot links:** `~/.claude/settings.json`, `~/.codex/{config.toml,agents}`,
  `~/.claude/skills`, `~/.config/systemd/user/portkey-gateway.service`,
  `codexbar-serve.service`, `~/.local/bin/{cc,codexbar-quota-cues}` all →
  `~/.local/agents/...`.
- A second full deploy run (after B5) exercised the retired-link removal live:
  both links removed, `...done`.
- Secrets render note (pre-existing, not a regression):
  `UNMAPPED services/gjc/config.enc`, `failed 0`.

## 3. Phase A3 — hosts

**makemake** ✅ — clean tree @ `82b3acae` → pulled to `95dd4fd3`, deploy exit 0
(`/tmp/makemake-deploy-phase1.log` on host). Fragment 67 chained; spot links
flipped. Host-specific, pre-existing gaps isolated (not carve-out
regressions; both files untouched by the merge):

- `codewhale-cli`/`codewhale-tui` cargo install failed (stderr swallowed by
  `70_runtime_installs.zsh:242`; crates.io reachable; binary was never
  present). Needs a manual `cargo install codewhale-cli --locked` to diagnose.
- `git-restore-mtime`, `psql` failed smoke test — host packages on ceres
  (`/usr/bin`), never installed on makemake.

**saturn** ✅ — clean @ `4f9ed700` → `95dd4fd3`, deploy exit 0
(`/tmp/saturn-deploy-phase1.log`). `setup-paseo.sh` re-run in the same
session: daemon answering on 127.0.0.1:6767; watchdog plist now execs
`/Users/ctaylor/.local/agents/scripts/paseo-watchdog`; `local.paseo-watchdog`
last exit 0. Extra finding: **saturn had its own straggler** —
`~/.codewhale/skills` was a real vendor-write-through dir (48K,
`.system-installed-version` marker), the same §10.4 class the owner approved
moving aside at cutover. Applied the same pattern: backed up to
`saturn:~/.local/state/carveout-backup-20260908/codewhale-skills`, re-ran
`~/.local/agents/deploy`, link planted. Pre-existing host nit: `moor`
installer failed (untouched by merge, not investigated).
`local.paseo-daemon` launchd label shows last-exit 1 — Paseo.app owns the
daemon now (setup script verified it answering); cosmetic.

**neptune** ✅ — clean @ `4f9ed700` → `95dd4fd3`, deploy exit 0. Watchdog
plist repointed to the agents path, loaded, last exit 0. All spot links
flipped including `~/.codewhale/skills` (no straggler here). Only warning:
the standard gjc unmapped note.

**pluto** ⚠️ — **dirty tree, not pulled, not forced** (brief rule). Real local
edits (post `update-index --really-refresh`, so not phantom):
`configs/ai/claude-code/hooks/langfuse_hook.py` + `settings.json`
(LANGFUSE_HOST localhost:3050 → `https://telemetry.webfront.app`) and
`configs/ai/codex/config.toml` (model/effort write-through). All three files
**move to the agents repo** in the merge, so reconciliation is an owner call:
`git stash` then pull, then port any wanted edits into
`~/.local/agents/configs/ai/...`. Until then pluto's auto-pull timer will
keep failing silently. Not deployable today; its two retired-bin links were
absent anyway, and litellm cleanup was done over ssh (does not touch the git
tree).

**quaoar** ⏭️ skipped (away, per brief). Needs the same pull+deploy +
watchdog re-setup when back. **eris** ⛔ excluded per brief (also: the `eris`
git remote fetch failed during A1 — box offline).

## 4. Phase A4 — ceres checkout hygiene

`git config --unset filter.codex-clean.clean` — key was present
(`node scripts/codex-config-clean.mjs`), now gone (report §10.9).

## 5. Phase B5 — `bin/webfront-root` + `bin/p` retired

dotfiles `25c06098` (pushed):

- `git rm bin/webfront-root bin/p`; rows dropped from `docs/cli-tools.md`.
- `21_bash_symlinks.zsh`: link rows removed; new drift-correct block removes
  stale `~/.local/bin/{webfront-root,p}` links on future deploys (only if
  symlink; `deploy_rm`-based) so late-pulling hosts (pluto) self-heal.
- **Bug caught in verification:** the first version of that block used raw
  `rm`, which really deleted the links during `--dry-run` (the zsh/bash
  dry-run diff runs both drivers concurrently; the bash leg's raw `rm` won the
  race). Rewrote with `deploy_rm` (prints `[dry-run] would rm`, no side
  effect), recreated the links, re-verified: dry-run announces and preserves;
  real deploy removes. Sequential driver dry-runs now diff empty.
- Live sweep: `~/.local/bin/{webfront-root,p}` removed on ceres (via deploy),
  makemake, saturn, neptune; pluto never had them.

## 6. Phase B6 — ccr-router retired (agents repo `41e9488`, pushed)

- Deleted `configs/ai/ccr-router/` (service, config.json, custom-router.js —
  all preserved in git history).
- `manifests/links.conf`: `~/.config/ccr-router` row removed; comment records
  the retirement.
- `AGENTS.md` retirement-candidate flag replaced by a retired note.
- Deliberately kept: `zsh/env.d/11_ccr_default.zsh` (`USE_CCR=0`) — it gates
  rollback routing in `bin/cc*`, it is not the service tree.
- Tests: `deploy.test.zsh` 75/75 after the change.
- Live sweep: `~/.config/ccr-router` symlink removed on ceres, makemake,
  saturn, neptune (pluto never had one). No ccr units were ever linked into
  systemd.

## 7. Phase B7 — ceres webfront stack archived + retired

Scope discipline: **only** the `cereswebfrontapp-*` project, via
`~/repos/deploy/ceres.webfront.app/`. `rss-*`, `immich_*`, `telemetry-*`
containers and `~/deploy/telemetry-*` bind dirs untouched — verified by
container census before and after.

Topology found (differs from the brief's assumption in two harmless ways):

- Live containers were just two: `cereswebfrontapp-postgres-1` (up) and
  `cereswebfrontapp-webfront-app-1` (**exited 137, dead for 2 months**). The
  nginx-proxy/cloudflared/ddns compose files exist but no such containers run.
- The postgres "volume" is a **bind mount at `~/deploy/postgres-data/16/data`**
  (env override `WF_DB_DATA`), root-owned — not the compose dir's
  `./postgres-data` (0 bytes, unused). Archived and cleaned via
  root-equivalent `docker run --rm` one-liners.
- The cluster held 8 DBs (~2.1 GB): four `neutron_*` snapshots (Feb–Mar 2026),
  `webfront_system_logs`, `beedee_2026_04_13`, `litellm_proxy` (10 MB — the
  old litellm DB), `postgres`.
- No external clients: `pg_stat_activity` showed only postgres background
  workers; the app container had been dead for months.

**Backups taken first** (both verified: `gzip -t`, dump ends with
"PostgreSQL database cluster dump complete", 7 `CREATE DATABASE`; tar lists
8,935 entries with the correct `16/data/base/...` layout):

| archive | size |
|---|---|
| `~/.local/state/webfront-final-backup-20260908/webfront-pg-dumpall-20260908.sql.gz` | 369 MB |
| `~/.local/state/webfront-final-backup-20260908/webfront-postgres-datadir-20260908.tar.gz` | 576 MB |

Then: `webfront-compose.sh down -v --remove-orphans` (2 containers, network,
`wf-app-cache` volume); two leftover bundle-cache volumes
(`cereswebfrontapp_wf-app-bundle`, `..._wf-app-dotbundle`, declared by
inactive compose variants) removed explicitly; `~/deploy/postgres-data`
removed after the tar. `~/deploy/` now contains only the telemetry dirs.
Nothing in the Caddyfile routed to these containers (`*.ceres.webfront.app`
→ portless stays), so no caddy changes were needed.

## 8. Phase B8 — litellm stripped fleet-wide

Swept every reachable host for units (incl. `default.target.wants/`),
`~/.config/litellm`, `~/.local/state/litellm`, processes:

| host | found | action |
|---|---|---|
| ceres | nothing | — (already clean) |
| saturn | nothing | — |
| neptune | nothing | — |
| makemake | dangling unit symlink + `~/.config/litellm/` (2 dangling config symlinks) + `~/.local/state/litellm/` (old rendered `env` credential, mode 600 — deleted unprinted) | removed; `daemon-reload` + `reset-failed`; verified clean |
| pluto | dangling unit symlink + `~/.config/litellm/` (**sweep finding beyond the brief, which only named makemake**) | same treatment; verified clean |

All remnants pointed into the now-deleted `~/.local/dotfiles/configs/litellm/`.

## 9. Follow-ups for the owner (out of brief scope)

1. **pluto reconciliation** (§3) — stash/ports the three local edits, pull,
   deploy, then it self-heals (retired-link drift block included).
2. **quaoar** — pull + deploy + `setup-paseo.sh` re-run when back on network.
3. **agents repo follow-up:** `bin/cc*` wrappers' fallback
   `${DOTFILES:-...}/bin/webfront-root` is dead now (B5); the repo also still
   carries `zsh/fpath/_webfront_root` + `zsh/rc.d/23_webfront_wrappers.zsh`
   from the carve-out move — a webfront-cleanup pass there would drop both.
4. Census docs refresh (carve-out report §13.5): `docs/fleet-census-*.md` and
   the `docs/fleet-consolidation.md` move-table still describe the carve-out
   as pending.
5. Pre-existing nits observed, not fixed here: the ghx retirement block in
   `70_runtime_installs.zsh` uses raw `rm` (same dry-run side-effect class as
   §5's caught bug; never fires in CI because ghx never existed there);
   makemake codewhale cargo failures + missing host packages; saturn `moor`
   install failure; `services/gjc/config.enc` unmapped in secrets render.
6. `~/repos/deploy/ceres.webfront.app/` itself (compose files, `app-data`,
   `webfront/`, `dropbox`, `cronus.env`) left untouched — brief authorized
   containers + volume only. `app-data` is 4 KB of deploy scripts; decide its
   disposition later.

## 10. Commit trail

| repo | commit | content |
|---|---|---|
| dotfiles | `95dd4fd3` | merge `agents-carveout` → main (conflict resolution in message) |
| dotfiles | `25c06098` | retire `bin/webfront-root` + `bin/p` |
| agents | `41e9488` | retire ccr-router |
| dotfiles | (this report) | `plans/phase1-cutover-report.md` |
