# Fleet consolidation — what the tooling is actually for

Date: 2026-09-08. Status: direction notes, owner-reviewed goals distilled from
Cameron's own words. Not a ralplan. Supersedes the framing of
`plans/ralplan-declarative-nix-fleet.md` (see `docs/ralplan-distortion.md` for
why that plan's process, not just its content, is being replaced).

## How we got here (one paragraph)

Dotfiles began as a fork for preconfigured shell/tool niceties, then became
the natural home for *everything fleet-wide*: cross-OS tool installation,
secrets and their encryption pathway, daemons and infra, then agent tooling.
mise arrived for env management and stretched into global installs; brew,
cargo, npm, pacman/apt, submodules and curl-installs each claimed territory,
with if-ladders arbitrating. It works — "idempotent-ish", declarative intent
in imperative language — largely because LLM agents now do the maintenance.

## The pains, distilled

- **P1 — one repo, five jobs.** Home config, fleet tooling, secrets, infra,
  and agent setup all live in dotfiles by accretion, not decision.
- **P2 — too many installers.** mise, brew, pacman, apt, npm, pnpm, cargo,
  submodules, curl-of-binaries, native macOS (vp historically). Every pair is
  a potential two-owners conflict; several have already burned us (openclaw
  downgraded 4×, vite-plus role hijack).
- **P3 — imperative approximations of declarative intent.** Lex-ordered
  fragments converge, but ownership and ordering are implicit.
- **P4 — deploy-config sprawl.** Systemd units and service configs are
  scattered across repos; some were agent-improvised. The owner cannot
  enumerate them today.
- **P5 — submodules** as a distribution mechanism. Want gone. (Census
  2026-09-08: 48 remain — 24 nvim, 17 zsh, 4 tmux, 2 yazi, 1 ranger — the
  tools/ purge already removed the rest; stale memory said ~159.)
- **P6 — services welded to hosts.** Moving a service (e.g. off ceres to
  makemake, or onto eris's idle RAM) is a project, not an edit. k8s was
  rejected as overkill; this mobility want is what made Nix attractive.
- **P7 — bash parity for agents.** Largely delivered by the dual-shell port;
  the remaining goal is that agents running bash get the same environment,
  minus terminal cosmetics.

## What Home Manager was actually standing in for

The HM appeal decodes into five separable wants — none of which requires HM:

1. One explicit module per tool (interface, not accident).
2. One manifest that describes a machine.
3. One manager instead of ten.
4. Generations / rollback.
5. An established pattern in preference to a hand-rolled system.

Want 5 deserves the update Cameron already articulated: the instinct predates
LLMs. Agents internalized HM's design principles from training; hand-rolled
systems are now maintainable, re-implementation is cheap, and legacy
archaeology — not fresh code — is the expensive thing. Absolute effort
estimates (mine and Cameron's) are trained on pre-LLM labor costs; treat them
as relative measures only.

Peer-review caveat (codex, accepted): LLMs make *code generation* cheap — not
specification, testing, recovery, or institutional memory. And unsupervised
agents multiply locally-plausible conventions, which is exactly how unit
placement became unknowable (P4). Hand-rolled is viable **only** with a hard
schema boundary and mechanical enforcement; see the invariants below.

## Ideal world: what this fleet's tooling should look like

**Pets and cattle, split honestly.**

- **Interactive machines** (ceres-as-dev-box, quaoar, saturn, neptune) are
  pets: native OS, the hand-rolled home layer, one tool manager. HM/nix-darwin
  would add a permanent hybrid layer for thin benefit — the existing system
  already delivers reproducible home config.
- **Headless service boxes** (makemake, pluto, potentially eris) are cattle:
  **NixOS is genuinely strong here** — whole box declared in one flake,
  services as modules, host reassignment is an attribute flip. This is the
  *high-value half* of Nix, and the half the old plan deferred. Nix adoption
  cost ≈ migration cost, so fresh installs and repurposed boxes get NixOS from
  birth — but per codex (accepted): don't leave this passive, or NixOS stays
  permanently deferred. Nominated 2026-09-08: **makemake** (native, M5
  target) and **pluto** (NixOS at its already-wanted reinstall, M6). eris
  stays macOS by owner decision — see "Owner decisions" below.

**Four layers, one owner each, one placement rule per layer.**

| Layer | Owner | Rule |
|---|---|---|
| Home (shell, editor, terminal, XDG configs) | dotfiles | config file + symlink manifest entry |
| Tools (runtimes, CLIs, npm globals) | mise, one file | pin in `configs/mise.toml`; brew only for casks/GNU userland; OS pkg mgr only for root daemons |
| Services (daemons, containers, proxies) | owning repo + infra placement map | unit + pinned artifact + **declared state dir** + secrets refs; `services.toml` maps service → host |
| Agents (CLIs, skills, providers) | agents layer (per split plan) | fast-churn, deliberately not pinned like infra |

Secrets stay as-is: sops/age authority, rendered outside worktrees.

**Service mobility without an orchestrator.** For ~10 services on ~3 hosts, a
scheduler is overkill; what's missing is *declared placement* and *declared
state*. Keep `services.toml` deliberately boring (codex's framing, adopted):
identity + assigned host, implementation reference, state paths, secret refs,
ports/dependencies/health check, backup-and-restore procedure, migration
constraints. **No** auto-scheduling, failover, bin-packing, overlay networking
or service discovery — that road ends at bad Nomad. Stateless moves can be
one-line edits; **stateful moves are workflows** — each stateful service
carries an explicit migration runbook/command (stop → backup → transfer →
translate ownership → cut over → verify → rollback path). Do *not* render
NixOS modules and native systemd units from one generic intermediate model;
share the placement map and metadata, let each service supply per-backend
implementations.

**Complete the loop we already own — inside a hard boundary.** The fleet
already has 80% of a declarative system: the TOML manifest (dispositions) +
converge (observer) + deploy fragments (actuators). The missing piece is that
the actuators don't read the manifest — intent lives in scripts, the ledger
just watches. The greenfield move is manifest → apply → observe, one loop.
This is "a tiny home-manager of our own," and it is a trap **unless** two
conditions hold (codex, accepted):

1. **Scope is fenced**: files, links, package-ownership assertions, service
   enablement, observation. No embedded language, no dependency solver, no
   package builder, no generic module system.
2. **Apply is transactional**: render into a versioned generation directory,
   validate, atomically switch, retain prior generations, support rollback.
   Without generations you rebuild HM's least interesting parts while
   omitting its most valuable operational property.

**Submodules die** — but prefer existing lockfile-capable managers over a
bespoke fetcher (lazy.nvim for the 24 nvim plugins, a lockfile zsh manager for
the 17 zsh ones, tpm for tmux). A custom fetch script is an inferior package
manager; reserve it for irreducible cases.

**Explicit non-adoptions:** HM on interactive machines; nix-darwin near-term;
k8s/Nomad; all-Nix-everywhere (Mac friction + agent-tool churn fits nixpkgs
poorly — weekly-updated agent CLIs would end up in a writable npm prefix
anyway). Per codex: hold these as *testable* positions, not ideology — a
bounded HM pilot in a disposable home remains a legitimate probe if evidence
warrants; the burden of proof just sits with the adoption, not the status quo.

Full peer review: `docs/fleet-consolidation-codex-review.md` (codex
gpt-6-astra, brief-only, no repo access — deliberately decorrelated).

## Where does a new thing go? (the one-screen answer for any agent)

```
New thing arrives:
├─ user CLI tool or runtime        → mise (configs/mise.toml), pin the major
├─ npm global                      → mise npm backend / .default-npm-packages
│                                     (exception: openclaw — service-guard owned)
├─ macOS app, font, GNU userland   → brew (scripts/deploy.d/75_brew_setup.zsh)
├─ shell/editor/terminal config    → dotfiles configs/ + symlink fragment + manifest
├─ secret                          → secrets repo (sops/age), rendered at deploy
├─ daemon or service              → unit in OWNING repo + manifest entry
│                                     + services.toml placement; root steps human-run
├─ agent CLI/skill/provider config → agents layer
└─ host-specific quirk             → host-scoped fragment + manifest entry
```

**One declared owner per artifact class, enforced mechanically.** (Refined per
codex: "mise owns all user tools" is aspiration — some tools genuinely need
system libraries, privileged integration, or packaging mise can't deliver. The
durable rule is single *designated* ownership, with CI rejecting duplicate or
undeclared ownership.) If a new tool doesn't fit a row, that's a design
conversation, not an eighteenth installer.

**Invariants (any implementation must hold these):**

- One declared owner per artifact; duplicates are CI failures, not runtime
  arbitration (`50_mise.zsh`'s brew-fallback loop and the fd/delta/age
  dual-installs become explicit, declared exceptions or die).
- Every stateful service has backup, restore, migration, and rollback
  definitions before it counts as "managed".
- Apply is transactional with retained generations.
- Removal is explicit and conservative — undeclared ≠ deletable.
- Drift checking and apply share one normalized desired-state model.
- Agents extend versioned schemas with validation; they do not invent
  parallel conventions.

## Consolidation moves, value-ordered

Each independently shippable, reversible, with a kill criterion. Effort in
agent-sessions (relative measure).

| # | Move | Fixes | Effort | Kill criterion |
|---|---|---|---|---|
| M1 | Adopt the placement tree above into CLAUDE.md/docs | P1 (policy), agent confusion | done-when-merged | — |
| M2 | Unit/service census → manifest entries, **plus CI that rejects duplicate ownership and undeclared service artifacts** (codex: the single highest-leverage move — it attacks the recurring conflict class and produces the migration backlog) | P2, P4 | 1–2 | census shows <5 strays: skip formalizing |
| M3 | Kill submodules — 48 left, all editor/shell plugins (lockfile + fetch, or lazy.nvim-style lockfiles per editor) | P5 | 2–3 | plugin breakage worse than submodule pain |
| M4 | Finish installer consolidation (cargo is down to 3: `linear-cli`, `codewhale-cli/-tui`; 6 curl installs; → mise backends where they exist) | P2 | 1–2 | a tool has no working mise backend: document exception |
| M5 | `services.toml` + declared state dirs + **one rehearsed move** (a real service, ceres → makemake, and back) | P6 | 2–4 | the rehearsal shows placement isn't the bottleneck |
| M6 | NixOS on one cattle box (pluto or next fresh install), services via the same declarations | P6 endgame | 3–5 | M5 shows native mobility is already fine |

M5 is the keystone: it converts the vague mobility want into evidence about
what mobility actually requires, before any Nix commitment. M6 only happens if
M5 leaves a gap.

Census snapshots backing M2–M4: `docs/fleet-census-installers.md` (managers,
per-OS branches, dual-owner tools) and `docs/fleet-census-units.md` (units and
deploy mechanisms per repo). The installer census counts **17 distinct install
mechanisms** and 16 per-OS manager fan-outs — P2 quantified. The unit census
settles M2's kill criterion the other way: far more than 5 strays, including
live breakage — a dangling `litellm-proxy.service` symlink on makemake, a
`ccr-router` config pointing at a pre-move path, `caddy.service` documented as
installer-deployed but actually hand-maintained, an orphaned
`appreciation.service` with an untracked tmpfiles.d prerequisite, four hart
unit pairs with no install path at all, and a docker drop-in spanning three
repos with no deployer. M2 proceeds.

## Owner decisions (answered 2026-09-08)

- **pluto → the M6 NixOS venue.** Woken and probed: i7-5700HQ (4c/8t
  Broadwell), 16 GB RAM, Ubuntu 24.04 **with a GUI, booted from the 1 TB
  7200 rpm spinner** (98 G used) while two 128 GB SATA SSDs sit idle. Owner
  already wants a reinstall (off the spinner, drop the GUI) — so NixOS lands
  at near-zero marginal cost: install to the SSDs, keep the spinner as bulk
  storage. Later probing (other session, 2026-09-08) identified it as an MSI
  GS60 2QE laptop with EC-owned untunable fans, and found it already runs
  live services the reinstall must carry: SeaweedFS master+filer and
  t3-serve, plus the pull-dotfiles timer. Historical note: the tracked
  `configs/caddy/caddy.service` header says "mirrored from pluto" — it has
  run services before.
- **eris stays macOS** — Ollie uses it (iPad-familiar UI is worth the
  inconvenience for now). Its service class is therefore **disposable
  RAM-heavy workloads**: headless-browser servers and integration-test
  runners, not robustness-critical services like immich. This names a real
  pain: background agent-browser runs and integration tests burden agentic
  development; neptune currently absorbs them but has other uses. Offloading
  that class to eris (container or native) is a service-placement decision
  `services.toml` should express like any other.
- **M5 = RSS first, then immich → makemake.** Owner reframe: immich is
  scary in principle but low-risk in fact — its DB was rebuilt from a Google
  Takeout export weeks ago, so the move doubles as a live test of the backup
  infra built for future value before it becomes critical. RSS (same shape:
  compose + postgres, zero-stakes data) rehearses the runbook mechanics
  first. Feasibility verified: ~49 G immich library vs 335 G free on
  makemake's internal SATA; office wired LAN moves that in minutes. The
  runbook carries more than the compose stack: photo-steward backup/prune
  timers in ceres's user systemd (`setup-immich.sh:304-335`), the rendered
  backup unit embedding the machine-local API key (re-render on the new
  host), and slower ML indexing on the N97 (latency, not correctness).
  Precondition per the invariants: a **tested restic restore** first.
- **Postgres: declare, don't consolidate — now down to two.** Verified
  2026-09-08: three instances, all on ceres — immich
  (`postgres:14-vectorchord0.4.3-pgvectors0.2.0`, pinned by upstream), RSS
  (`postgres:17-alpine`), webfront (custom `16.3` + tds_fdw). Owner ruling:
  **webfront is retired** — its postgres goes (live-ops cleanup on ceres).
  RSS's DB is owner-personal and moves to latest + pgvector as a
  general-purpose vector store; immich's pinned requirements are honored.
  Per-instance overhead is small (~7 idle background processes and roughly
  50–150 MB RSS + ~100 MB WAL/catalog disk each) and the mobility argument
  overrides it: a shared instance welds services to one host. Each DB is
  declared as its service's state in `services.toml`. (Census gap found
  alongside: the telemetry stack — langfuse + seaweedfs on ceres — lives in
  `~/repos/telemetry`, outside the five censused repos; add it to scope.)
- **Agents repo: decided, no delay.** Layer 4 lands as its own repo — the
  domain is conceptually distinct from dotfiles, some CLIs churn their own
  configs, and development skills/processes are not shell niceties. Where
  the line is drawn: see below.
- **Retirements approved (2026-09-08, owner):** `ccr-router` (delete from
  the agents repo), `bin/webfront-root` + `bin/p` (delete from dotfiles),
  the webfront containers + postgres on ceres (archive the DB before volume
  removal), and litellm stripped fleet-wide (makemake's dangling symlink and
  any other remnants).
- **Agents remote live:** `git@github.com:camerontaylor/agents.git`
  (private, created 2026-09-08); `67_agents.zsh`'s clone leg now resolves on
  every fleet host with the SSH key.

## The agents-repo line

**Implemented 2026-09-08** on branch `agents-carveout` (pushed) plus
`~/.local/agents` `main` (pushed) — see `plans/agents-carveout-report.md`
for moves, consumers updated, and the live-ops sequence. The table below is
the design record; the report is the as-built record.

The test: **"If I stopped doing AI-agent work tomorrow, would I still want
this?"** Yes → dotfiles. No → agents repo. Two refinements:

1. **Installation stays with the tool layer; configuration moves.** The
   claude/codex/etc. CLIs keep installing via mise/npm per the placement
   tree — the agents repo owns their *config*, skills, and routing, never a
   second installer (or we recreate the two-owners bug class).
2. **Being a daemon doesn't make it infra.** Owning-repo convention (the
   photo-steward precedent) applies: agent-serving daemons keep their units
   in the agents repo; `services.toml` handles placement like any service.
   Services with an existing owning repo (openclaw → hart) stay put.

By that test, the line largely draws itself along the de-facto agents domain
the unit census exposed inside dotfiles:

| Moves to agents repo | Currently at |
|---|---|
| cc*/ccz-direct alias class + worker wrapper | `zsh/env.d/09_claude_code_aliases.zsh`, `scripts/agent-aliases.zsh`, `bin/cc*` wrappers |
| commit-conventional, generate-commit-msg (LLM git workflow) | `scripts/` |
| paseo setup + generated units + watchdog | `scripts/setup-paseo.sh`, `scripts/paseo-watchdog` |
| LLM proxy: portkey (configs + unit) — litellm is **retired** (replaced by portkey; delete its config, clean the dangling makemake symlink); ccr-router moves but is flagged a retirement candidate (unreferenced, stale paths) | `configs/ai/` |
| openclaw-mcp bridge config + unit | `configs/openclaw-mcp/` |
| codexbar / llm-quota stack (quota of LLM plans) | `configs/ai/codexbar/`, `scripts/setup-llm-quota.sh` |
| codex/claude/provider configs, skills, ~/.claude templates | `configs/ai/`, `~/repos/skills` |

Shell integration uses the already-reserved mechanism: dotfiles keeps its
gitignored numbered slots (rc.d/env.d 90–99 local, 96–99 agents hooks), and
the agents repo's deploy drops fragments into them — dotfiles never sources
the agents repo directly. This slots into the approved split framework's
existing conventions (ledger dispositions, sibling ordering) without
reopening any planning ceremony.
