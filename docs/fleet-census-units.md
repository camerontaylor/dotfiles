# Fleet census: service/daemon deployment artifacts

Date: 2026-09-08. Produced by a GLM-5.3 researcher (read-only survey of
dotfiles, infra, hart, deploy, paseo; secrets repo untouched), collected during
the fleet-consolidation direction work (`docs/fleet-consolidation.md`).
Point-in-time snapshot — re-verify line numbers before acting on them.

# Fleet service/daemon deployment census

Scope: `~/.local/dotfiles`, `~/.local/infra`, `~/repos/hart`, `~/repos/deploy`, `~/repos/paseo`. `/home/ctaylor/.local/secrets` was not read. Paths in tables are repo-relative; the repo root is in the heading. "Manual symlink" = documented `ln -s` command, no script.

## 1. dotfiles — `/home/ctaylor/.local/dotfiles`

The deploy pipeline is `scripts/deploy.d/*.zsh` (numbered fragments run by `deploy.zsh`), plus one-off `scripts/setup-*.sh` installers. Note: `deploy.d/66_infra.zsh:76-89` clones/pulls and runs infra's `./deploy` — dotfiles is the top of the chain.

### Tracked unit/config files

| Path | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `configs/ai/portkey/portkey-gateway.service` | Portkey LLM gateway (fork, :8787) | Symlink by `scripts/deploy.d/20_symlinks.zsh:133` → `~/.config/systemd/user/` | Unconditional — lands on Macs too, where it's inert (`specs/split-infrastructure-out-of-dotfiles-trace.md:46`). Runtime start/stop glue (not deployment) in `zsh/rc.d/11_portkey.zsh:301,761` |
| `configs/openclaw-mcp/openclaw-mcp.service` | OpenClaw MCP bridge, :3111 | Symlink, ceres-gated, `scripts/deploy.d/20_symlinks.zsh:142-144` | EnvFile is a rendered copy from secrets, never a symlink (`20_symlinks.zsh:138-141`) |
| `configs/ai/codexbar/codexbar-serve.service` | CodexBar quota collector :8791 | Symlink, ceres-gated, `scripts/deploy.d/20_symlinks.zsh:152-157`; **also** `scripts/setup-llm-quota.sh:100-103` | Two independent mechanisms for the same units. **[deleted 2026-09-10]** Collector moved to neptune as the dotfiles-owned LaunchAgent `com.github.ctaylor.codexbar-serve` (`78_codexbar_serve.zsh`, host-gated by `configs/codexbar/collectors.conf`) — macOS cookie-based sources; see `~/.local/agents/docs/llm-quota.md` |
| `configs/ai/codexbar/ntfy-server.service` | ntfy push server :2586 | Same two: `20_symlinks.zsh:152-157` + `setup-llm-quota.sh:100-103` | Binary installed by `setup-llm-quota.sh:79` |
| `configs/ai/codexbar/codexbar-quota-cues.service` | Quota cue engine | Same two: `20_symlinks.zsh:152-157` + `setup-llm-quota.sh:100-103` | Enabled at `setup-llm-quota.sh:105-106` |
| `configs/ai/codexbar/codexbar-quota-cues.timer` | Cadence for cues | Same two | Documented in `docs/llm-quota.md:38` |
| `configs/caddy/caddy.service` | Caddy TLS ingress (system unit, ceres) | **None in code.** `scripts/setup-caddy.sh:104` defines `TRACKED_CADDY_UNIT` and never uses it; `setup_caddy_systemd` (`setup-caddy.sh:500-515`) only writes a drop-in. Doc claims install: `docs/caddy-ingress.md:7` | Header says "Mirrored from pluto … official unit" (`caddy.service:1-4`); `/etc/systemd/system/caddy.service` is effectively hand-maintained |
| `configs/ai/litellm/litellm-proxy.service` | LiteLLM multi-provider proxy :4199 | **None.** README claims "Symlinked … by deploy.zsh" (`configs/ai/litellm/README.md:22-25`) but `20_symlinks.zsh` has no such line | Live on makemake as a **dangling** symlink to the pre-move path (`hart/wiki/fleet-converge-status.md:29`, `specs/split-infrastructure-out-of-dotfiles-trace.md:46`) |
| `configs/ai/ccr-router/ccr-router.service` | claude-code-router | **None** — "unreferenced" per `specs/split-infrastructure-out-of-dotfiles-trace.md:46` | Its `config.json:6` points at stale path `~/.local/dotfiles/configs/ccr-router/…` (now `configs/ai/ccr-router/`) |
| `configs/wake-peers/com.github.ctaylor.wake-peers.plist` | sleepwatcher screen-wake fanout (macOS peers) | **Rendered copy** (awk substitutes `@HOME@`/`@SLEEPWATCHER_PATH@`) to `~/Library/LaunchAgents/` by `scripts/deploy.d/76_wake_peers.zsh:77-103`, bootstrap at `:128-137` | Gated on hostname in `peers.conf` (`76_wake_peers.zsh:36-44`); data-file symlinks at `20_symlinks.zsh:167-170` |
| `configs/caddy/Caddyfile` | Caddy routes (7 sites) | Copy: `sudo install` in `scripts/setup-caddy.sh:435` (backup at `:433`) and `scripts/setup-caddy-usage-site.sh:85`; manual re-copy recipe `docs/caddy-ingress.md:131-132` | Per-host variant `Caddyfile.$HOSTNAME` supported at `setup-caddy.sh:99-100`, none tracked |
| `configs/immich/docker-compose.yaml` | Immich stack (see deploy repo) | Copy to `~/repos/deploy/immich/docker-compose.yaml` by `scripts/setup-immich.sh:180` via `install_tracked` (`install -m 644`, `setup-immich.sh:135`) | Dotfiles is the tracked source of truth (`setup-immich.sh:12-14`); containers are never touched (`:24-27`) |

Not a deployment: `nvim/plugins/solarized/docker-compose.yml` (2-line plugin build fixture).

### Units generated on-host by dotfiles scripts (no tracked unit file)

| Live unit | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `/etc/systemd/system/t3-serve.service` | T3 Code server :3773 | heredoc `sudo tee` — `scripts/setup-t3.sh:152-175`, enable `:178` | |
| `/Library/LaunchDaemons/local.t3-serve.plist` | same, macOS | `sudo tee` — `scripts/setup-t3.sh:189-233`, bootstrap `:236-238` | |
| `/etc/systemd/system/caddy.service.d/override.conf` | Caddy env drop-in | `sudo tee` — `scripts/setup-caddy.sh:505-509` | The only caddy unit piece the script actually writes |
| `/Library/LaunchDaemons/local.caddy.plist` | Caddy, macOS | `sudo tee` — `scripts/setup-caddy.sh:538-559`, bootstrap `:562-564` | |
| `/etc/systemd/system/portless-proxy.service` | Portless wildcard proxy :8080 | `sudo tee` — `scripts/setup-caddy.sh:577-598`, enable `:601` | Docs also describe a *user* `portless.service` (`docs/caddy-ingress.md:110-112`) — different unit, not generated by this script |
| `/Library/LaunchDaemons/local.portless-proxy.plist` | same, macOS | `sudo tee` — `scripts/setup-caddy.sh:629-671`, bootstrap `:672-674` | |
| `/etc/systemd/system/paseo-daemon.service` | Paseo agent-orchestrator daemon | staged heredoc + `sudo cp` — `scripts/setup-paseo.sh:388-433` (`cp` at `:430`), enable `:436` | Fork-pin guard `:364-380` |
| `~/Library/LaunchAgents/local.paseo-daemon.plist` | Paseo daemon at login | heredoc — `scripts/setup-paseo.sh:532-583`, bootstrap `:586-587` | Disables Paseo Desktop's own daemon management `:518-524` |
| `~/Library/LaunchAgents/local.paseo-watchdog.plist` | 5-min daemon watchdog | heredoc — `scripts/setup-paseo.sh:618-679`; runs `dotfiles/scripts/paseo-watchdog` directly (`:608,627`) | |
| `pull-dotfiles.{service,timer}` | daily `git pull` of dotfiles | written to `$XDG_CONFIG_HOME/systemd/user` or `/etc/systemd/system` (root) — `scripts/deploy.d/99_periodic.zsh:9-18`, heredocs `:27-48`, enable `:50` | macOS launchd branch: `com.ctaylor.dotfiles.pull` plist `:63-99`; crontab fallback `:108-118` |
| `com.ctaylor.dotfiles.pull.plist` | same, macOS | heredoc + bootstrap — `99_periodic.zsh:99-103` | |
| `prune-tmpdir.{service,timer}` | daily `~/.tmp` reaper | user or `/etc/systemd/system` dir choice `scripts/deploy.d/56_tmpdir_prune.zsh:45-53`, heredocs `:55-73`, enable `:75` | launchd branch `:83-113`, crontab `:122-130` |
| `com.ctaylor.dotfiles.prune-tmpdir.plist` | same, macOS | heredoc + bootstrap — `56_tmpdir_prune.zsh:113-117` | |
| `/Library/LaunchDaemons/com.ctaylor.dotfiles.maxfiles.plist` | launchd maxfiles limit raise | heredoc, `sudo -n tee` — `scripts/deploy.d/77_maxfiles_limit.zsh:38-55,85`, bootstrap `:101-103` | Skips (prints manual steps) without passwordless sudo `:64-73` |
| `~/.config/systemd/user/agents.slice` | cgroup MemoryMax umbrella | generated — `bin/install-agents-slice.sh:60-76`, enable `:78-79` | RAM-dependent; "run once per host" (`:5-6`) |
| `hart-immich-backup.timer`, `hart-immich-prune.{service,timer}` | Immich backup/prune | installed **from out-of-scope repo** `~/repos/photo-steward/ops/` into `~/.config/systemd/user` — `scripts/setup-immich.sh:304-305` | House convention "unit and script live in their owning repo" (`setup-immich.sh:217-220`) |
| `hart-immich-backup.service` | (rendered, carries API key) | rendered from photo-steward template — `setup-immich.sh:308-335` | The one non-symlink real file in `~/.config/systemd/user` (`setup-immich.sh:288-292`) |

Package-unit enables only (no artifact): `setup-ceres-share.sh:46,50` (smb), `deploy.d/79_keyd.zsh:55` (keyd), `deploy.d/73_tailscale.zsh:152` (tailscaled), `deploy.d/42_monitoring.zsh:128` (atop), `install-niri-stack.sh:90-92` (vicinae).

## 2. infra — `/home/ctaylor/.local/infra`

Purpose-built for this problem: the only repo with a real deployer for its own units.

| Path | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `systemd/converge-check.service` | converge drift check (oneshot) | **Symlink** to `~/.config/systemd/user/` by `deploy:71` (`deploy_ln`, `:48-65`), daemon-reload `:77` | ExecStart indirection `${INFRA_DIR:-…}/bin/converge-check-run` (`converge-check.service:15`); `bin/converge-check-run` exists. Enablement deliberately human-only (`deploy:9-11`, timer header `:2-3`) |
| `systemd/converge-check.timer` | 6h cadence | Symlink by `deploy:72` | Cadence flagged PROVISIONAL (`converge-check.timer:5-6`) |
| `launchd/com.ctaylor.converge-check.plist` | same, macOS | Symlink to `~/Library/LaunchAgents/` by `deploy:84-85`; no bootstrap by design (`:86`) | Reached via dotfiles chain `dotfiles/scripts/deploy.d/66_infra.zsh:76-89` |

## 3. hart — `/home/ctaylor/repos/hart`

No installer script for most units; the "house convention is symlinks" and the `ln -s` commands live in unit-file headers and ops docs.

| Path | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `scripts/systemd/hart-wiki-mcp.service` | wiki MCP server :3112 | Manual symlink — `AGENTS.md:230` ("symlinked from `scripts/systemd/`") | Fails closed without env file (`hart-wiki-mcp.service:8-12`) |
| `scripts/systemd/cloudflared-hart-wiki.service` | Cloudflare Tunnel connector for wiki | **Script**: `ln -sf` at `scripts/wiki_mcp_tunnel_provision.sh:98`, enable `:100` | The one hart unit with a scripted deploy |
| `scripts/systemd/hart-home-ip-drift.service` + `.timer` | HOME_IP WAF drift guard | Manual symlink — `docs/home-ip-drift-guard.md:20` | Daily 09:07+jitter (`home-ip-drift-guard.md:27`) |
| `scripts/systemd/hart-claudeai-sync.service` + `.timer` | claude.ai chats → repo sync | Manual symlink — `docs/handover-home-ip-drift.md:136-137` | |
| `scripts/systemd/hart-openclaw-fallback-events.service` + `.timer` | OpenClaw fallback event ingest | Manual `ln -s` in unit header — `hart-openclaw-fallback-events.service:9-13` | "NOT installed by the build — house convention is symlinks" |
| `scripts/systemd/hart-openclaw-bridge-health.service` + `.timer` | OpenClaw bridge health | Manual `ln -s` in header — `hart-openclaw-bridge-health.service:12-16` | |
| `scripts/systemd/hart-openclaw-bridge-patch-check.service` + `.timer` | OpenClaw npm-drift detect | Manual `ln -s` in header — `hart-openclaw-bridge-patch-check.service:12-16` | |
| `scripts/systemd/hart-openclaw-stable-cutover.service` + `.timer` | one-shot beta→stable cutover (2026-09-02) | **None found** — no install comment, no script | The script it runs manages *other* units: `scripts/openclaw-stable-cutover.sh:85-98` |
| `scripts/systemd/hart-agent-homes-sync.service` + `.timer` | hart-agent-homes git sync (ceres→saturn) | **None found** — runs hourly on ceres per `wiki/active-projects-register.md:219` | |
| `scripts/systemd/hart-ollie-notes-backup.service` + `.timer` | ollie_notes restic backup (fires on ceres, executes on saturn) | **None found** | Superseded launchd plist retained disabled on saturn (`hart-ollie-notes-backup.service:11-12`) |
| `scripts/systemd/openclaw-gateway-10-state-dir.conf` | openclaw-gateway drop-in (state dir) | **None found** — live symlink documented at `docs/analysis/2026-09-03-agent-home-topology.md:137-138` | |
| `scripts/systemd/openclaw-gateway-20-ensure-stable.conf` | openclaw-gateway drop-in (self-heal stable) | **Script**: `ln -s` at `scripts/openclaw-stable-cutover.sh:96-97` (removes `20-ensure-beta.conf` at `:96`) | |
| `scripts/systemd/docker-10-after-tailscale.conf` | **docker.service** drop-in (boot race fix) | **None found** — live at `/etc/systemd/system/docker.service.d/10-after-tailscale.conf` per `~/repos/deploy/rss/README.md:98-101` | ExecStartPre `/usr/local/bin/wait-for-tailscale-ip.sh` (`docker-10-after-tailscale.conf:11`) is hart-tracked at `scripts/wait-for-tailscale-ip.sh` but hand-copied to `/usr/local/bin` |
| `appreciation/scripts/systemd/appreciation.service` | Appreciation SvelteKit app (unix socket) | **None found** — the README install block covers only export/backup (`appreciation/scripts/systemd/README.md:26-42`); zero references repo-wide | Depends on `/etc/tmpfiles.d/appreciation.conf` (`appreciation.service:26-27`), tracked nowhere |
| `appreciation/scripts/systemd/appreciation-export.service` + `.timer` | daily JSONL export + assertions | Manual `ln -s` — `appreciation/scripts/systemd/README.md:30-36` | |
| `appreciation/scripts/systemd/appreciation-backup.service` + `.timer` | restic 2-tier backup | Manual `ln -s` — `README.md:32-36` | |
| `claude.ai/claude_chats/5e16854c-…/artifacts/webfront-deploy-webfront.service` | webfront app unit (chat artifact) | **None** — historical; companion `webfront-deploy-justfile.txt:147` does `sudo mv /tmp/{{app}}.service /etc/systemd/system/` | Agent-improvised material checked into the chat archive, not wired to anything |

## 4. deploy — `/home/ctaylor/repos/deploy`

> **Update 2026-09-08 (post-snapshot):** the **webfront app is retired**
> (owner ruling — `docs/fleet-consolidation.md`, "Owner decisions"). Its
> container/postgres cleanup on ceres is pending live-ops; the `*.webfront.app`
> rows below are historical evidence of the pre-retirement state, preserved
> as cited. The `*.webfront.app` **DNS zone itself remains live** — it still
> names fleet hosts (paseo daemons per `zsh/rc.d/12_paseo.zsh`, the Portkey
> gateway at `ceres.webfront.app` per `zsh/rc.d/11_portkey.zsh`) and is
> unaffected by the app's retirement.

No systemd/launchd/caddy artifacts at all — compose only. **The root is not a git repo; only `rss/` has a `.git`** (cf. `dotfiles/scripts/setup-immich.sh:6-9`). All compose files run **in place** — nothing is copied or symlinked out of this repo.

| Path | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `ceres.webfront.app/docker-compose.webfront-app.yaml` (+ `-port`, `-repos`, `-development-dir`, `-http` overlays) | webfront-app container | Run in place via wrapper `ceres.webfront.app/webfront-compose.sh:2` (6-file `-f` layering) | `-http` variant not in the wrapper (manual) |
| `ceres.webfront.app/docker-compose.nginx-proxy.yaml` / `-standalone.yaml` | nginx-proxy + acme-companion + cloudflared / webfront-app + cloudflared | same wrapper `webfront-compose.sh:2` | Two mutually exclusive ingress shapes |
| `ceres.webfront.app/docker-compose.postgres.yaml` | postgres | same wrapper | |
| `ceres.webfront.app/docker-compose.cloudflare-ddns.yaml` | cloudflare-ddns | same wrapper | |
| `ceres.webfront.app/docker-compose.lanfuse.yaml` | webfront-app (langfuse variant) | **None** — not referenced by the wrapper | Leftover/alternate stack |
| `rhea.webfront.app/docker-compose.*` (8 files: webfront-app, -port, -repos, -development-dir, postgres, cloudflare-ddns, nginx-proxy) | same shapes for rhea | Run in place via `rhea.webfront.app/webfront-compose.sh:2` | Uses legacy `docker-compose` binary |
| `b.cronus.webfront.app/docker-compose.webfront-app.yaml` (+ `-port`, `-development-dir`, `external-nginx-proxy`) | webfront-app on b.cronus | Run in place via `b.cronus.webfront.app/webfront-compose.sh:2` | `external-nginx-proxy.yaml` only defines a network |
| `rss/docker-compose.yaml` | miniflux, db (postgres), rsshub, rss-bridge, digest-web | Manual `docker compose up -d` — `rss/README.md:23-28` | Only version-controlled subtree (own `.git`) |
| `immich/docker-compose.yaml` | immich-server, immich-machine-learning, redis, database, model-cache | **Installed copy** — written from dotfiles by `dotfiles/scripts/setup-immich.sh:180`; `up -d` is a deliberate human step (`setup-immich.sh:24-27`) | Live copy; tracked source of truth is `dotfiles/configs/immich/docker-compose.yaml` |
| `rss/digest/*` (job `rss-digest.{service,timer}`) | LLM feed digest | Units live in `~/.config/systemd/user` per `rss/digest/README.md:45` — **tracked in none of the five repos** | See scattered list |

## 5. paseo — `/home/ctaylor/repos/paseo`

| Path | Service | Deploy mechanism (file:line) | Notes |
|---|---|---|---|
| `docker/docker-compose.example.yml` | upstream Paseo daemon+UI example | None — upstream product example, not fleet-deployed | The fleet's actual paseo daemon units are generated by dotfiles (`setup-paseo.sh:388/532/618`) |

All `*.plist` hits in this repo are `node_modules`/build entitlements and Xcode `Info.plist`s — not launchd agents. No caddy/systemd/crontab artifacts.

## Scattered / unclear ownership

1. **`dotfiles/configs/caddy/caddy.service` has no deploy path.** `docs/caddy-ingress.md:7` says the installer installs it; `setup-caddy.sh:104-105` defines `TRACKED_CADDY_UNIT`/`UNIT_CHANGED` and never uses either; `setup_caddy_systemd` (`setup-caddy.sh:500-515`) writes only `override.conf`. The live `/etc/systemd/system/caddy.service` is hand-maintained ("Mirrored from pluto", `caddy.service:1-2`).
2. **`litellm-proxy.service` and `ccr-router.service` (dotfiles) are deployed by nothing.** README claims deploy.zsh symlinks litellm (`configs/ai/litellm/README.md:22-25`); the trace doc confirms both are "unreferenced by any fragment" (`specs/split-infrastructure-out-of-dotfiles-trace.md:46`), and the live litellm symlink on makemake dangles at the pre-`configs/ai/` path (`hart/wiki/fleet-converge-status.md:29`). ccr's `config.json:6` also points at the stale path.
3. **Codexbar units have two owners** — `deploy.d/20_symlinks.zsh:152-157` and `setup-llm-quota.sh:100-103` both link the same four units.
4. **Most hart units have no scripted installer** — the mechanism is `ln -s` commands embedded in unit headers or ops docs (`hart-openclaw-fallback-events.service:9-13` et al.; `AGENTS.md:230`; `docs/home-ip-drift-guard.md:20`). For `hart-openclaw-stable-cutover.*`, `hart-agent-homes-sync.*`, `hart-ollie-notes-backup.*`, and `openclaw-gateway-10-state-dir.conf` I found no install instructions at all, only evidence they run (`docs/analysis/2026-09-03-agent-home-topology.md:95`, `:137-138`).
5. **`appreciation.service` is a tracked orphan** — no install path documented (README installs only export/backup, `appreciation/scripts/systemd/README.md:26-42`), and its `/etc/tmpfiles.d/appreciation.conf` prerequisite (`appreciation.service:26-27`) is tracked in no surveyed repo.
6. **`docker-10-after-tailscale.conf` crosses three repos with no deployer**: tracked in hart, live in `/etc/systemd/system/docker.service.d/` documented only in `deploy/rss/README.md:98-105`, plus a hand-copied helper at `/usr/local/bin/wait-for-tailscale-ip.sh`.
7. **`rss-digest.{service,timer}`** run from `~/.config/systemd/user` (`deploy/rss/digest/README.md:45`) but are tracked in none of the five repos — the digest *code* is in deploy/rss, the units exist only on the host.
8. **The deploy repo root is unversioned** — only `rss/` is a git repo; the three webfront host dirs and `immich/` are plain directories (corroborated by `dotfiles/scripts/setup-immich.sh:6-9`).
9. **Cross-repo installers hide ownership**: dotfiles' `setup-immich.sh` deploys *photo-steward's* units and template into `~/.config/systemd/user` (`setup-immich.sh:304-335`) and dotfiles' compose into `~/repos/deploy/immich` (`:180`) — the live immich stack is thus owned by two repos at once.
10. **Live-host units owned by repos outside this census** (per dotfiles' own trace, `specs/split-infrastructure-out-of-dotfiles-trace.md:54`): ceres `~/.config/systemd/user` is a 48-unit symlink farm — libris (12), hart (9), telemetry (7), photo-steward (3), dotfiles (2); ~38% of fleet artifacts "trace to nothing". Same doc (`:57`) flags: 8 hart openclaw units "tracked but deployed nowhere", and a `neptune-swap-watchdog` plist executing `saturn-swap-watchdog.sh`, neither in any repo.
11. **Crontab manipulated outside any script**: saturn's one live crontab line runs `~/repos/hart-agent-homes/tools/distiller/hooks/distill-codex.sh` (`dotfiles/plans/ralplan-infra-repo.md:47`) — hart-agent-homes is outside the census and no surveyed script manages that entry. (The only scripted crontab writes are fallback branches: `deploy.d/99_periodic.zsh:114`, `56_tmpdir_prune.zsh:126`.)
12. **Agent-improvised material in-tree**: `hart/claude.ai/.../webfront-deploy-webfront.service` + `webfront-deploy-justfile.txt:147` (`sudo mv` into `/etc/systemd/system`) — a chat-archive deploy recipe not wired to any host dir in the deploy repo.
13. **Two portless shapes exist**: the generated system `portless-proxy.service` (`setup-caddy.sh:577`) vs. the user `portless.service` in restore docs (`docs/caddy-ingress.md:110-112`) — the latter's provenance is undocumented.
