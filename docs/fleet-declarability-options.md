# Fleet declarability: full Nix vs movable-service tooling vs the infra-repo baseline

*Theoretical exploration, September 2026. Fleet manifest as of the split-infrastructure spec: ceres (Arch/CachyOS hub), makemake (Ubuntu headless), saturn (Mac Studio), neptune (2019 iMac), quaoar (Arch laptop). Tailscale mesh + office wired LAN; secrets in a private sops/age repo rendered at deploy. Already-decided near-term plan (the baseline): an infra repo with a per-host manifest and a `converge --check` loop.*

---

## 0. Framing: the real design space is two axes, not one

Most "Nix vs Kubernetes" arguments go in circles because they argue about one axis while actually disagreeing about two. Name the axes and the space becomes navigable:

1. **Scope** — what does the system model? *Services only* (containers, ports, volumes) ↔ *host + users + services* (packages, config files, units, dotfiles, everything).
2. **Mechanism** — *converge at deploy time* (a loop reads desired state from git and pushes; nothing runs in between) ↔ *continuously scheduled runtime* (a control plane holds cluster state and places/heals workloads forever).

Placed on these axes:

| | Converge-at-deploy | Scheduled runtime |
|---|---|---|
| **Host+users+services** | Full Nix endpoint | *(doesn't exist — nothing schedules host config)* |
| **Services only** | **Your baseline**, Quadlet, Komodo/Dockge | Swarm, Nomad, k3s/k0s |

Two consequences fall out immediately:

- The **light tier** (Quadlet, Komodo, Dockge) is in the *same quadrant as your baseline* — that's why it composes with it instead of competing against it. It's not a shrunken Kubernetes; it's a better file format for the manifest you already decided to build.
- The **schedulers** trade scope for runtime intelligence. Whether that trade pays at 2.5 clusterable Linux nodes is the recurring question of Part 2.

### What's actually new since ~2022 (quick primer)

- **Nix flakes** are the de facto standard — 78.9% of the 2025 NixOS community survey uses them — yet still carry the official `experimental` flag upstream. Determinate Systems' Nix fork ships them as stable. The format itself is effectively frozen; the label is about CLI API promises, not the lockfile you'd commit today.
- **nixos-anywhere + disko**: reinstall a machine into NixOS over SSH with declarative partitioning. The "reinstall tax" that used to kill NixOS adoption conversations is now a kexec and a config file.
- **sops-nix / agenix** are the mature secrets layers; both speak age.
- **Quadlet** (podman ≥ 4.4, richer in 5.x): containers/volumes/networks/pods as systemd generator units, with `podman auto-update` + auto-rollback. `podman generate systemd` is deprecated in its favor.
- **Docker Swarm is alive**: Mirantis extended support five more years (July 2025), swarmkit is actively developed in moby, and CSI support has landed (young — homelabs still mostly pin volumes to nodes).
- **Nomad 2.0 shipped April 2026** under IBM's SC-2 lifecycle; built-in service discovery and a variables store since 1.4/1.6 mean a small fleet needs neither Consul nor Vault.
- **k3s** is at the v1.36 line (Aug 2026), bundles Traefik v3, and pairs beautifully with the **Tailscale Kubernetes operator** (ingress on `*.ts.net` with automatic TLS).
- **Komodo** (core + periphery agents) and **Dockge** (file-based, by the Uptime-Kuma author) are the new compose-manager tier; Portainer remains the multi-host incumbent.
- **macOS Tahoe (26) is the last Intel macOS**, and it drops the 2019 iMac — neptune tops out at Sequoia 15. Tahoe also introduced a Background Task Management quirk that can silently block Nix's LaunchDaemons until manually approved.

---

## Part 1 — The full Nix endpoint

### 1.1 The shape of the solution

One flake repo becomes the source of truth for every host:

```nix
# flake.nix (sketch)
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {
      ceres    = nixpkgs.lib.nixosSystem { modules = [ ./hosts/ceres.nix    ./modules/tailnet.nix ./modules/adblock.nix ]; };
      makemake = nixpkgs.lib.nixosSystem { modules = [ ./hosts/makemake.nix ./modules/tailnet.nix ./modules/telemetry.nix ]; };
    };
    darwinConfigurations = {
      saturn  = ...;  # nix-darwin + home-manager
      neptune = ...;
    };
    homeConfigurations.quaoar = ...;  # standalone home-manager on Arch
  };
}
```

- **`nixosConfigurations`** — ceres and makemake as full NixOS machines. Every system service is a module option: `services.caddy.virtualHosts`, `services.postgresql.port = 5433`, `services.valkey`, `services.clickhouse`, `services.ollama`, `services.samba`, `services.tailscale`, `services.syncthing` (with declarative folders/devices), `services.zerotierone`, `services.miniflux`, `services.adguardhome`, `services.github-runners.<name>`.
- **`darwinConfigurations`** — nix-darwin for saturn/neptune: `launchd.daemons.caddy`, `launchd.daemons.portless`, `system.defaults.*`, Homebrew either imperatively or declared via nix-homebrew. home-manager layered underneath for user-level packages/files.
- **`homeConfigurations`** — quaoar gets standalone home-manager (Nix on Arch, no NixOS).
- Deployment is push (`nixos-rebuild switch --flake .#ceres --target-host ceres`) or pull (a systemd timer running `nixos-rebuild switch --flake github:you/infra` — which is your current auto-pull timer, transplanted). Fleet deployers like **colmena** or **deploy-rs** add parallelism and profile rollback.

### 1.2 Translating this specific fleet

| What exists today | Nix translation | Friction |
|---|---|---|
| 18 Docker containers (Immich, RSS, Langfuse+SeaweedFS, webfront pg) | `virtualisation.oci-containers` (docker backend), or **compose2nix** generating that module from the existing compose files, or **arion** (run compose natively) | Low if compose2nix; you keep compose as source. Volumes must migrate from `/var/lib/docker` |
| Miniflux + its db, langfuse postgres | could *de-containerize*: first-class NixOS modules + native postgres | Medium; optional |
| ~48 systemd **user** units, each owned by its project repo | `systemd.user.services` via home-manager, or project repos become flake inputs exporting NixOS modules (preserves federation) | **High — this is the biggest cultural change.** Unit source-of-truth moves from project repo to flake (unless every project adopts flakes) |
| Caddy config, Samba, btrfs subvols + snapper | `services.caddy`, `services.samba`, **disko** declares partitions/subvolumes, snapper config in nix | Medium; the /srv/downloads subvol maps cleanly |
| GitHub Actions runners | `services.github-runners` (in nixpkgs) | Low |
| saturn/neptune launchd daemons + agents | `launchd.daemons` / `launchd.agents` in nix-darwin | Low-medium |
| neptune's colima + browserless/lightpanda | declared via brew/HM; the VM itself stays stateful | Medium; colima remains an imperative-ish pet |
| mise toolchain | keep mise (it composes fine), or replace with nix devShells | Keeping mise: zero cost. Replacing: philosophical rewrite of the toolchain story |
| sops/age secrets repo | **sops-nix consumes it nearly unchanged** | ~Zero — see below |
| paseo-daemon + the 14 scheduler crons in the platform's own store | unit can be declared; the crons **cannot** — the platform store stays out-of-band under every option | Unchanged |
| The dual-shell bootstrap (bash 3.2 floor, BSD-clean rules) | moot on NixOS (stdenv everywhere) — but **still required on the Macs and quaoar**, so you carry both layers for years | Real, sneaky cost |

### 1.3 Secrets: the strongest single synergy

This fleet already runs the exact pattern sops-nix was built for. Each host gets an age identity; the existing encrypted repo renders at deploy today and would render at **activation** tomorrow via `sops.secrets."langfuse-db".owner = "langfuse";` — files materialize in `/run/secrets` (tmpfs) before the services that need them start. No re-encryption campaign, no new trust roots, agenix unnecessary. If the Nix door ever opens, the secrets walk through it for free.

### 1.4 Rollback: what generations do and don't cover

- **NixOS**: every `nixos-rebuild switch` creates a boot entry; `nixos-rebuild switch --rollback` (or picking the previous generation in the boot menu) restores the *entire system closure* atomically. This is the gold standard — nothing else in this document has it.
- **nix-darwin**: `darwin-rebuild --rollback` exists, but there's no boot-menu safety net and activation is less atomic.
- **The trap**: generations roll back *configuration*, not *state*. Immich's postgres schema migration, ClickHouse parts, Syncthing indexes, and the AdGuard config written by its web UI do not rewind. The rule you'd live by: roll back config freely, never roll back across an application migration without a data snapshot — same discipline as today, just easier to forget because config rollback feels so complete.

### 1.5 Migration cost, host by host

- **ceres (CachyOS → NixOS)**: a reinstall, full stop (nixos-infect-style in-place conversion exists and is rightly feared on production). The modern path: write the full config, test with `nixos-rebuild build-vm`, then `nixos-anywhere` onto fresh storage while the old root sits on the shelf as the rollback plan, then migrate `/var/lib/docker` volumes and `/srv` subvolumes, then repoint tailnet DNS. You lose CachyOS's optimized repos/kernels (irrelevant for a server) and gain reproducibility. **Estimate: 2–6 careful weekends**, mostly spent on the 48 user units and 18 containers' volume/env fidelity.
- **makemake (Ubuntu → NixOS)**: the easiest Linux conversion — Docker + runner + 3 crons + ML worker. Also the least urgent, which makes it the ideal **toe-dip host** (see Part 3).
- **saturn/neptune (→ nix-darwin)**: no reinstall — nix-darwin layers onto macOS. You'd convert the launchd farm gradually; existing daemons keep running while you port them. Gaps that never close: OS updates stay Software Update/imperative, TCC permission prompts are inherently manual, GUI app settings are only as declarative as `defaults` allows (your own macos-scripts experience already knows this), and Homebrew is imperative unless you adopt nix-homebrew (workable, extra machinery). **neptune-specific**: capped at Sequoia 15, Tahoe dropped the 2019 iMac, and Nix 25.11 already began shedding older macOS support — expect slow ecosystem bitrot on that box regardless of approach. And the annual ritual is real: every fall's macOS release arrives *before* nixpkgs/nix-darwin fully catch up (Tahoe's BTM silently blocked Nix LaunchDaemons until approved; the daemon crash in Tahoe betas was fixed in later Nix).
- **quaoar (Arch + home-manager)**: standalone HM is possible but **duplicates the dotfiles repo's job**. This repo *is* a battle-tested, CI-gated, dual-shell deployment system; HM would claim the same files. You'd retire one of them. Running both = two owners per file = the drift you built the whole apparatus to avoid.

**Coexistence rule if you go partial** (Nix on some hosts only): every file gets exactly one owner. Nix store paths, brew prefixes, pacman, and mise shims coexist fine technically — the failure mode is *organizational*, "who owns `/etc/caddy` on which host," and it's answered by the manifest discipline you already have.

### 1.6 Failure modes people actually hit

1. **Eval-time breakage on input bumps** — a nixpkgs bump rebuilds half the host and occasionally breaks eval (the infamous "infinite recursion encountered" module errors). Mitigate: stable release channels + shared lockfile; but expect a day of fixing per major bump.
2. **The learning curve never fully ends for new operators** — and on this fleet the primary operators are *agents*. Nix error messages have improved but remain the least agent-friendly surface in this comparison; every future session pays a fluency tax the baseline doesn't charge.
3. **Garbage-collection footguns** — `nix-collect-garbage -d` happily deletes the rollback points you wanted; no GC at all fills the disk. Needs a policy from day one.
4. **Config-vs-state divergence** (§1.4).
5. **Packaging long tail** — paseo-daemon and friends need wrapping (`autoPatchelfHook`) or stay imperative; Immich ML offload on saturn is a launchd port either way.
6. **macOS upgrade timing** (§1.5 saturn/neptune).
7. **Supply chain** — flake inputs are trust decisions; CVE-2024-27297 (`nix-shell` env-var exfiltration) was a wakeup call. Pin inputs, run `nix flake check` in CI, decide your substituter trust explicitly.
8. **Two documentation worlds** — wiki vs manual vs flakes docs, with flakes still officially experimental (Determinate's fork exists precisely because of this).

### 1.7 What it buys vs the baseline

Honest ledger. **Buys**: drift eliminated *by construction* (the converge loop becomes unnecessary rather than better); atomic whole-system rollback; one reviewable language for hosts+users+services; dev shells; direct reuse of the sops repo. **Doesn't buy**: state rollback; macOS OS-level coverage; anything for the platform-store crons; *runtime placement* — a service still lives on the host whose config declares it, moved by editing configs and rebuilding (config mobility, not scheduling). **Costs**: two reinstalls, two darwin conversions, a flake rewrite of ~48 units + 18 containers, permanent dual systems during transition (dotfiles repo for Macs/laptop, flake for Linux), and the steepest learning curve in the field.

---

## Part 2 — Movable-service tooling

### 2.1 Three sub-tiers people lump together

1. **Push-to-host managers** (Komodo, Dockge, Portainer): a UI (plus optional git sync) that runs `docker compose up` on remote hosts via agents. No scheduler, no cluster state.
2. **Unit generation** (Quadlet): containers as systemd generator units on a single host. No scheduler either — placement is "which host's filesystem has the file."
3. **True schedulers** (Swarm, Nomad, k3s/k0s): define a service once; a control plane with **consensus state** (Raft/etcd) places it, restarts it across node failure, and owns its lifecycle forever.

The tiers behave so differently that the growth scenario below is run per-tool.

### 2.2 The schedulers

**Docker Swarm** — embedded in `dockerd` (swarmkit); `docker stack deploy -c compose.yml` using the compose v3 files *you already have*. Placement constraints, rolling updates, an L4 routing mesh with VIP-based DNS, built-in secrets/configs (file-based, raft-encrypted, no sidecar). CSI support has landed and is still maturing — the homelab norm remains local volumes + pinning. Single-manager is fine at this scale (raft state under `/var/lib/docker/swarm`). **Status**: quietly resurgent — Mirantis extended support five years in mid-2025 and swarmkit sees active development; it is *maintained*, not *frontier*. **Ops weight**: lowest of the three schedulers; engine upgrades are drain-and-roll per node.

**Nomad** — single Go binary; servers + clients; jobs in HCL. Since 1.4 it has built-in service discovery and a variables store, so the historic "you also need Consul+Vault" tax is gone at small scale. **Host volumes** are declared per-client — storage gravity is *explicit*: a job names a volume that exists on specific nodes, so "moving" a service visibly requires moving the volume too. `system` jobs (DaemonSet analog) are the natural shape for node-local DNS. **Status**: alive and well — Nomad 2.0 shipped April 2026 under IBM's SC-2 lifecycle (1.10 was the last old-model LTS; Spring/Fall feature releases continue). **Ops weight**: medium-low; one server binary, drain-and-swap upgrades, ACL to enable.

**k3s (and k0s)** — certified Kubernetes in one binary; embedded SQLite datastore by default (etcd optional); Traefik v3 bundled; local-path provisioner for storage. The YAML surface is the full k8s API plus Helm charts; Flux/ArgoCD are the gitops layer if you want the baseline's pull model inside the cluster. **Where it shines**: the **Tailscale Kubernetes operator** — an ingress on `https://adguard.<tailnet>.ts.net` with automatic TLS, cluster egress through the tailnet — is the best Tailscale story of any option here. **Where it taxes**: day-2 is chart churn, API deprecations, and the storage decision — PVCs on local-path are node-pinned, and the fixes (Longhorn, Rook) want **≥3 nodes** for quorum. You have ~2.5 clusterable Linux nodes. Current line: v1.36 (Aug 2026). k0s is a peer alternative (Mirantis, airgap-friendly); same weight class, same caveats.

### 2.3 The light tier

**Quadlet** — podman ≥ 4.4 (5.x adds `.build`/`.image`). You write `adblock.container` in `/etc/containers/systemd/` (or **`~/.config/containers/systemd/user/` — note that path: it is structurally identical to your existing `~/.config/systemd/user` symlink convention**). A systemd generator turns it into a real unit: journald logging, `Requires=`/`After=` dependencies, timers, `podman auto-update` via the `io.containers.autoupdate=registry` label plus the bundled timer, with auto-rollback on failed update. Rootless by default. There's even a `.kube` unit for running k8s-style YAML under podman. **Caveat**: it's podman, not docker — existing compose stacks either stay on docker (two container runtimes on ceres) or translate.

**Komodo** — core (UI + DB) + **periphery** agents on every Docker/Podman host. Stacks, builds, and deployments defined as resources **synced from git** — manual UI edits get reverted on sync, which is a genuine drift story. Multi-server view, automations, alerts, browser terminals. The closest thing to "movable services" without a scheduler: reassign a stack's target server in the resource. The control plane is a UI+database you must run, patch, and back up — but it is *not* a consensus system.

**Dockge / Portainer** — Dockge (Uptime-Kuma's author) is the minimalist: it reads and writes `compose.yaml` directories directly on disk — no database hiding your config — so it stays fully compatible with a converge loop and git ownership. Multi-host is link-out-to-other-instances, not centralized. Portainer is the incumbent: DB-backed, agent-based multi-host, RBAC, templates, git-backed stacks; heavier, and the free/BE licensing line keeps moving. Pick at most one of the three UIs.

### 2.4 Cross-cutting realities

**Storage gravity.** Postgres does not float. The fleet's actual weight is its state: three postgres instances (Immich, langfuse on :5433, webfront), ClickHouse, SeaweedFS, Syncthing trees, the `/srv/downloads` btrfs subvol. Options, worst to best: (a) shared storage — NFS from ceres reintroduces ceres-gravity, you renamed the dependency instead of moving it; (b) replication — CNPG operator (k8s) or PG streaming, real complexity for 1–2 replicas across 2 nodes, no quorum; (c) **pin the stateful services and only move stateless ones** — what homelabs actually do, and it's most of the mobility value anyway: ad-block DNS, rss-bridge, digest-web, portkey are genuinely floatable; Immich is not.

**The Mac exclusion.** No kubelet on macOS; Swarm and Nomad have theoretical macOS stories nobody runs. saturn's Immich ML offload and neptune's browserless/socat bridges **cannot join any scheduler** — they stay launchd/colima forever. Structural fact: every scheduler in Part 2 covers ceres+makemake (plus quaoar when awake, which makes it a bad cluster member — sleeping laptops and Raft don't mix). The baseline manifest is the only model in this document that treats saturn/neptune services as first-class entries; full Nix is the only one that *configures* them declaratively (without mobility). Komodo/Dockge can *reach* a colima docker socket on a Mac, but through a VM layer — second-class.

**Tailscale.** For ad-block DNS the tailnet matters more than the scheduler: Tailscale's admin console DNS (global nameserver + "override local DNS") must point at wherever the resolver lives, so **moving the resolver = an admin-console edit + a config/data move** under every option. Beyond that: `tailscale serve` for per-node TLS'd exposure on any approach; the k8s operator for cluster ingress (§2.2). Office wired LAN is orthogonal — the resolver should answer on both the 10.77.0.x wired IP and the tailnet IP. Ubuntu detail: makemake's systemd-resolved stub listener squats on :53 and must be disabled before any DNS server lands there.

**The 2.5-node problem.** A cluster of ceres+makemake(+sometimes-quaoar) cannot give you HA (control-plane quorum wants 3; data replication wants 3 for anything Longhorn-class). What a scheduler buys at this size is *placement convenience and uniform YAML*, not resilience. Weigh that against introducing a distributed system whose own state you must upgrade, back up (etcd/raft snapshots), and secure — a new pet, on a fleet whose current pets are already hand-tamed.

### 2.5 The growth scenario: ad-block DNS, concretely

Pick the tool first (Blocky if you want config-file-only and stateless-declarative; AdGuard Home if you want the web UI, accepting that its wizard writes state; Pi-hole if you enjoy sqlite archaeology — most people shouldn't). Then:

- **Baseline**: add a manifest entry for the chosen host (one unit or compose file), open :53, point the tailnet console at ceres's tailnet IP. *~30–60 min, zero new concepts.*
- **+Quadlet**: same, but the manifest entry is a single `blocky.container` file — the cleanest version of the baseline answer.
- **Komodo/Dockge**: add a stack resource in git (Komodo syncs it out) or paste compose in the UI. AdGuard's wizard-state lives outside git; Blocky's config doesn't.
- **Swarm**: add a service to a stack file with a placement constraint and a local volume; `docker stack deploy`. DNS on the routing mesh is L4 — fine for :53/tcp+udp.
- **Nomad**: a job HCL with a constraint (or a **`system` job**: Blocky on *every* Linux node, node-local DNS, no tailnet single-point — the one architecture here that genuinely improves on "pinned to ceres").
- **k3s**: a Deployment/Service or Helm chart, hostPath/local-path PVC, Traefik or the Tailscale operator for exposure. Most YAML for the same result; best if you *also* want the operator's ts.net ingress pattern for everything else.
- **Full Nix**: move the `services.adguardhome.enable = true;` block (or Blocky module + config file) into the target host's config; `nixos-rebuild switch`. The *definition* is identical on any host — config-mobility rather than runtime-mobility, but for a 5-box fleet that distinction is mostly academic.

### 2.6 The hypothesis, adjudicated

*"This class is more constrained than Nix yet more heavyweight."* **True for the scheduler tier, with two refinements:**

1. The heaviness isn't the control plane binary — it's **consensus state that must itself be operated**: upgraded, snapshotted, restored, secured. Nix's "control plane" is git + nix at deploy time: stateless evaluation, per-host store, nothing running between deploys. That asymmetry is the real cost line.
2. The dichotomy breaks at the **light tier**: Quadlet/Komodo/Dockge are *narrower AND lighter* than Nix — no host config, no new language, no consensus. They live in the baseline's quadrant (§0), which is why the coherent move is adopting *them*, not graduating from them.

Also true and worth saying plainly: Nix *covers* services (modules, oci-containers), so schedulers are a strict subset by scope; their only unique capability is runtime placement/healing — which, at 2.5 Linux nodes with data gravity and Macs excluded, mostly buys YAML.

---

## Part 3 — The comparison

### 3.1 Matrix

**Operations and adoption**

| Approach | Adoption effort | Day-2 weight | Drift detection | Rollback |
|---|---|---|---|---|
| **Baseline** (infra repo + converge) | days–weeks (already decided) | low — git, ssh, a timer | built-in (`--check`) | git revert + re-converge; coarse-grained |
| **+ Quadlet** | +days | low — systemd you already run | same converge, over unit files | file revert + restart; auto-update rollback |
| **+ Komodo/Dockge** | a weekend | low-med — one more web service to run | Komodo: git-sync reverts edits; Dockge: files on disk, converge still applies | redeploy previous stack def only |
| **Swarm** | weekend + stack migration week | medium — engine upgrades, raft backups | `stack deploy` is converge; manual `docker` cmds drift | `docker service rollback`; old stack file |
| **Nomad** | 1–2 weeks to comfort | medium — server upgrades, job sprawl | git-owned HCL; `nomad job plan` dry-run | re-run previous HCL; auto-revert on failed deploy |
| **k3s** | 2–4 weeks + storage decision | **high** — charts, API deprecations, snapshots | git-owned manifests (+ Flux/Argo) | `rollout undo`; Velero for full restores |
| **Full Nix** | 1–3 months of weekends, fleet-wide | medium — nixpkgs bumps, locks, GC policy | **structural** — drift is nearly impossible in config | **gold standard** — boot generations, `--rollback` |

**Capability**

| Approach | Service mobility | OS coverage | Secrets | Ad-block DNS next week |
|---|---|---|---|---|
| **Baseline** | manual — move unit+data, edit manifest | **all 5 hosts uniformly** (incl. Mac launchd) | sops/age at deploy (current) | ~30–60 min |
| **+ Quadlet** | same, one `.container` file | Linux hosts; Macs stay launchd/docker | systemd `LoadCredential` or sops-rendered envs | one file; cleanest answer |
| **Komodo/Dockge** | UI reassign / copy stack | Docker endpoints; Macs only via colima (2nd-class) | Komodo secrets / env files | stack in git or UI; AdGuard state caveat |
| **Swarm** | constraint flip + volume move | Linux; Macs excluded | swarm secrets (raft-encrypted files) | stack service + constraint |
| **Nomad** | constraint/datacenter flip + host volume | Linux; Macs excluded | vars store / sops-rendered templates | job HCL; `system` job = per-node variant |
| **k3s** | nodeSelector flip; PVC blocks unless solved | Linux; Macs excluded | k8s secrets + SOPS/ExternalSecrets | manifest/chart; Tailscale operator ingress is genuinely nice |
| **Full Nix** | move module between host configs | all 5 (neptune capped at Sequoia; watch bitrot) | **sops-nix reuses the existing repo as-is** | move module + rebuild |

### 3.2 Coherent combinations vs redundant ones

**Coherent:**
- **Baseline + Quadlet** — same manifest, same converge loop, same systemd semantics, rootless containers, auto-update. The natural evolution; nothing new to operate.
- **Baseline + Komodo** (or Dockge) — git remains source of truth; you gain a fleet-wide UI and stack reassignment for the container tier only.
- **Baseline + Swarm** — if placement churn between ceres/makemake becomes a real weekly pain and you want compose-native scheduling with the least ceremony. Just accept pinned volumes.
- **Full Nix** — replaces the baseline *wholesale* (the converge loop is subsumed by rebuild). Strongest if a ceres rebuild is coming anyway; secrets migrate free via sops-nix.
- **makemake → NixOS as a toe-dip, baseline elsewhere** — the cheapest real experiment: least-loved host, `nixos-anywhere` redeploy, learn whether Nix fits your operating style before touching ceres. Fully reversible at fleet scale.
- **home-manager on Macs only, no nix-darwin** — technically fine, organizationally weak: it duplicates the dotfiles repo's exact job. Only worth it if that repo is ever retired.

**Redundant or contradictory:**
- **Full Nix + k3s at this size** — two full declarative systems for 2 nodes. (NixOS *hosting* k3s is legitimate at real scale; here it's belt-and-suspenders with twice the upgrade surface.)
- **Swarm + Nomad together**; **Portainer + Dockge + Komodo together** (pick one UI).
- **converge loop + Nix** — the loop's whole job disappears; keep one.
- **Longhorn/CSI replication on 2 Linux nodes** — no quorum; fake HA is worse than honest pinning.
- Under *every* option: the paseo scheduler crons and (realistically) the GH runners stay per-host out-of-band. Nothing here manages the platform store.

### 3.3 Recommendation (optional, as flagged)

The baseline you already chose is the right spine for this fleet — it's the only approach that uniformly covers all five hosts, and its `--check` loop already answers the drift question. Layer, in order of fit: **Quadlet for new Linux container services** (or keep compose + Komodo if you want the UI), **pin stateful services to ceres regardless of approach**, and treat the sops repo as unchanged — it's forward-compatible with sops-nix, which keeps the Nix door cheap. Use **makemake as the NixOS experiment slot** if curiosity demands a real answer rather than a paper one. Revisit schedulers only if the Linux node count reaches 3+ or service placement churn becomes a weekly irritant; at 2.5 nodes they cost more than they move.

---

## Sources

- [Why are flakes still experimental? — NixOS Discourse](https://discourse.nixos.org/t/why-are-flakes-still-experimental/29317)
- [Flakes in the 2025 NixOS Community Survey — NixOS Discourse](https://discourse.nixos.org/t/discussion-of-flakes-from-2025-nixos-community-survey-report/78853)
- [Experimental does not mean unstable — Determinate Systems](https://determinate.systems/blog/experimental-does-not-mean-unstable/)
- [macOS Tahoe 26 compatible computers — Apple Support](https://support.apple.com/en-us/122867)
- [macOS Tahoe BTM blocks Nix LaunchDaemons — mgaebler.me](https://mgaebler.me/en/blog/nix-macos-tahoe-btm-blocks-launchdaemons/)
- [Support for older macOS versions — NixOS Discourse](https://discourse.nixos.org/t/support-for-older-macos-versions/72931)
- [Nomad release notes (2.0, SC-2 model) — HashiCorp](https://developer.hashicorp.com/nomad/docs/release-notes)
- [Docker roadmap: Swarm mode status — GitHub](https://github.com/docker/roadmap/issues/175)
- [Docker Swarm CSI — forestier.re](https://forestier.re/en/posts/2024-12-23-docker-swarm-csi/)
- [k3s releases — GitHub](https://github.com/k3s-io/k3s/releases)
- [Komodo — komo.do](https://komo.do/)
- [podman-systemd.unit(5) — Quadlet reference](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Make systemd better for Podman with Quadlet — Red Hat](https://www.redhat.com/en/blog/quadlet-podman)
- [Portainer vs Dockge — talos.tools](https://talos.tools/compare/portainer-vs-dockge)
- [Why I switched from Portainer to Dockge — BigMike](https://bigmike.help/en/posts/dockge-why-i-switched-from-portainer-to-this-lightweight-tool-and-recomme-2f9da9/)
