# Plan: Declarative fleet with Nix and Home Manager

Status: pending approval
Date: 2026-09-07 | Mode: deliberate | Review iteration: 2
Primary spec: `specs/split-infrastructure-out-of-dotfiles-spec.md`
Related approved plans: `plans/ralplan-fleet-split-foundation.md`, `plans/ralplan-infra-repo.md`

## RALPLAN-DR

**Principles:** one editable disposition ledger; one active writer per target; observe before taking ownership; keep secrets out of source/build closures; separate builds, activation, service lifecycle, and data recovery.

**Decision drivers:** reproducible user environments across Linux/macOS; preserve the working split/drift infrastructure; achieve incremental benefits without simultaneous OS, runtime, and service migrations.

| Option | Benefits | Costs and limits |
|---|---|---|
| A. Standalone Home Manager first, nix-darwin next, NixOS optional | Reuses current OS installations and repo ownership; small reversible steps; modules can later integrate into system configurations | Mixed management persists; adapters and explicit ownership handoffs required |
| B. Commit to NixOS on Linux and nix-darwin on Macs immediately | Strongest eventual host declaration; less native Linux configuration glue | Linux storage/boot/recovery migration; larger service and runtime changes; Mac state remains partly external |
| C. Retain native OS management and adopt HM permanently | Avoids Linux reinstall; reproducible user configuration | Root Linux services still need native adapters or a separately selected declarative manager; cannot claim full-host reproducibility |
| D. Keep manifest/converge alone | Lowest transition cost; already covers fleet inventory | Does not deliver Nix package/config generations requested here |

**Recommendation:** A. It addresses user-environment reproducibility with the smallest live cutover while preserving existing recovery and drift reporting. C remains a viable long-term endpoint if preserving Linux distributions matters more than full system declaration. B needs a separate host-migration decision. Replacing converge with Nix alone is not sufficient: Nix does not supply this fleet's disposition history, unmanaged-artifact inventory, service health, stale-host reporting, or notification channel.

## Context and evidence

This is an additive roadmap and proposed amendment, not authorization to execute. The original spec explicitly excluded Nix. Its approved foundation remains unchanged until an amendment is accepted; researching the newly requested direction does not reopen its existing production gates.

Repository evidence on 2026-09-07:

- Initial dotfiles HEAD observed: `2358ab3a`; architecture review later observed `4f9ed700`. Infra HEAD: `47619b6`. These are point-in-time observations; concurrent work can advance them, so W0 re-verifies inputs.
- Current manifest counts: ceres 83, makemake 13, saturn 27, neptune 31, quaoar 4: **158**. The historical H1 signoff recorded 155; the difference is three subsequent ceres entries (80 → 83).
- `../infra/docs/phase-a-signoff.md` records PG1/PG3 evidence, satisfied PG4, and PG2 soak accruing from 2026-09-06. Phase B/H3 remains open. The background reports a review scheduled for 2026-09-13 20:00 AEST; this session did not verify that schedule or reprobe remote hosts.
- Local ceres was verified as CachyOS Linux x86_64. Other manifests verify OS family, not current OS version/architecture.
- `../infra/converge/converge/check.py` checks generic paths for existence and unit symlinks literally; present-enabled is not yet independent enablement/health proof. Findings can accompany exit 0. `inventory/systemd.py` recognizes dpkg/pacman ownership, not NixOS ownership. There is no general `converge apply` implementation yet.
- `scripts/secrets-render.zsh` still targets gitignored SSH/private TLS files inside dotfiles. This is a source-capture risk, not evidence that secrets were committed. `scripts/setup-immich.sh` documents a machine-local API key whose recovery must be accounted for.
- `scripts/deploy.d/50_mise.zsh` upgrades mise tools during ordinary deploy and can try-restart OpenClaw. Keeping it means runtime reproducibility is explicitly partial.
- `docs/fleet-declarability-options.md` overstates elimination of drift and near-free secret migration. Correct those claims during implementation; retain it as historical analysis.

## Target architecture and boundaries

| Host | Evidence today | First target | Later system target |
|---|---|---|---|
| ceres | CachyOS, Linux x86_64 verified | Standalone HM; first live canary is bat config only | NixOS optional, separate recovery/storage plan |
| makemake | Linux manifest; Ubuntu is historical description; arch unverified | Standalone HM after native preflight | Preferred candidate to assess an eventual NixOS experiment; suitability unverified |
| saturn | macOS manifest; Mac Studio is historical description | Standalone HM after native preflight | nix-darwin recommended, integrated HM only after explicit activation ownership transfer |
| neptune | macOS manifest; 2019 iMac is historical description | Standalone HM after OS/arch/package availability checks | nix-darwin recommended if supported by selected pins |
| quaoar | Linux, RETURN-PENDING; Arch laptop is historical description | Standalone HM on return after reader/bootstrap and inventory gates | Keep current OS unless separately decided |

The coverage target remains all three repos on all five hosts: **15 cells**, with existing quaoar waiver/return semantics. This is the required end state, not a claim that agents disposition is already complete. eris remains excluded.

- **dotfiles:** interactive modules and configuration, portable bootstrap, retained cgroup shell cluster.
- **agents:** authored/adopted modules and provider configuration, preserving required writable provider targets. Do not turn whole provider directories into immutable store links.
- **infra:** aggregate flake/release composition, host wiring, single TOML disposition ledger, observer and deployment adapters.
- **Owning service repos:** retain logic and units; expose reusable modules or curated source artifacts consumed at pinned revisions. A project does not need a complete flake conversion merely to supply a unit.
- **Secrets repo:** existing SOPS/age authority and renderer initially; plaintext stays external to Nix inputs.
- **mise:** remains runtime/Node/npm authority initially. Nix must not introduce a competing Node/npm/shim chain. CLI packages migrate individually, including removal of old mise/brew fallback writers.
- **Services:** HM covers user configuration, not privileged Linux system management. Existing Linux root placement remains human-run through native adapters. Keep Docker Compose and its data layout initially; no Quadlet, scheduler, or container-runtime conversion is required.
- **Macs:** nix-darwin later covers selected system settings, launchd and Brew declarations. OS updates, TCC approval and mutable GUI/application state remain explicit external dependencies. Brew lists do not become version-pinned merely through a flake lock.

A fleet-wide HM milestone is a scoped declarative user environment, not a fully declarative host fleet. Full-host Linux requires a later NixOS or other explicit system-management decision.

## Contract amendments and traceability

Propose an amendment before implementation that admits Nix into the former non-goal, adds backend/schema semantics and declarative acceptance, and defines release-aware deployment under C2. Do not silently edit approved plans.

C1 retains artifact IDs, owner repo, dispositions and the sole TOML ledger; backend is a separate attribute. Generated expectations/activation receipts are machine-derived evidence, never a second editable disposition database. Preserve generic path UNMANIFESTED=N/A.

C2 retains dotfiles → secrets → infra → agents, sibling absence behavior, required dry-run, warn-not-fail with visible failure status, and strict failure mode. Add locking and exact-release selection. Resolve `INFRA_DIR` consistently. Do not bypass agents ownership by importing pre-move provider trees.

C3 retains all 15 cells and RETURN-PENDING behavior. C4 retains its class boundaries, including no sudo in infra automation: builds do not imply permission for activation. C5 retains existing findings, error-set notifications, spool/wiki and STALE semantics, plus strict version/enum handling. C6 needs explicit scope for the new readiness gates; they do not certify original G1–G4 completion. C7, soak/A7/H3, and frozen domain ordering remain prerequisites for live moves.

| Work package | Acceptance authority | Contracts / existing gate relationship |
|---|---|---|
| W0 evidence and amendment | Proposed declarative addendum | C1–C7; G1–G4 remain separate |
| W1 safe sources and recovery dependencies | Proposed declarative addendum | C1/C4/C7; corroborates G1 |
| W2 observer and schema | G3 for observer behavior; Nix readiness under addendum | C1/C3/C5/C6/C7 |
| W3 pinned builds and release adapter | Proposed declarative addendum | C2/C4/C5; corroborates G3 |
| W4 ownership transfer protocol | Proposed declarative addendum | C1/C2/C4/C7 |
| W5 static pilot and W6 HM rollout | Proposed declarative addendum | C1–C7; corroborates G4, never substitutes for purity/seam gates |
| W7 services/system backends | Separate domain amendment/host plan | G1 or G2 in owning split domain; C4 remains binding |

Each implementation acceptance criterion must choose exactly one authority when its domain plan is written. G1 infra extraction, G2 agents disposition, G3 deploy hardening, and G4 residual purity/fresh-box behavior retain their original owners and completion tests. This document has no FR/SC identifiers to carry forward.

## Ordered work packages

### W0 — Reconcile gates and verify platforms

Read the authoritative signoff and approved split plans; record dated reachable-host facts, missing agents-repo work, installed Nix state, OS/version/architecture, free disk, service manager, shell startup and recovery access. Verify package/build support natively, particularly on the older Mac; do not infer it from hardware names. Coordinate W1 with any in-flight secrets rotation or cleanup before choosing relocation timing.

Choose and pin the Nix implementation and installer independently, documenting daemon ownership, shell integration, uninstall and recovery. Account installer-created units/plists in the ledger before fleet installation; root installation is a human-run step. Test on disposable environments first.

**Exit:** proposed amendment and preflight checklist are reviewable; no live path transfers. Research and isolated disposable builds may precede H3; production installs/transfers wait for the relevant gates and authorization. Existing split domains continue in their approved order.

### W1 — Establish safe build sources and external secrets

Inspect renderer destinations and consumer paths without reading plaintext. Define curated, non-secret module/config inputs before any local path or flake source enters the store. Filtering a derivation after its parent source has already been copied is insufficient. Avoid broad local repo/home inputs; prove Git/submodule inclusion rules using a clean source fixture.

Relocate SSH/private TLS rendering and consumer links outside worktrees before broad source adoption, via a separately reviewed secrets change. A narrow bat-only curated source may proceed independently only when exclusion is proven. Preserve encryption identities, formats, modes, host gates and recovery. Derive any non-secret target report from renderer definitions rather than creating another editable ledger. Account for Immich's machine-local key recovery.

Keep sops-nix deferred. Never supply decrypted content through `home.file.source`, `builtins.readFile`, derivation text, environment interpolation or logs.

**Exit:** synthetic secret canaries cannot enter fetched sources, store outputs or build logs; required submodule assets remain available; external secret paths and restoration dependencies are identified.

### W2 — Upgrade the observer before ownership changes

Develop and test in isolation during the current PG2 soak. Deploy observer changes after the existing soak/A7/H3 decision by default. Any earlier observer deployment requires an explicit soak-owner ruling on comparability and whether the soak restarts; passing v1 regression fixtures alone does not preserve elapsed soak credit automatically.

In `../infra/converge/converge/{schema,check,status}.py`, inventory modules, tests and `../infra/docs/manifest-schema.md`, add versioned backend metadata and generated expectation support. Exact schema is designed in this work package; preserve existing IDs, dispositions and owner values. Do not create manifest flags that grant privileged or lifecycle authority.

Ship v2-capable readers supporting v1/v2 while manifests remain v1. Confirm reachable readers before converting their manifests. Quaoar's manifest remains v1 until its updated reader is verified, or its return bootstrap must update the reader before parsing v2. Old readers still hard-fail higher versions/unknown enums. Rollback preserves a capable reader or restores a matching reader/manifest release.

Compare live targets/content to expectations from the **active** generation; show candidate/build status separately. Detect disabled adopted services and service health with explicit type-appropriate probes; do not equate existence with health. Preserve inventory coverage for Nix-installed daemons and unknown services; no blanket store-path exemption. NixOS inventory integration is required before any later NixOS pilot. Resolve parked AM4 before adopting any `/Library/LaunchAgents` resource.

**Exit:** fixtures prove generation changes, content drift, stale/failed activation, unknown unit detection, legacy behavior and strict schema failures. Structured findings, not exit 0 alone, determine green. Candidate builds cannot falsely certify active state.

### W3 — Build pinned releases without activation

Proposed files: infra `flake.nix`, `flake.lock`, `nix/hosts/`, `nix/lib/`; dotfiles `nix/home/` with explicit static assets; eventual agents modules stay in agents. Infra composes exact owning-repo revisions and aligned nixpkgs/HM/nix-darwin pins using shared nixpkgs where appropriate. Freeze initial `home.stateVersion`; updates require migration review.

Define a release receipt containing host, manifest/schema revision, source revision vector/lock identity, built output, candidate and active generation, and operation result. It is derived operational state outside worktrees. Pulling siblings may fetch newer source but cannot alter the selected release or activate moving HEADs. Activate the exact reviewed build; never rebuild against a different checkout during switch. Keep mutable out-of-store exceptions visible and outside reproducibility claims.

Specify one host-local deployment lock respected by every participating pull/deploy/activation entry, with stale-lock recovery and no nested lock deadlock. Existing bootstrap and sibling order remain intact. Automated pull must not invoke HM/nix-darwin switch; publish failures/pending activation through deploy status.

A true deploy `--dry-run` prints intended operations with **zero mutations** and invokes no Nix evaluation/build. Explicit eval/build can fetch and write declared cache/store/output locations; it is not dry-run.

Before expanded builds require free space ≥ max(10 GiB, 2 × estimated missing closure bytes + 5 GiB reserve); absent estimates block expansion pending an explicit bounded build budget. Root current and previous known-good generations regardless of age and retain other generations for 30 days; no GC before a rollback drill. Monthly reviewed lock updates, expedited security fixes, and per-platform builds replace unattended moving-input upgrades for Nix-owned scope.

**Exit:** CI evaluates pinned host configurations and builds the supported Linux/Mac outputs without production secrets, alongside native pilot and isolated platform checks; lock updates are explicit; exact-build identity, disk policy, failure status and zero-write preview are tested. Native builds for each actual platform are required before that platform's rollout.

### W4 — Implement per-target handoff and recovery

Persist the writer exclusion in the owning deploy implementation, driven by approved host/backend ownership. Do not globally remove the old writer while other hosts still need it. Cover fallback installers, cron/pull entrypoints and manual deploy as well as the obvious symlink line.

Transaction: observe → build/inspect → capture prior path and backup → fence old writer → activate exact closure → verify → retain recovery evidence. Operational progress receipts are not editable disposition ledgers.

Before fencing, the old writer remains authoritative. After fencing, interruption retains/restores the captured path and keeps the old writer fenced; recovery is explicit. Do not retry an old writer automatically after partial activation. To abandon HM ownership, restore its pre-adoption state, restore the matching ledger/backend state, then explicitly re-enable the old writer under the same lock. A rollback between two HM generations keeps the legacy writer fenced.

**Exit:** inject failure at each boundary; prove no concurrent writers, deterministic recovery, no lost hand edits, and no next-pull overwrite. Avoid blanket HM force/collision overwrites.

### W5 — One static live pilot after the split gates

Use only `configs/bat/config` → `$XDG_CONFIG_HOME/bat/config` for the ceres user. Its legacy placement is in `scripts/deploy.d/20_symlinks.zsh`. Keep package/runtime ownership unchanged. Declare the path under C1, noting generic paths are checked only when declared.

Prerequisites: W0–W4 complete, PG/soak/A7/H3 evidence current, no conflicting split domain work. First rehearse in a disposable home with required HM support files included in the reviewed footprint. HM generation/profile infrastructure is also accounted for; “one config” does not mean its activation writes only one file.

Inspect the full activation DAG. Use `systemd.user.startServices = "suggest"` where Linux unit support is included; this does not suppress arbitrary hooks. No service modules, secrets, shell entrypoints, cgroup files or runtime changes enter this pilot.

**Exit:** build → switch → content/link check → structured converge check → ordinary pull/deploy → repeat activation → generation rollback and pre-HM restoration drill. No unreviewed path change or service lifecycle event. Retain/reapply the reviewed canary generation after successful recovery proof. Observe at least seven days including normal deploy cycles before expansion.

### W6 — Reach the scoped HM endpoint

Expand one host and config family at a time: static XDG files, then editor/tmux/yazi assets, then selected CLI packages. Test native architectures before cutover. Preserve configuration semantics rather than rewriting everything into HM program options at once.

Shell migration is a separate later tranche: preserve zsh/bash startup order, bash-3.2 bootstrap, ZDOTDIR/XDG, 90–95 overrides, agents 96–99 hooks, submodule loading and cgroup cluster. Test interactive/login/noninteractive shell and service executable resolution together. Keep runtime migration out of this tranche; mise, npm globals, pinned service paths and Mac bundled CLIs require a coordinated future transfer.

Agents configuration waits for the approved agents-disposition domain. Mutable provider write-through stays writable in its owning repo/runtime directories; immutable assets alone enter Nix. When adopting HM integrated with nix-darwin later, disable the standalone HM activator for that host.

**Exit:** each reachable host's selected user scope builds, activates, rolls back and survives login/reboot and pull cycles; quaoar completes the same gates on return. Each excluded config/package has an explicit owner and reason. This milestone does not claim runtimes, macOS native state or Linux root services are Nix-reproducible.

### W7 — Add service and system declaration deliberately

First Linux user units: place via HM with suggestion mode and audited hooks; enable/start/restart remains separately authorized. On Macs, HM launchd hooks perform bootout/bootstrap: initially build/place plists through the approved adapter, or approve the entire lifecycle-bearing activation explicitly.

Then nix-darwin: canary one compatible Mac, declare selected defaults/Brew/system plists; keep Brew activation updates/upgrades off and cleanup `"none"` initially. Audit defaults reversibility and launchd domains; preserve existing manual permissions and recovery.

Keep Compose project names, container identity, network/volume names, env-file lookup, bind paths, UID/GID and deployed image digest fixed across configuration relocation. No application upgrade, volume migration, Docker-to-Podman move or database change in that cutover. Root-owned placements remain human-run.

Evaluate sops-nix separately using pinned source: its custom HM activation can restart its service on Linux or bootstrap launchd on Darwin despite suggestion mode. Preserve per-host secret eligibility, permissions, formats and credentials recovery.

If full-host Linux is chosen, write a separate NixOS plan: hardware/boot/storage/network/GPU support, deployment access, fresh storage or equivalent recovery path, data restore rehearsal, explicit downtime and host-native/NixOS inventory policy. Start in a VM; assess makemake before ceres. Nix generations do not roll back databases or other mutable data.

**Exit:** each selected later backend has its own measured canary, lifecycle policy and restore evidence. No full-fleet declarative claim until remaining system/runtime/state ownership is explicitly covered or excluded.

## Verification and readiness gates

**Unit:** v1/v2 readers and unknown enums; ID/expectation mapping; candidate vs active identity; content/enablement drift; source allowlist/synthetic secret rejection; failure transitions; notification deduplication.

**Integration:** exact locked native builds; clean Git/submodule sources; actual activation DAG; no unexpected service events; collision handling; all deploy paths honor fences/lock; dry-run filesystem snapshot unchanged; warn-not-fail and strict status behavior; missing reader/secret/input/space failures.

**End to end:** disposable fresh bootstrap with/without siblings; bat pilot and interruption recovery; generation rollback plus pre-HM restoration; ordinary pull and concurrent timer runs; Linux/Mac login/reboot; native package availability; synthetic Compose identity/restore fixture before service adoption.

**Observability:** parse findings rather than rc; stable artifact IDs; new error → one push, repeat → silence, recovery → wiki; stale/return-pending remains visible; selected/candidate/active release, failure timestamp and generation roots reported without secret content.

Readiness sequence: R1 amended scope/platform facts → R2 safe sources → R3 compatible readers/observer → R4 exact builds/preview/recovery protocol → R5 static pilot → R6 rollback, pull safety and seven-day soak → R7 per-platform HM rollout → R8 separately approved system/service scope. Original G1–G4 remain independent completion gates.

## Pre-mortem

1. **Six months later this failed because a broad input captured private render output.** Curate sources before store capture, relocate sensitive runtime destinations, test synthetic canaries, and retain external secrets authority.
2. **Six months later this failed because a pull replaced a reviewed generation or GC removed the rollback path.** Exact release receipts, host-local locking, persistent writer exclusions, rooted known-good generations, disk gates and interruption/rollback drills address this failure.
3. **Six months later this failed because a switch restarted services or was mistaken for database recovery.** Audit complete activation code, preserve C4, keep data/runtime changes separate, and require independent restore evidence for stateful services.

## Intent reconciliation

The user authorized research, planning and researcher fan-out. Their new request reopens the former Nix non-goal for planning; it does not approve a fleet migration.

The optional strategic question received no reply during this run. Home Manager first, optional Linux NixOS, later nix-darwin, the ceres bat canary, and initial mise retention are explicitly proposed choices, not recorded user consent. They leave implementation reversible and preserve the requested scope. NixOS destination, installer choice and live-host execution are gates for later execution, not blockers to delivering this plan. No approved foundation artifact is modified.

## ADR

**Decision:** staged HM with infra composing pinned releases; retain the federation and independent observer. Recommend nix-darwin after user-scope proof; leave NixOS optional.

**Drivers:** heterogeneous existing fleet, known runtime ownership incidents, permanent accounting, and safe adoption under the split.

**Alternatives:** immediate system migration; permanent HM on native OSes; manifest-only deployment. Their bounded benefits and limitations are recorded above.

**Why chosen:** delivers reusable declarative user configuration without requiring reinstalls or granting automatic lifecycle authority.

**Consequences:** hybrid operation and adapter maintenance remain real costs. Flake locks pin declared Nix inputs, not mutable mise/Brew/provider/data state. Explicit scope reporting derived from the existing ledger and a later endpoint decision prevent claiming more reproducibility than achieved.

**Follow-ups:** approve the amendment; execute W0–W4 as separate narrow work packages; preserve the September soak/H3 decision; later choose full-host Linux scope. No implementation is performed by this planning run.

## Primary technical sources

Researched against current upstream documentation/source on 2026-09-07; implementation must recheck the exact pinned release.

- [Home Manager installation modes](https://nix-community.github.io/home-manager/installation.html), [systemd options](https://nix-community.github.io/home-manager/options/home-manager/systemd.html), [launchd activation source](https://github.com/nix-community/home-manager/blob/master/modules/launchd/default.nix).
- [Home Manager rollback](https://nix-community.github.io/home-manager/usage/rollbacks.html), [file ownership/collisions](https://nix-community.github.io/home-manager/usage/dotfiles.html), [mise integration](https://nix-community.github.io/home-manager/options/home-manager/programs/mise.html).
- [Nix flakes](https://nix.dev/concepts/flakes.html) remain officially experimental; use pinned inputs and a documented installer choice. [Installation manual](https://nix.dev/manual/nix/2.34/installation/), [NixOS installer](https://github.com/NixOS/nix-installer).
- [Nix store and secrets](https://nix.dev/manual/nix/2.34/store/secrets), [sops-nix HM activation source](https://raw.githubusercontent.com/Mic92/sops-nix/master/modules/home-manager/sops.nix).
- [nix-darwin manual](https://nix-darwin.github.io/nix-darwin/manual/), [NixOS manual](https://nixos.org/manual/nixos/stable/).
- [Compose project identity](https://docs.docker.com/compose/how-tos/project-name/), [Compose volumes](https://docs.docker.com/reference/compose-file/volumes/).

## Consensus trail

Iteration 1: architect recommended observer-first sequencing; critic ITERATE. Required source/reader safety before pilot, corrected HM option, C3 coverage, release/rollback mechanics, explicit tests and endpoint boundaries.
Iteration 2: planner revised; orchestrator consolidated corrections to strict readers, correct systemd option, one-path pilot, exact release activation, rollback/GC, traceability and deferred host decisions. The initial second-pass architect was interrupted by quota. On resumption, sequential GLM-5.3 reviewers through Paseo returned **architect APPROVE** (`7f7391ad-a36b-4126-a82b-c36c12f5bcda`) and **critic APPROVE** (`b97597b5-b465-4e0d-90b3-3dcbdf09dfb3`). Architect clarifications on soak timing, evidence currency, secrets coordination and CI were incorporated before the critic reviewed the saved artifact. The critic found no blocking gaps; its count-attribution and review-record notes are incorporated here. Review consensus does not constitute owner approval to implement.
