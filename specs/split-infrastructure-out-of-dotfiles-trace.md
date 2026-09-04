# Trace: split-infrastructure-out-of-dotfiles

Deep-dive trace, 2026-09-04. Three parallel evidence lanes (repo inventory /
live-fleet inventory / premise audit) plus two orchestrator probes. All claims
below carry citations from the lane reports; strength tiers follow the trace
discipline (1 = uniquely discriminating artifact … 6 = speculation).

## Observed Result

The dotfiles repo has expanded beyond config/settings files into handling
infrastructure. Secrets were already moved out into their own repo; now
infrastructure should be split out too — possibly with the "agents" stuff and
associated wiring as a third repo, since it goes on all working machines while
individual services belong on one box. Cited pain: churn in dotfiles for
things that only belong on ceres, and agent skill updates that are partly the
user's and partly worked-around provider configs. Desired end-state: dotfiles
gives quality-of-life setup like a normal dotfiles repo, and the fleet
possibly moves from per-machine manual deploy configs to a structured dynamic
system.

## Ranked Hypotheses

| Rank | Hypothesis | Confidence | Evidence Strength | Why it leads |
|---|---|---|---|---|
| 1 | **Composite (converged)**: the felt problem decomposes into four distinct mechanisms — (i) a small, clean, movable one-box infra set inside dotfiles; (ii) a large agents tree whose real pain is provenance mixing, not location; (iii) a fleet-level ownership gap of ~45 live artifacts owned by *no* repo; (iv) a federated deploy substrate with no reconciliation loop. Only (i) is what the original framing describes. | High | Tiers 1–2 across all three lanes | Every lane's strongest evidence survives the rebuttal round and slots into this decomposition without contradiction |
| 2 | Lane 1 (refined): the in-repo infra layer is enumerable and cleanly separable via the existing `configs/<svc>/ + scripts/setup-<svc>.sh + docs/<svc>.md` triple convention; the agents layer is separable but must first be *constructed* (three service leaks inside `configs/ai/`, 4 in-file seam cuts, one genuinely entangled cgroup cluster) | High | Tier 1–2 (written carve-out spec `AGENTS.md:134-149`; zero deploy coupling of service scripts; export-surface audit) | Directly confirmed by disconfirmation tests; refined, not overturned, by rivals |
| 3 | Lane 2 (refined): dotfiles is deliberately one of six unit-owning repos (~14% of live units trace to it); the real gap is the unowned bucket (`~/repos/deploy`, portless/t3code/github-runner units, 14 OpenClaw crons, macOS glue, all of makemake) plus tracking≠health drift | High | Tier 1–2 (live inventory of 4 hosts; `setup-immich.sh:219` convention comment; broken/failing tracked units) | Core findings uncontested; "seventh owner" framing softened by rebuttal (see below) |
| 4 | Lane 3 (measurements): ceres-churn premise false (1.8% of commits); agent-churn premise true but partly construction-phase (27.5%/12mo, ~40% of touches in five structural commits); submodule bumps are the unstated #1 (41.3%/12mo); provider entanglement real but split-orthogonal; secrets split ~80% done | High | Tier 1–2 (direct git measurement, three windows) | Numbers unchallenged; only the *implications* were re-weighted in rebuttal |
| 5 | Original naive framing: "split infra out of dotfiles to get ceres churn out" | Down-ranked | Contradicted (tier 1) | Ceres-only infra is 17/955 commits and 0.2% of file-touches — statistically invisible; and a bare relocation adds an owner without closing the actual gap |

## Evidence Summary by Hypothesis

### Lane 1 — repo inventory & separability (confirmed, refined)

**For:**
- **The repo contains its own carve-out spec** (tier 1): `AGENTS.md:134-149` "## TODO: infra carve-out" — "Cameron's intent (2026-09-03) is to split infra out of dotfiles into its own repo, leaving this one to config *preferences*… keep new infra to the `configs/<service>/` + `scripts/setup-<service>.sh` + `docs/<service>.md` triple so the eventual move is a `git mv`, not a rewrite." Copies at `docs/immich.md:119-152`, `README.md:190-208`. Introduced in `a8f5645f`.
- **Zero deploy coupling of service scripts** (tier 2): no deploy fragment invokes any `setup-*.sh` (`rg` over `scripts/deploy.d/`, both drivers, `post-merge` — comment-only hits at `75_brew_setup.zsh:377,397`). Confirmed as policy at `README.md:202-204` ("hand-run, never wired into scripts/deploy.d/").
- **Disconfirmation test passes** (tier 2): no infra or agents fragment exports state consumed by a QoL fragment — only `50_mise.zsh` and `70_runtime_installs.zsh` export anything (PATH), and all shared variables are set by `deploy.zsh:56-133` / `lib/helpers.zsh:152-158`, never by peer fragments. The 40 cross-fragment name references are all comment-level idiom citations.
- **Host gating is 3 pin-points, not diffusion** (tier 2): `20_symlinks.zsh:134` (only hardcoded hostname in any fragment), `11_portkey.zsh:18`, and the `_gate_open()` table in `secrets-render.zsh:267-273`. Everything else gates on `$DOTFILES_OS`.
- **`lib/helpers.zsh` is layer-agnostic** (tier 2): 270 lines of `have`/`deploy_ln`/brew helpers, zero service/host/agent knowledge — vendorable unchanged.
- **79.9% of 12-month commits are single-layer** (tier 2, 895 commits classified): QoL 63.0%, AGENTS-pure 10.1%, INFRA-pure 1.7%.
- Inventory (tier 2): 9 clean service triples (immich, caddy, samba/ceres-share, office-lan, t3, openclaw-mcp, portless, eris-bootstrap, tailscale-runbook); `configs/ai/` = 316 tracked files / 2.2 MB; agents shell fragments = 1126 lines ≈ 41% of the 2741-line interactive shell layer (49% with the cgroup cluster).

**Against / refinements:**
- The written spec is **two-way, not three-way** (tier 1): `docs/immich.md:137-141` lists infra candidates; `configs/ai/` appears nowhere, and paseo (an agent orchestrator) is classified as *infra*. The three-way split is a new proposal, not latent structure.
- `configs/ai/` **contains three one-box services** (tier 2): `portkey-gateway.service` (symlinked unconditionally at `20_symlinks.zsh:126`, planted even on Macs), `litellm-proxy.service` + 32 KB wrapper (unreferenced by any fragment), `ccr-router.service` (unreferenced; names `ceres.webfront.app`). Infra and agents are not disjoint sets today.
- **Two fragments need in-file seam cuts** (tier 2): `20_symlinks.zsh` (~57 agents lines of 174; contiguous block `:72-126`), `70_runtime_installs.zsh` (55 agent mentions interleaved with QoL installs); plus `10_dirs.zsh:11-12` and `60_git_hooks.zsh:13-23`.
- **One cluster genuinely resists** (tier 2): `zsh/rc.d/00b_agents_slice.zsh` (execs the shell through `systemd-run --slice=agents.slice`), `04c_worktree_scope.zsh`, `env.d/06_resmon.zsh`, `bin/install-agents-slice.sh` — cgroup *memory* infrastructure load-order-coupled to the shell hot path. Naming trap: `agents.slice` is a cgroup slice, not the AI-agents layer; keyword-based splitting would mis-file it. It stays in dotfiles.
- `configs/ai/` is **absent from the repo's own Structure map** (`AGENTS.md:99-131`) and has been relocated at least once already (stale `configs/litellm/__pycache__`, 4 files still under old `configs/<tool>` paths) — an accreted layer, not a designed one.

### Lane 2 — live-fleet inventory (confirmed, redirected)

**For:**
- **The federation is documented policy** (tier 1): `scripts/setup-immich.sh:219` — "systemd convention on ceres is 'unit and script live in their owning repo'"; `~/.config/systemd/user/` on ceres is a symlink farm: 34 of 48 unit files are symlinks into libris (12), hart (9), telemetry (7), photo-steward (3) — **and dotfiles (2)**. Only ~17 of ~120 fleet-specific artifacts (~14%) trace to dotfiles; ~46% to other named repos; **~38% (~45 artifacts) to nothing**.
- **`~/repos/deploy` is not a git repo and live timers execute from it** (tier 1): `hart-immich-backup.service` ExecStart → `%h/repos/deploy/immich/bin/immich-backup.sh`; `rss-digest.service` → `~/repos/deploy/rss/digest/digest.py`. Six service trees (immich, libris, rss, 3× webfront) under no version control. Corroborated by hart wiki `active-projects-register.md:80,93`.
- **makemake is invisible to both claimed sources of truth** (tier 1): the hart register scopes itself to ceres/saturn/neptune (`:3,28`); dotfiles mentions makemake 3 times. Live it runs `github-runner-webfront.service`, `t3code.service`, 3 telemetry crons, and an `immich_ml` container the wiki attributes solely to saturn.
- **Tracking ≠ health** (tier 1–2): `litellm-proxy.service` enabled + load-state `bad` + inactive on makemake; `dotfiles.pull` failing on saturn (status 128) and neptune (status 1); `local.paseo-daemon` status 1 on both Macs; `ccr-router.service` and 8 hart openclaw units tracked but deployed nowhere; inert systemd units sitting on the two systemd-less Macs at two *different* dotfiles paths; `neptune-swap-watchdog` plist executing `saturn-swap-watchdog.sh` (neither in any repo).
- **Unowned clusters** (tier 2): (1) `~/repos/deploy`; (2) portless / t3code / github-runner hand-made units on 2–3 hosts each — dotfiles tracks portless *certs* and generates `t3-serve` but not these units (partial coverage, worse than none); (3) makemake wholesale; (4) 14 OpenClaw crons in OpenClaw's state store, one failing 6×; (5) macOS glue (omc-browser socat bridges ×4 + 2 containers, `actions.runner…webfront-js`, `com.webfront.reap` plist, swap watchdogs).

**Against / refinements:**
- The repo's infra surface **is** sharply enumerable (6 tracked unit files, 7 installers, 27 fragments) — not unbounded sprawl.
- The hart wiki register (verified 2026-09-03) had already found nearly all project-level gaps on the three hosts it covers; lane 2's marginal contribution is the unit-level untracked set and makemake.
- The most recent infra data point is dotfiles *successfully* absorbing immich with an idempotent installer + `--check` reconciliation (`a8f5645f`) — the repo is not failing at infra; it is doing it well, in an interim home.

### Lane 3 — premise audit (measurements confirmed)

**Churn by bucket, file-touches** (tier 2; disjoint classifier over `git log --name-only`):

| Bucket | 12mo (n=6,959) | 3mo | 1mo | All-time |
|---|---|---|---|---|
| Submodule bumps | **41.3%** | 15.6% | 12.7% | **69.4%** |
| Agent configs | **27.5%** | **35.4%** | **30.3%** | 5.3% |
| QoL dotfiles | 12.2% | 5.8% | 7.5% | 14.5% |
| Secrets plumbing | 4.5% | 5.0% | 7.8% | 0.9% |
| deploy.d | 3.6% | 15.1% | 19.2% | 0.7% |
| **Ceres-only service scripts/configs** | **0.2%** | 0.4% | 0.3% | 0.0% |

Commits, 12mo (n=955): QoL 44.2%; agent area 18.3%; **ceres-only infra 1.8% (17 commits)**.

- **Premise "churn from ceres-only things" falls** (tier 1): smallest bucket in every window.
- **Premise "agent skill churn" holds with a decay caveat** (tier 2): largest non-submodule bucket, #1 in the last month — but the subsystem is ~5 months old (`9c247b03`, 2026-04-08) and ~800 of 1,911 touches sit in five structural reorg/vendor commits. Part construction churn, part steady-state.
- **Boundary criterion leaks** (tier 1): Portkey is definitionally both sides — fleet-wide alias substrate (`11_portkey.zsh:3,7`, `agent-aliases.zsh:11`) *and* a ceres-only systemd service (`11_portkey.zsh:19-21`, `portkey-gateway.service`). Also two-homed: `.default-npm-packages` (agent CLIs + QoL tools + editor LSP + 20 lines of ceres incident history referencing `~/repos/hart`), `configs/mise.toml` (node pinned for "interactive shells and systemd units alike", sops/age, QoL tools, webfront absolute path), 12 agent-woven zsh fragments, paseo (daemon per box, config all boxes, per-host binaries), `secrets-render.zsh:185` gate column already encoding `all|ceres|immich|libris`.
- **Secrets precedent: mechanism landed, cleanup parked** (tier 1): cutover `1923532a` (2026-08-25); ten days later 21 `.enc` files still tracked, `.sops.yaml` still at root, `save/restore-secrets.zsh` still in top-25 churn, `deploy.zsh:58-59,89` still documents the deleted `65_sops.zsh` semantics, Phase 5 gated and uncleared, quaoar unverified. **Residue pattern of split #1 predicts residue of splits #2/#3, which have more inbound edges.**
- **Provider entanglement is the strongest-supported premise** (tier 1): `scripts/enforce-codex-defaults.zsh` is a checked-in pre-commit script existing solely to fight the Codex CLI writing into tracked config; `configs/ai/codex/config.toml` interleaves user policy with provider migration notices and a NUX impression counter; provider-written trust-state oscillated in/out across four commits; `config.toml` is the #1 non-submodule churn file (45 touches/12mo). **A repo split does not fix this — the vendor writes to the same path regardless of remote.**
- **The unstated #1 churn source** (tier 1): submodule pointer bumps — already being fixed by the proven vendor/mise migration (`75002f84`), no split required.

### Orchestrator probes (run after the lane reports)

- **Probe A — path binding of the agents layer** (tier 1): `rg` for `\.local/dotfiles|$DOTFILES|DOTFILES_DIR` across `configs/ai/`, `bin/`, `agent-aliases.zsh` → **12 files total**, mostly docs/reference; the notable executable hits are `cc-worker.sh` (hardcodes `$HOME/.local/dotfiles/scripts/agent-aliases.zsh`), `bin/disable-agents-slice-hook`, and the portkey/ccr service+config files. The agents tree is essentially path-independent; a move costs ~a dozen path fixes, not a design phase. **Lane 1's critical unknown: collapsed (favorable).**
- **Probe B — skill provenance** (tier 2): introducing-commit subjects for the ~92 skill dirs: ~35 = "chore(ai): vendor the Matt Pocock skill bundle", 11 = codewhale (provider-shipped), 6×3 = paseo skills ("track the six paseo skills across all three agent trees"), 3 = "vendor deep-dive/deep-interview/ralplan", plus hart-shaping vendor. Clearly user-authored: roughly 10–15 (agent-orchestration, gjc-orchestration, skill-recall, context-audit/generate, repo-research, ultragoal-prep…). **Vendored/provider content dominates by count (~75–85%); per-skill post-intro churn is 1–4 commits. Lane 3's critical unknown: collapsed — "stop tracking other people's files" is a live remedy for most of the tree.**

## Rebuttal Round

**Lane 2's "seventh owner" objection vs lane 1's carve-out spec — resolved in
favor of a merged reading.** Lane 2's strongest challenge to the split: the
fleet already federates units into owning repos, so an infra repo adds an
owner without consolidating anything. Lane 1 answered with a tier-1 artifact:
`docs/immich.md:143-147` explicitly places the *unowned* bucket in scope for
the future infra repo ("Also unversioned and in scope for that repo when it
exists: `~/repos/deploy/rss` … and `neptune:~/omc-browser`"). So the planned
repo is not a competitor to hart/libris/telemetry — it is the missing
owner-of-record for the ~38% that has none. Lane 2's critical unknown (is
`~/repos/deploy` destined for versioning or ephemeral?) is substantially
answered by the same citation: destined, when the repo exists. The rebuttal
lands both ways: lane 2's framing softens, and lane 1's scope widens — the
infra repo's real charter is dotfiles' 9 triples **plus** the unowned bucket.

**Lane 3's churn inversion vs the user's felt experience — both stand.** Lane
3's own window analysis (agent bucket rising to 30.3% in the last month, #1
bucket) confirms the user's *recent* perception even though the 12-month and
all-time pictures differ. And lane 1 supplies the justification the churn
numbers can't: `docs/immich.md:125-126` argues blast-radius, not churn — every
dotfiles push auto-deploys fleet-wide via the pull timers lane 2 catalogued,
so unrelated infra commits ride into every box's deploy path. The ceres-churn
*number* is tiny; the ceres-churn *coupling* is real.

**Lane 1's "clean git mv" vs lane 2's tracking≠health evidence — survives
with a caveat.** Nothing in lane 2 contradicts separability; but lane 2 shows
that relocation alone reproduces the current failure mode (enabled-but-bad
units, failing pull timers, tracked-but-undeployed units) in a new remote. The
leader holds only by adopting lane 2's prescription: the split must ship with
a reconciliation/convergence check, which no current repo has.

**Lane 3's "a split doesn't remove the pain" vs lanes 1+2 — re-weighted, not
overturned.** True for the two largest churn sources (submodule bumps,
provider writes — both have cheaper in-repo fixes, one already proven). But
the rebuttal from lanes 1+2: the split's actual value is *ownership and blast
radius* (unowned artifacts get an owner; one-box services stop riding the
fleet-wide auto-deploy), and probe B adds that most of the "agents churn" is
vendored content whose right fix is an install manifest, not a third remote.
Lane 3's verdict on premise (d) settles at: **wrong justification (churn),
right instinct (separation), wrong default target (a bare relocation).**

**Convergence check on lanes 1 and 2:** they cite the same artifacts
(`setup-immich.sh`, `docs/immich.md:143-147`, the symlink farm) from opposite
directions and reduce to complementary halves of one mechanism — they merge
into the rank-1 composite. Lane 3 stays separate: its evidence stream
(git measurement) is independent and its next probes differ.

## Convergence / Separation Notes

- Lanes 1 and 2 **converge** on the federated-ownership mechanism and on
  `~/repos/deploy` as the crux (independent evidence streams, same
  explanation) — merged into the composite.
- Lane 3 **kept separate**: independent measurement lane; its premise verdicts
  constrain the composite but imply different follow-ups (vendor-manifest
  work, secrets Phase-5 completion) than the ownership work.
- The naive framing was **down-ranked** for contradicted predictions: it
  predicted ceres-infra churn dominance (measured: 1.8%/0.2%) and predicted
  that repo contents define the infra domain (measured: ~14% of live
  artifacts).

## Most Likely Explanation

The discomfort is real but mis-attributed. Four mechanisms, in descending
severity:

1. **A fleet-level ownership gap, outside dotfiles.** ~45 live artifacts —
   an unversioned `~/repos/deploy` executed by nightly timers, hand-made
   portless/t3code/github-runner units on 2–3 hosts, 14 OpenClaw crons, macOS
   glue, and effectively all of makemake — belong to no repo. This, not
   dotfiles' content, is the infrastructure problem. The repo's own TODO
   already names the future infra repo as their intended owner.
2. **A provenance problem inside the agents tree, orthogonal to location.**
   ~75–85% of the 92 skills are vendored/provider content; provider processes
   write runtime state into tracked config (fought today by a checked-in
   enforcement hook). Moving the tree to a new remote changes none of this;
   an install-manifest / ignore boundary does.
3. **A small, clean, already-spec'd one-box infra set inside dotfiles.** Nine
   service triples, zero deploy coupling, 1.8% of commits — a literal `git mv`
   once a destination exists, per the repo's own carve-out convention.
4. **A deploy substrate with no reconciliation loop.** The fleet already runs
   a de-facto GitOps-lite system (owning-repo units + symlink farm +
   pull-timer auto-deploy) that no one repo asserts: enabled-but-broken units,
   failing pull timers on both Macs, tracked-but-undeployed units, and inert
   units on systemd-less hosts all persist silently. Any "structured dynamic
   system" recommendation should target *convergence checking* over this
   federation before (or instead of) centralizing it.

The agents layer is movable (12 path-bound files) but the case for a third
repo is provenance/ownership, not churn — and roughly half of what looks like
"agents" in the shell layer is either a one-box service CLI (785-line
`11_portkey.zsh`) or cgroup plumbing that must stay in dotfiles.

## Per-Lane Critical Unknowns

- **Lane 1 (verbatim):** "Does the agents layer have any consumer outside
  this repo's deploy path that would break if it moved — specifically, do the
  AI CLIs resolve `~/.claude`, `~/.agents`, `~/.gjc` by *symlink target path*
  rather than through the link?" — *collapsed by probe A at the path level
  (12 files, ~1 executable), but the write-through behavior (`gjc config set`
  writes through the link, `20_symlinks.zsh:104-117`) means agent-initiated
  writes would land in whichever repo owns the target: a workflow question
  only the user can weigh.*
- **Lane 2 (verbatim):** "Is `~/repos/deploy` intended to become the
  infrastructure repo, or is it intended to stay ephemeral runtime state?" —
  *partially answered by `docs/immich.md:143-147` (in scope for the repo when
  it exists); the open half is mechanics and priority: does the infra repo
  absorb it as versioned source, or render into it as regenerable output?*
- **Lane 3 (verbatim):** "What fraction of `configs/ai/`'s 316 tracked files
  and 92 SKILL.md files is user-authored versus provider-shipped or
  vendored?" — *collapsed by probe B: vendored dominates (~75–85% of skills);
  the open half is intent — is tracking vendored skills in git a deliberate
  fleet-distribution choice or an accident of `commit -A`?*

## Recommended Discriminating Probe

The remaining empirical uncertainty is the exact size of the unowned residue.
One read-only command per host (~30 s): resolve every live unit's `ExecStart`
target and test whether it sits in a git repo with a remote (lane 2's §7
script; `launchctl print`/plist equivalent on the Macs). Residue ≲5 paths →
the split is a repo-contents exercise; ≳20 → the parity spec must be
live-derived (current evidence: ≳20, given `~/repos/deploy`'s six trees plus
the watchdogs and bridges already found). Everything else still open is
intent, not evidence — resolved in the interview.
