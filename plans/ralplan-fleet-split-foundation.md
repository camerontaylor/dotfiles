# Foundation Plan — Three-Repo Fleet Split (Frozen Contracts)

> Status: **APPROVED 2026-09-04** — owner directed end-to-end orchestration of this plan
> ("orchestrate … end to end, using your best judgement"), which per §Approval freezes
> C1–C7 and the sequencing table and authorizes dispatching domain plan 1 (infra-repo).
>
> **Provenance**: ralplan run `1b5daf07` (gjc, deliberate mode) — planner 41,255 B ·
> intent 2,659 B · critic 19,446 B (codex `gpt-5.6-sol:xhigh`, verdict **ITERATE**) ·
> architect 19,406 B (verdict **BLOCK-as-frozen** = revise-and-refreeze, architecture sound).
> Receipts + sha256s: `.gjc/_session-1b5daf07-*/plans/ralplan/1b5daf07-*/`.
> The ACP session host failed twice after iteration 1; this final was **synthesized by the
> dispatcher** from the receipts, incorporating **all** critic findings (F1–F5 + expansions)
> and **all** architect recommendations (1–9). Nothing else was reopened.
> Full option analyses live in the planner receipt (§5); spec = `specs/split-infrastructure-out-of-dotfiles-spec.md`; evidence = the trace beside it.

## Summary

Three uniformly-deployed repos — **dotfiles** (interactive experience, strict-portability
bootstrap, cgroup cluster), **agents** (`camerontaylor/agents` → `~/.local/agents`), **infra**
(`camerontaylor/infra` → `~/.local/infra`) — over the *kept* pull-based federation, governed by
seven frozen contracts. Manifests + `converge --check` + drift channel land on the fleet
**before any content moves**. The four domain plans (infra-repo, agents-disposition,
deploy-system, dotfiles-residual) are later ralplan runs that consume §C1–C7 as
non-negotiable inputs; a domain plan that cannot implement a contract **escalates**
(amendment run + `schema_version` bump) — silent deviation voids the foundation.

## Frozen agent-level choices

| Choice | Frozen value | Why (full analysis: planner §5) |
|---|---|---|
| Manifest format | **TOML** | comments carry `reason`/`evidence` inline (ledger-essential); strict types → exact drift diffs; YAML/JSON invalidated |
| Sibling paths / slugs | **`~/.local/infra`, `~/.local/agents`** · `camerontaylor/{infra,agents}` | extends the proven `~/.local/dotfiles` + `~/.local/secrets` family; `~/repos/` rejected (owning-repo federation namespace) |
| Status file | **JSON** at `${XDG_STATE_HOME:-$HOME/.local/state}/converge/status.json` | machine-written state outside all worktrees (secrets-render precedent); that env fallback is canonical everywhere (timers don't source env.d) |
| Env indirection | **`$DOTFILES`** (existing convention) + new **`$AGENTS_DIR`**, **`$INFRA_DIR`** | `$DOTFILES_DIR` does not exist as a fleet var — stays a render-script local |

## The Seven Frozen Contracts (amended per critic + architect)

### C1 — Per-host manifest ≡ permanent disposition ledger
One TOML file per host at `infra/manifests/<host>.toml` (ceres, makemake, saturn, neptune,
quaoar). A second ledger document MUST NOT exist. Header: `schema_version`, `host`, `os`,
`inventory_date`. Entry fields: `id`, `kind`, `owner`, `disposition`
(`adopt | logic-to-owner | retire | deliberately-left`), `target`
(`present-enabled | present | absent`), `reason` (required for the last three dispositions),
`evidence`, `notes`. State vocabulary is unified on **`retire_pending`**.

**Live-set definition (per kind — makes "zero unmanifested" computable):**

| kind | live surface L | id namespace |
|---|---|---|
| `systemd-unit` | user-manager unit files **plus** `/etc/systemd/system` entries **not owned by the package manager** (dpkg/pacman verify); package-shipped units are out of inventory | `systemd-unit:user:<name>` / `systemd-unit:system:<name>` |
| `launchd` | `~/Library/LaunchAgents` + `/Library/LaunchDaemons` (world-readable; no sudo needed) | `launchd:agent:<Label>` / `launchd:daemon:<Label>` |
| `cron` | managed stores by **name** (`cron:<store>:<name>`, e.g. OpenClaw); raw crontab **command lines only** (env/comment lines are attributes, not artifacts), `cron:<user>@<sha1(normalized)[:10]>` | as shown |
| `container` | running containers, compose-canonical names | `container:<runtime>:<name>` |
| `path` | **manifest-declared paths only** — UNMANIFESTED is N/A for this kind (MISSING/DRIFTED only). Derivation seeds: ExecStart/plist/cron target-resolution probe (trace §Recommended Probe) ∪ trace-named clusters ∪ managed render roots | `path:<$HOME-relative>` |

Detection: `UNMANIFESTED = L ∖ M` (enumerable kinds), `MISSING = (M, target≠absent) ∖ L`,
`retire_pending = (M, target=absent) ∩ L`, `DRIFTED` = present with source mismatch.
**Zero-unmanifested is a permanent gate, not a migration-end condition.** Manifests MUST be
derived from live inventory, never repo listings (makemake precedent). Dispositions:
logic-to-owner = existing-repo-first (rss gains a remote); infra `adopt` = explicitly-marked
last resort for small glue; `deliberately-left(reason)` is valid output.

### C2 — Three-repo composition
Chain (frozen): dotfiles deploy → `65_secrets.zsh` → **infra** ensure+deploy → **agents**
ensure+deploy. Hard edges only: dotfiles-first (mise toolchain; recovery = re-run dotfiles
bootstrap), secrets-before-infra (renders).

- **Sibling-ensure** copies the `65_secrets.zsh` shape: clone-if-absent, `--ff-only` pull,
  invoke the sibling's deploy entry; idempotent; `--dry-run` supported.
- **Deploy-entry interface (frozen)**: each sibling exposes one stable entry script with
  `--dry-run` REQUIRED and defined exit codes.
- **Failure semantics (frozen)**: **warn-not-fail** by default (65_secrets precedent) — the
  chain never breaks a green dotfiles deploy; each repo's last-deploy result + timestamp is
  recorded in a `deploy` block of `status.json` and ages on the wiki under the same STALE
  rule (closes the drift channel's blindness to deploy failures — the `dotfiles.pull` 128/1
  class). `--strict` opts into fail-the-chain.
- **Sibling-absent no-op**: exit 0, one notice line, zero mutations, deploy stays green.
- **Agents shell integration**: agents repo **symlinks** (never copies — write-through must
  land in the agents repo) fragments into dotfiles' gitignored 90–99 slots.
  **Allocation (frozen): agents fragments own 96–99; human local overrides keep 90–95.**
  Dangling links on sibling removal are tolerated by the existing `[ -e ]` glob guards —
  that mechanism IS the no-op guarantee. The dotfiles purity gate is scoped to **tracked
  files only**.
- **Path indirection**: repo content never hardcodes `~/.local/<repo>`; use XDG consumer
  symlinks (`~/.claude`, `~/.agents`, …) or `$DOTFILES` / `$AGENTS_DIR` / `$INFRA_DIR`.
  The ~12 path-bound agents files are fixed under this rule during the move.

> **AMENDMENT 2026-09-06 (owner-directed, D3 escalation from domain plan 1 A7):** the infra
> sibling-ensure fragment (`66_infra.zsh`) lands now under domain plan 1 rather than waiting
> for rows 2/4; rows 2/4 retain the agents edge and chain hardening; the converge timer's
> pull survives as defense-in-depth (both writers `--ff-only` + idempotent).

### C3 — Coverage matrix + offline convergence
All 3 repos × all 5 hosts (ceres, makemake, saturn, neptune, quaoar) — all 15 cells deploy;
differentiation happens *inside* manifests (quaoar's infra manifest ≈ syncthing + membership).
**eris excluded**: wake-peers peer only; no manifest, no deploy; `eris-macos-bootstrap.zsh`
moves to infra as a hand-run script. Offline hosts converge on return via the kept
pull-timer/post-merge chain. **STALE rule**: last successful check older than
`max(48h, 2× check interval)` renders STALE on the wiki — absence of data is itself surfaced.

### C4 — Graduated converge autonomy
| Class | Membership |
|---|---|
| **AUTO-APPLY** | idempotent file placement: symlinks, non-secret renders, unit/plist/cron *file* placement (not activation), `daemon-reload`, pinned-skill installs |
| **SURFACE** | any service side effect: enable/disable/start/stop/restart, launchctl load/unload, compose up/down, restart-needed |
| **HUMAN-ONLY** | data-path ops, secret material, **manifest/disposition edits**, retire executions, cross-host bulk ops |

Frozen test: worst-case re-run destroys data / interrupts a service / crosses a host → ≥
SURFACE; data or secrets → HUMAN-ONLY. Gray zone defaults safer. Converge governs
infra-manifest artifacts **only** — existing dotfiles deploy behaviors (keyd, macos-defaults,
brew, tmpdir-prune, self-update) are not reclassified.

### C5 — Drift channel
`status.json` (shape per planner C5: `schema_version`, `manifest_rev`, summary counts,
findings with `first_seen`/`last_seen`, plus the C2 `deploy` block) written every check run.
**Push semantics**: ntfy-class push **iff** the error-set gains a new id (ok→error);
recovery updates the wiki silently; identical error-set → silence. Hosts push to the ceres
spool (`${XDG_STATE_HOME:-$HOME/.local/state}/converge-spool/<host>.json`) over Tailscale
SSH — **device-auth preferred; any per-host keys are HUMAN-ONLY secret material provisioned
via the secrets render, never tracked**. A ceres-gated, infra-owned renderer rewrites a
dedicated machine-written hart-wiki page (fleet matrix, unmanifested list, STALE hosts,
deploy-chain health, finding/manifest ages); **publish is atomic and always leaves the hart
worktree clean**; human edits are overwritten by design. ntfy topic resolves from the
secrets render at bring-up. **Schema consumer rule**: consumers MUST hard-fail loudly on a
higher `schema_version` or unknown enum — never best-effort parse.

### C6 — Acceptance authority
The spec's four gates (G1 infra parity · G2 agents hard gate + service health · G3 deploy
detect+fix+surface · G4 dotfiles structural+behavioral) are the **only** completion
authority; the spec's Acceptance Criteria text is canonical. Binding rule: every domain-plan
criterion cites exactly one gate; **tie-break for dual-gate criteria (frozen): authority =
the gate owned by the plan that executes the criterion; the other gate cites it as
corroboration only.** Unmapped criteria are out of scope or escalate.

### C7 — Phase gate + sequencing
No content moves until ALL of:
- **PG1** — five manifests exist and pass schema validation;
- **PG2** — `converge --check` on cadence on all *reachable* hosts;
- **PG3** — zero unmanifested on all *reachable* hosts;
- **PG4** — drift channel live: wiki page rendering from the spool via a **provisional
  single-host publish path shipped in infra Phase A** (deploy-system owns hardening), plus
  one observed transition push — **injected drift counts**.

**Offline-host rule (frozen)**: PG2/PG3 bind on four hosts green + the absent host marked
**RETURN-PENDING** (its manifest schema-validated in-repo; wiki row STALE/PENDING); the
permanent zero-unmanifested gate binds on its return; a full skip requires an explicit owner
waiver (secrets Phase-5 quaoar precedent).

## Domain-plan sequencing (frozen order)

| # | Plan | Consumes | Entry conditions | Key exclusions |
|---|---|---|---|---|
| 1 | **infra-repo** — A: skeleton + manifests + `--check` + provisional drift channel (satisfies PG1–PG4); B: moves (9 triples git mv, `~/repos/deploy` hybrid absorb+render, rss remote, unowned-bucket adoption) | C1 C3 C4 C5 C6(G1) C7 | this plan approved | converge language; litellm/ccr dispositions (bring-up) |
| 2 | **agents-disposition** — third repo, skill manifest + adopt, write-through quarantine, portkey split, ~12 path fixes | C1 C2 C3 C6(G2) | PG1–PG4 green (per offline-host rule); infra repo exists | skill-manifest schema details; provider-CLI fixes |
| 3 | **deploy-system** — autonomy enforcement, cadences, chain hardening, wiki publish finalization, broken-set closure | C1 C3 C4 C5 C6(G3) C7 | infra + agents exist | ntfy topic; cadence values |
| 4 | **dotfiles-residual** — 4 seam cuts, purity check, fresh-box gate | C2 C3 C6(G4) | agents-disposition DONE (**explicitly last** — seams cut only after tenants vacate) | QoL changes beyond the 4 seams |

## Verification (executed by domain plans; highlights)

Unit: TOML round-trip ×5 hosts; identity goldens (namespaced unit ids, launchd Labels, cron
normalization, compose names); transition-differ goldens (new id → push; repeat → silence;
recovery → wiki-only). Integration: decoy-unit detection on one Linux + one Mac; sibling-absent
no-op (exit 0, zero writes); sibling-**failure** warn-not-fail + `deploy` block surfacing;
offline/STALE; **purity-gate scoping** (passes with agents fragments in 96–99 untracked slots,
fails on an agent reference planted in a tracked file). E2E: fresh-box chained deploy in a VM
(with and without siblings); fleet table from 5 spool files; exactly-one-push on injected
drift. Pilot: two-OS soak (one Linux + one Mac, ≥1 week) in infra Phase A **before any move**.

## Top risks

Identity churn → push storms (named cron ids, normalization, pilot soak) · schema gap found
after freeze (`schema_version`, two-OS pilot, amendment protocol, consumer hard-fail) ·
silent timer death → false green (STALE rule + manifest age) · split-#1 residue pattern
(hard gates + permanent zero-unmanifested + dotfiles-residual last) · makemake
under-inventoried (live-derivation rule) · deploy-chain silent decay (warn-not-fail +
`deploy` block on the wiki).

## Approval

Approving this plan freezes C1–C7 and the sequencing table, and authorizes dispatching
domain plan 1 (infra-repo) as its own ralplan run. Repo-file citations in the receipts are
verified by content; cite by symbol/heading going forward (line anchors drift — critic F4).
