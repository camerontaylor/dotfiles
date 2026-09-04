# Deep Interview Spec: Split infrastructure out of dotfiles

> Status: **pending approval** — no implementation may begin from this document without explicit human approval.

## Metadata
- Rounds: 18 (+ Round 0 topology gate) · Final Ambiguity: 9% · Threshold: 10%
- Type: brownfield · Generated: 2026-09-04
- Result: **PASSED**
- Upstream evidence: [`specs/split-infrastructure-out-of-dotfiles-trace.md`](split-infrastructure-out-of-dotfiles-trace.md) (3-lane deep-dive trace, cited throughout)
- Side deliverables produced during the interview:
  - `docs/fleet-declarability-options.md` — Nix endpoint vs movable-service tooling explainer (paseo agent, theoretical only)
  - Commit `8714e095` (pushed) — stale secrets `--force` docs fixed; secrets Phase-5 gate verified blocked at 3/4 (quaoar offline since ~2026-08-08). **Superseded same-day**: the owner waived quaoar and completed Phase-5 cleanup in a concurrent session (`26a96a30`, `26ee408a` — `.enc` files, `.sops.yaml`, legacy scripts dropped). Remaining secrets work: key rotation (human; Tailscale first) + `legacy-removed/` quarantine purge

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal | 0.95 | 0.35 | 0.3325 |
| Constraints | 0.90 | 0.25 | 0.2250 |
| Success Criteria | 0.90 | 0.25 | 0.2250 |
| Context (brownfield) | 0.85 | 0.15 | 0.1275 |
| **Total Clarity / Ambiguity** | | | **0.91 / 0.09** |

## Topology
| Component | Status | Description | Coverage / Deferral note |
|-----------|--------|-------------|--------------------------|
| infra-repo | active | Owner-of-record repo: dotfiles' 9 service triples + the ~45 unowned fleet artifacts; hybrid absorb+render; per-host manifests = permanent disposition ledger | Fully covered; litellm/ccr dispositions decided at bring-up |
| agents-disposition | active | Third agents repo (symlink model); vendored skills → pinned install manifest; provider write-through quarantined | Fully covered |
| deploy-system | active | Pull-based federation kept; `converge [--check]` with graduated autonomy; drift → wiki status page + push | Fully covered |
| dotfiles-residual | active | Dotfiles reduced to interactive-experience content + bootstrap + cgroup cluster; structural+behavioral done-gate | Fully covered |
| secrets Phase-5 cleanup | **deferred** | Parked tail of split #1; followed up by a dedicated paseo agent during this interview; blocked on quaoar (2026-09-04) | User-confirmed out of scope at Round 0 |
| submodule→vendor migration | **deferred** | The actual #1 churn source (41.3%/12mo); separate proven workstream (`75002f84`) | User-confirmed out of scope at Round 0 |

## Goal

Split the fleet into three uniformly-deployed repos — dotfiles (interactive-experience only; keeps the strict-portability bootstrap and chains sibling deploys), an agents repo (authored skills, provider configs, and agent wiring with provider write-through quarantined there, vendored skills replaced by a pinned install manifest with an adopt mechanism), and an infra repo (service configs + wiring with logic staying in owning repos — existing-first, infra last-resort — plus per-host manifests that double as a permanent disposition ledger, and a graduated-autonomy `converge --check` loop surfacing drift to a wiki status page with push on new drift) — where manifests and drift detection land *before* any content moves, and each component finishes only through its mechanically checkable done-gate.

The trace reframed the original request: the felt pain was mis-attributed (ceres-only infra is 1.8% of commits; the real problems are ~45 *unowned* live artifacts, provider-content provenance inside the agents tree, and a federation with no reconciliation loop). This spec addresses the real mechanisms, not the original attribution.

## Constraints

1. **Logic vs wiring**: service *logic* lives with the service's owning repo; the infra repo owns configs and deployment wiring only. Orphaned logic: existing-repo-first (rss's local repo gains a remote and joins the federation), infra repo as explicitly-marked owner-of-last-resort for small glue (swap watchdogs, omc-browser bridges).
2. **`~/repos/deploy` is a managed render target** after cutover — code/units/compose live in repos; secrets and env render out at deploy time (the `a8f5645f` immich pattern, fleet-wide); never hand-edited.
3. **Secrets never enter the infra or agents repos**; the private secrets repo renders per the established pattern with its `all|ceres|immich|libris`-style gates.
4. **The federation convention stands**: hart, libris, telemetry, photo-steward, ollie_notes keep their units; the infra repo is the missing owner-of-record for the unowned bucket, not a competitor to existing owners.
5. **Skill provenance model**: third-party skills are installed by a pinned manifest and NOT tracked; user-authored skills are tracked; deliberately modified vendored skills can be *adopted* into tracking; ignore/include carve-outs must be robust against inconsistent provider-CLI write behavior.
6. **Provider/CLI write-through is quarantined**: symlink targets for `~/.claude`, `~/.codex`, `~/.agents` etc. live in the agents repo, so provider-initiated writes produce diffs there, never in dotfiles.
7. **The cgroup shell cluster stays in dotfiles** (`00b_agents_slice.zsh`, `04c_worktree_scope.zsh`, `env.d/06_resmon.zsh`, `bin/install-agents-slice.sh`) — load-order-coupled to the interactive shell hot path; `agents.slice` is a cgroup slice, not the AI layer.
8. **Experience-vs-service rule** for gray-zone items: dotfiles keeps anything shaping the interactive experience even when host-gated or root-installed (keyd, karabiner, wake-peers, obs, macOS defaults, tmpdir-prune, self-update timers); infra takes anything serving the network/fleet (tailscale fragment + all service triples + `eris-macos-bootstrap.zsh`).
9. **Graduated converge autonomy**: timers auto-apply safe idempotent classes (symlinks, config renders, unit-file placement); NEVER auto-restart services or touch data paths — those surface in the drift channel for a human-run `converge` on that host.
10. **Uniform coverage**: all three repos deploy to all five boxes (ceres, makemake, saturn, neptune, quaoar); per-host manifests differentiate (quaoar's infra manifest ≈ syncthing + membership); offline boxes converge on return; eris is excluded from the matrix (wake-peers peer only).
11. **Composition**: dotfiles deploy ensures sibling checkouts exist and chains their deploys (the `65_secrets.zsh` auto-clone precedent); the agents repo integrates via symlinked fragments in the existing gitignored 90–99 `rc.d`/`env.d` slots; all hooks no-op gracefully when siblings are absent.
12. **Portability disciplines**: only dotfiles keeps the dual-shell bash-3.2/BSD bootstrap discipline; infra and agents repos run post-bootstrap and may assume the mise toolchain (recovery = re-run dotfiles bootstrap, which chains back).
13. **Sequencing**: per-host manifests + `--check` land FIRST (baseline inventory on a live drift detector); content moves execute against it. No "move everything, then convert" phase.
14. **Two-homed components split along the logic/wiring rule** — Portkey: zsh CLI + aliases + fleet wiring → agents repo; `portkey-gateway.service` + `config.json` + state → infra repo, manifest-gated to ceres (ending the current unconditional unit symlink onto systemd-less Macs, `20_symlinks.zsh:126`).
15. **Path indirection**: the ~12 files referencing `~/.local/dotfiles` inside the agents layer (worst: `cc-worker.sh`) are fixed during the move via stable well-known paths, never hardcoded repo locations.

## Non-Goals

- Secrets split remaining work (deferred; tracked in `plans/ralplan-secrets-repo-migration.md`): Phase-5 dotfiles cleanup **completed 2026-09-04** (`26a96a30`, quaoar waived); still open are key rotation (human; leaked Tailscale authkey first) and the `legacy-removed/` quarantine purge.
- Submodule→vendor migration (separate workstream).
- Relocating other owning repos' units into the infra repo.
- Any Nix / k3s / Nomad / Swarm migration — evaluated theoretically in `docs/fleet-declarability-options.md`; the chosen system is the manifest + converge loop over the existing federation.
- Fixing OpenClaw's failing crons (flagged; owned by OpenClaw, outside infra scope beyond their `deliberately-left` manifest entries).

## Acceptance Criteria

**Infra repo (parity gate)**
- [ ] Per-host manifests exist for all five boxes and double as the disposition ledger: every artifact in the live-fleet inventory (daemons, user units, timers, crons, containers, launchd plists) carries `adopt` / `logic-to-owner` / `retire` / `deliberately-left(reason)`.
- [ ] `converge --check` runs on every host and reports **zero unmanifested artifacts** and zero drift on adopted ones — permanently, not just at migration end.
- [ ] The 9 dotfiles service triples are moved (git mv + history note); `~/repos/deploy` trees are absorbed per the hybrid rule; rss has a remote and owns its logic.

**Agents repo (hard gate + service health)**
- [ ] `configs/ai/` is gone from dotfiles except thin load hooks; no vendored/provider-shipped content is tracked anywhere, enforced by a pre-commit/CI check in the agents repo (adopt mechanism exempts deliberate adoptions).
- [ ] A fresh box gets the full agent environment from agents repo + pinned skill manifest in one chained deploy.
- [ ] Portkey/litellm/ccr service halves live in the infra repo and report healthy under `converge --check` (litellm/ccr may alternatively be `retire`d via their bring-up ledger decision).

**Deploy system (detect + fix + surface)**
- [ ] `--check` timers run per host with graduated autonomy; results aggregate to a machine-written status page in the hart wiki; new-drift transitions push (ntfy-class).
- [ ] The trace's known-broken set is fixed or explicitly dispositioned at bring-up: litellm `bad` on makemake, `dotfiles.pull` failing on saturn (128) and neptune (1), paseo-daemon status 1 on both Macs, tracked-but-undeployed units, inert units on systemd-less Macs, `neptune-swap-watchdog` misnaming.

**Dotfiles residual (structural + behavioral)**
- [ ] The 4 named seams are cut: `20_symlinks.zsh` (agents `:36-39,72-126` + infra blocks), `70_runtime_installs.zsh` (agent installs), `10_dirs.zsh:11-12`, `60_git_hooks.zsh:13-23` (codex filter moves to agents repo).
- [ ] A mechanical purity check (rg) finds no agent/service references outside the hook files and the retained cgroup cluster.
- [ ] Fresh-box `./deploy.zsh` yields the full QoL environment; hooks no-op when sibling repos are absent.

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| "Churn comes from ceres-only infra" | Trace measured 1.8% of commits / 0.2% of touches | Premise dropped; split justified by ownership + blast-radius + provenance instead |
| "Agents stuff is mine" | Probe B: ~75–85% of 92 skills vendored/provider content | Manifest-install model; tracking only authored + adopted |
| "A structured dynamic system must replace the deploy model" (contrarian round) | The federation already IS GitOps-lite; it lacks verification | Keep federation; add manifest + converge/check + surfacing |
| "Adopt everything for parity" (simplifier round) | Some artifacts are junk or deliberately platform-managed | Disposition ledger: full *accounting*, not full adoption |
| "Ledger and manifest are separate documents" (ontologist round) | Two-document drift risk | One artifact; "unmanifested" permanently detectable |
| "Secrets are already moved out" | 21 `.enc` tracked; Phase 5 gated | Follow-up agent verified blocked 3/4 + fixed docs (`8714e095`); owner then waived quaoar and completed cleanup (`26a96a30`) — now true bar rotation + quarantine purge |
| Repo names, manifest format, converge implementation language, exact ntfy channel | Not user-decided | *Agent-decided in planning* — flagged; no score depends on them |

## Technical Context

From the trace (full citations in `split-infrastructure-out-of-dotfiles-trace.md`): the fleet convention is units-live-in-owning-repo with a symlink farm (`setup-immich.sh:219`); dotfiles owns ~14% of ~120 live artifacts, other repos ~46%, ~38% unowned; the carve-out triple convention is written policy (`AGENTS.md:134-149`); the agents tree is path-independent except ~12 files; `gjc config set` demonstrates provider write-through (`20_symlinks.zsh:104-117`); the secrets split precedent shows mechanism-lands-cleanup-parks, motivating this spec's hard gates. Tooling declaration: no Nix/orchestrator migration — analysis preserved in `docs/fleet-declarability-options.md`.

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| InfraRepo | core | manifests, service configs+wiring, converge tool, render pipeline, orphan glue | owns wiring; renders into DeployDir; last-resort owner |
| AgentsRepo | core | authored skills, provider configs, shell wiring, bin launchers, SkillManifest, adopt mechanism, enforcement check | symlink-deployed; receives write-through; hooks into Dotfiles 90–99 slots |
| Dotfiles | core | QoL configs, bootstrap (bash-3.2/BSD), cgroup cluster, drop-in slots, sibling chaining | bootstraps siblings; experience-rule scope |
| HostManifest (= ledger) | core | per-host desired state + dispositions (adopt/logic-to-owner/retire/deliberately-left+reason) | input to ConvergeLoop; one per box |
| ConvergeLoop | core | --check timers, graduated-autonomy classes, drift transitions | reports to DriftChannel |
| DriftChannel | supporting | wiki status page, ntfy-class push on new drift | aggregated on ceres |
| DeployDir (~/repos/deploy) | supporting | render-managed trees | written only by render/converge |
| OwningRepos | supporting | hart, libris, telemetry, photo-steward, ollie_notes, webfront, rss (new remote) | keep units + logic |
| SkillManifest | supporting | pinned third-party skills; provenance states: vendored / user-authored / adopted-modded | installed per-machine |
| SecretsRepo | external | sops/age, render gates | renders at deploy; Phase-5 gate separate |
| FleetHosts | supporting | ceres, makemake, saturn, neptune, quaoar (eris excluded) | uniform 3-repo coverage |
| Portkey | supporting (two-homed) | CLI+aliases / service+config | split: wiring→AgentsRepo, service→InfraRepo(ceres) |

## Ontology Convergence
| Round | Entities | New | Changed | Stable | Stability |
|-------|----------|-----|---------|--------|-----------|
| 1 | 9 | 9 | 0 | 0 | N/A |
| 2 | 10 | 1 | 0 | 9 | 0.90 |
| 3 | 11 | 1 | 1 (AgentsLayer→AgentsRepo) | 9 | 0.91 |
| 4 | 12 | 2 | 1 | 9 | 0.92 |
| 5–7 | 13 | 1 (DispositionLedger) | 0 | 12 | 0.92–1.0 |
| 8–10 | 14 | 1 (DriftChannel) | 0 | 13 | 0.93–1.0 |
| 11 | 13 | 0 | 1 (Ledger merged into HostManifest) | 12 | 1.0 |
| 12–18 | 13 | 0 | 0 | 13 | 1.0 |

## Coverage
| Category | Status |
|----------|--------|
| 1 Functional Scope & Behavior | Clear |
| 2 Domain & Data Model | Clear |
| 3 Interaction & UX Flow | Clear (ops surfaces: converge CLI, status page, push) |
| 4 Non-Functional Quality | Clear (graduated autonomy, drift visibility) |
| 5 Integration & Dependencies | Clear (chained deploys, secrets render, federation) |
| 6 Edge Cases & Failure Handling | Clear (offline boxes, orphans, two-homed, path-bound files) |
| 7 Constraints & Tradeoffs | Clear (incl. rejected Nix/orchestrator paths, documented) |
| 8 Terminology | Clear (logic/wiring, adopt, unmanifested, experience-rule) |
| 9 Completion Signals | Clear (four mechanically checkable gates) |
| 10 Misc / Placeholders | Partial — deferred-to-planning: repo names, manifest schema, converge language, exact push channel; deferred-to-bring-up: litellm/ccr dispositions |

## Clarifications
### Session 2026-09-04
- Q: Topology (4 components + 2 deferrals)? → A: Looks right
- Q: `~/repos/deploy` relationship to infra repo? → A: Hybrid absorb+render; logic with service owners, configs+wiring in infra
- Q: Vendored skill tracking deliberate? → A: Manifest install; part accident/part CLI misbehavior; must support tracked-mine + adopted-modded
- Q: Slimmed agents layer location? → A: Third agents repo, symlink model
- Q: (contrarian) Deploy system shape? → A: Manifest + converge loop; Nix/orchestrator comparison delegated to paseo explainer
- Q: What stays in dotfiles? → A: Experience-vs-service rule
- Q: (simplifier) "At least parity" means? → A: Disposition ledger, 100% accounting
- Q: Agents split done? → A: Hard gate + service health (+ spawned secrets Phase-5 follow-up agent)
- Q: Deploy-system done? → A: Detect + fix + surface
- Q: Converge autonomy? → A: Graduated
- Q: Repos × hosts? → A: Uniform, all 3 on all 5
- Q: (ontologist) Ledger ≡ manifest? → A: One artifact
- Q: Dotfiles residual done? → A: Structural + behavioral gate
- Q: Orphan logic owner? → A: Existing-repo-first, infra last resort
- Q: Repo composition? → A: Dotfiles bootstraps + 90–99 drop-in slots
- Q: Drift channel? → A: Wiki status page + push on new drift
- Q: Eight edge resolutions? → A: Confirm all
- Q: Portability discipline? → A: Post-bootstrap freedom for new repos
- Q: Restate gate? → A: Yes, crystallize

## Interview Transcript
<details><summary>Full Q&A (18 rounds + topology gate)</summary>

Ambiguity trajectory: 100% → 75% (R1) → 73% (R2) → 73% (R3) → 64% (R4) → 58% (R5) → 54% (R6) → 54% (R7) → 42% (R8) → 42% (R9) → 38% (R10, soft warning: user chose threshold) → 38% (R11) → 33% (R12) → 33% (R13) → 27% (R14) → 27% (R15) → 18% (R16) → 15% (R17) → 9% (R18, restate confirmed).

Questions and answers as recorded in the Clarifications section above; per-round targeting, rationale, and scoring shown live during the session. Challenge modes: contrarian (R4), simplifier (R6), ontologist (R11) — each used once. Side dispatches: fleet-declarability explainer (R4, delivered `docs/fleet-declarability-options.md`), secrets Phase-5 follow-up (R7, delivered `8714e095` + gate-blocked report).
</details>
