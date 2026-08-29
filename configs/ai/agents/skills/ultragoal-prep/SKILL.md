---
name: ultragoal-prep
description: Pre-flight checklist and execution-contract preamble for multi-goal gjc ultragoal runs — run before create-goals, paste the preamble into every multi-goal brief, and follow the validation-run protocol on the next multi-goal run. Companion to the canonical ultragoal skill (which cannot be modified or shadowed).
metadata:
  version: "1.0.0"
---

# ultragoal-prep — execution contract for multi-goal runs

**Verified against gjc 0.15.5 (2026-08-29** — originally pinned to 0.15.3,
which upgraded to 0.15.5 mid-session that same day; every pinned claim was
re-verified, with compaction internals relocated but semantically identical**).**
On any gjc upgrade or dotfiles relocation, re-run the smoke check
(§Install & smoke) and re-verify the pinned-claims table before trusting
this file. Provenance: hart
`plans/ralplan-coding-workflow-management.md` (4-iteration consensus) built on
`specs/coding-workflow-management-spec.md` and the evidence trace
`specs/analyse-our-coding-workflow-trace.md`.

**Why this skill exists (and is named this):** the canonical workflow skills
(`ultragoal`, `ralplan`, `deep-interview`, `autoresearch`) are hard
shadow-filtered in every skills directory — a filesystem skill with one of
those names always resolves to the bundled definition
(`src/skill-state/canonical-skills.ts:2`,
`src/extensibility/runtime-skill-discovery.ts:211-217`), and editing the
bundled SKILL.md is silently reverted on package update. A renamed companion
keeps all CLI verbs and runtime gates (they key off durable state, not skill
names). Behavioral policy therefore lives here and in brief preambles —
explicit directives contractually outrank skill-default routing heuristics
(`src/prompts/system/system-prompt.md:22`).

## When to use

- Before `gjc ultragoal create-goals` on any multi-goal scope: run the
  pre-flight checklist (§Consolidation check, §Invariant audit, §Seam naming,
  §Validation batches), then paste the §Preamble into the brief.
- **Small-run carve-out**: single-goal or skip-ralplan-scale scope (bundled
  ultragoal SKILL.md:228) stays leader-inline — skip the executor ceremony;
  the <150K leader ceiling still applies.

## Preamble template

Paste this block at the top of every multi-goal ultragoal brief, before the
first `@goal:` delimiter. It is self-contained — no external file references.

```
EXECUTION CONTRACT (explicit directives; these outrank skill-default routing
heuristics, including the "work within a single domain stays with the leader"
inline default):

1. Delegation: each story's implementation goes to a FRESH executor subagent
   spawned via the NATIVE task tool, discarded at that story's checkpoint.
   Never spawn external agents for goal work — external spawns bypass
   task.agentModelOverrides role routing and token-log.jsonl accounting.
2. Slices: drive each story as a SEQUENCE of task invocations of <=3-5
   explicit files each, resuming the same executor within the story
   (resume, don't respawn) per the subagent reuse contract.
3. Compaction: issue /compact or /handoff at EVERY story and batch boundary.
   Do not rely on auto-compaction — with default thresholds a 1M-context
   leader model auto-compacts only near 850K tokens.
4. Leader ceiling: leader context stays UNDER 150K tokens at every
   checkpoint; read the number from the session context report at checkpoint
   time and record it in the checkpoint evidence. The leader does
   orchestration, checkpoints, integration, and verification only.
5. Model routing: role->model routing comes from task.agentModelOverrides in
   the user config, engaged automatically by native task spawns. Do not
   hardcode models in this brief.
6. Attestations (must be true before create-goals ran; leave them in the
   brief as evidence):
   Attest: consolidation check run — artifact is as-amended, zero supersession layers.
   Attest: invariant audit run — nothing normative lives only in goal text.
   Attest: per-goal file-target seams named.
```

## Pre-flight checklist (before create-goals)

### Consolidation check

The artifact handed to `create-goals` must be **as-amended** — one normative
layer, zero supersession stack. Procedure:

```bash
grep -nEi 'supersede|SUPERSEDED|as amended by|amendment' <plan-file>
```

Any hit → consolidate first; do not extract. A plan produced by the CLI
writer's `final` stage qualifies by construction
(`src/gjc-runtime/ralplan-runtime.ts:90,1652`) — which is one reason plans
warranting a ralplan should go through `gjc ralplan --write` (see the
gjc-orchestration skill's writer-mandatory rule).

### Invariant audit

Spot-check each goal draft: any normative statement (MUST/acceptance
criterion/contract term) that exists **only** in goal text gets folded back
into the plan before extraction. Goal text may summarize and point; it must
never be the sole home of a requirement.

### Seam naming

Each goal names its file-target seam(s) so serial per-story workers stay
available. Goals stay **contract-merged** — validation-coupled stories merge
per the bundled granularity contract (ultragoal SKILL.md:106-115). There is
**no per-goal character budget**; density from a consolidated plan is fine
(the historical mega-goal problem was supersession-stack flattening, which
the consolidation check removes at the source).

### Validation batches

Declare batches at creation via `--validation-batch-json`, boundaries chosen
as review clusters; the boundary-once heavyweight-review default
(ultragoal SKILL.md:248) is retained, not overridden.

## Validation-run protocol (the next multi-goal run self-instruments)

The first multi-goal run executed under this contract doubles as the policy's
evidence run. It must start under the **full policy from goal 1**:

1. Plan produced via `gjc ralplan --write` with stage artifacts; record stage
   byte-counts into the plan header:
   `wc -c .gjc/_session-*/plans/ralplan/<run-id>/*`
   (this also settles whether plan growth is draft-side or review-side).
2. Preamble in the brief from goal 1; native task-tool executors only, so
   `token-log.jsonl` and role routing engage automatically.
3. Per-checkpoint leader context recorded; <150K at every checkpoint.
   Breaches are recorded as policy-amendment data, never hidden.
4. Write-up lands in hart `docs/research/` (dated at execution), framed as
   **observational reference — effect directions only, no causal claims**,
   compared against the libris baseline:
   - G001–G003 inline marginal context cost ≈102K / 74K / 43K tokens per goal
   - wall-clock 8.7 / 40.8 / 20.3 min; first boundary joined 7 blockers (VB001)
   - **Named confounds (carry all of them):** baseline G001–G002 ran on gjc
     0.14.2 (mid-run upgrade); different work content per goal; the baseline
     run self-adopted *external* executor delegation mid-run (02:57:22Z
     ledger event — the ~3× leader-burn drop belongs to that event, not to
     this policy); executor model catalog cost ≈0 makes the cost axis weak —
     tokens and wall-clock are the primary axes.

### One-driver rule (any live durable run)

One driver per durable ultragoal run, always. Grounds (verified 0.15.5):
goals.json writes are revision-guarded CAS that fail closed
(`ultragoal-runtime.ts:563-578`; conflict throw `state-writer.ts:543-545`;
guard engages only when `state_revision` is numeric, :574) — but cross-driver
read-modify-write cycles are unserialized, a second driver at fresh revision
clobbers semantically, the **brief write is atomic yet unguarded
last-writer-wins and is written before the goals CAS**
(`state-writer.ts:1115-1124`; ultragoal-runtime :567 precedes :571 — brief clobber happens even
on CAS-rejected writes), ledger appends are uncoordinated `appendJsonl`
(:1133-1138), and duplicate goal *execution* has no guard at all.

Live-driver check before touching any existing run:

- Leader transcript mtime **<15 min** → LIVE → steer the existing leader;
  never open a second session.
- **15–30 min** → wait and re-stat; do not act on one sample (durable-state
  staleness false-fires: goals.json can sit hours stale under an actively
  working leader).
- **≥30 min AND** a process-liveness check finds no driver →
  a successor may take over. Liveness: `pgrep -f 'gjc.*<session-id>'` (or the
  session's bun host process). A wrapper-shell self-match **fails safe** — a
  false "alive" blocks the successor, which is the correct direction.
- Successor sessions export `GJC_SESSION_ID=<session-id>` — env is the
  **only** session source for ultragoal CLI write verbs
  (`ultragoal-runtime.ts:311-313`; no `--session-id` fallback there) — and
  must run from the repo that owns the run: **ultragoal state is
  cwd-relative** (`<cwd>/.gjc/_session-<id>/ultragoal/`), so the right env in
  the wrong cwd reports a clean "missing" status rather than the run.

## Install & smoke

**Install:** the dotfiles repo is the source of truth — this skill lives at
`configs/ai/agents/skills/ultragoal-prep/` and reaches every deployed machine
with no per-skill step: `deploy.zsh` links `~/.agents` → that configs dir, and
the tracked gjc `config.yml` points `skills.customDirectories` at
`~/.agents/skills`. A fresh box gets the skill by cloning dotfiles and running
`deploy.zsh`. Consumers on the same single copy: gjc (customDirectories),
Claude Code (`~/.claude/skills/` is the dotfiles claude-code skills dir, which
holds a relative symlink here), and hart agents (`hart/skills/ultragoal-prep`
is a relative symlink here).

Discovery notes: custom-directory entries surface as `source: user`
(verified 2026-08-29); symlinked skill dirs are accepted
(`src/discovery/helpers.ts:453`); a same-named skill planted in
`~/.gjc/skills/` or `~/.gjc/agent/skills/` **outranks this copy** (gjc logs
"already resolved from a higher-precedence location") — don't shadow it there.

**Smoke (re-run after every gjc upgrade AND after dotfiles moves/redeploys)**
— every leg asserts output content, never a bare exit code; the pass signal
is the literal string:

```bash
gjc --version | grep -qx 'gjc/0.15.5' && grep -q 'name: ultragoal-prep' ~/.agents/skills/ultragoal-prep/SKILL.md && grep -q -- '- ~/.agents/skills' ~/.gjc/agent/config.yml && gjc ultragoal --help | grep -qi 'ultragoal workflow' && gjc ralplan --help | grep -q -- '--write' && echo SMOKE-PASS || echo SMOKE-FAIL
```

(Update the version literal on each re-pin.) Leg rationale:
- The two grep legs assert the delivery chain end-to-end: the SKILL.md is
  readable through the `~/.agents` dotfiles symlink, and the resolved gjc
  config still carries the `customDirectories` entry.
- **Do not use `gjc skills discover` as an existence check**: the CLI
  truncates its candidate list at `DEFAULT_LIMIT = 20`, sorted by name, with
  no limit/query flag (`runtime-skill-discovery.ts:53,425`; the CLI passes
  neither) — with >20 skills in the shared dir, late-alphabet names like
  `ultragoal-prep` silently vanish from the listing (observed 2026-08-29:
  adding gjc-orchestration as skill #21 pushed ultragoal-prep off the list).
  **Runtime loading is unaffected**: the skill tool resolves by name through
  an unlimited targeted scan (`findRuntimeSkillByName`,
  `runtime-skill-discovery.ts:430`; consulted at `tools/skill.ts:150`), and
  the in-session `skill_discovery` tool accepts `query`/`limit` inputs.
- The CLI-verb leg uses `--help` deliberately: help renders before settings
  migration and session resolution (`commands/ultragoal.ts:23-25`) —
  session-independent and mutation-safe. Empirical check (2026-08-29, /tmp):
  `gjc ultragoal status --json` without `GJC_SESSION_ID` prints "a session id
  is required to write state…" and exits **1**; with the env set but the
  wrong cwd it exits 0 reporting `"status": "missing"` with cwd-relative
  paths — both behaviors make `status` unsuitable as a smoke leg.

**Dangling-symlink warning:** discovery gates on `fs.existsSync(skillPath)`
(`helpers.ts:455`), which follows symlinks — if the `~/.agents` link or the
dotfiles checkout goes away, this skill **vanishes from discovery with zero
diagnostic** (and the hart/Claude-Code relative symlinks dangle too). That
silent-absence mode is why the smoke re-run is mandatory after dotfiles
relocations, not just gjc upgrades.

**Non-dotfiles host:** copy this directory to `~/.gjc/skills/ultragoal-prep/`
and run the same smoke. The preamble is embedded above, so the copy is
self-sufficient; it drifts from dotfiles until refreshed.

## Compaction policy (decided 2026-08-29)

Cameron chose **preamble-behavioral enforcement** (option c): no
`compaction.thresholdTokens` config change. Rationale: auto-compaction's
default threshold for a 1M-window model is contextWindow − max(15%, 16384,
maxOutputTokens) ≈ **850K tokens**
(`@gajae-code/agent-core/src/compaction/compaction.ts:262-269,416-437`; a 0.15.5 adaptive-threshold branch exists but is off by default, so the reserve path governs) — far
above the 150K policy ceiling, so the boundary `/compact`//`/handoff`
directive in the preamble is the operative lever. A positive global
`thresholdTokens` would clamp every session of every model, and on
≤150K-window models clamps to contextWindow − 1 (:426) — strictly worse
than the default for those models. Revisit only with evidence from the
validation run.

## Pinned-claims table (re-verify on upgrade)

| Claim | Source (gjc 0.15.5, package-qualified) |
|---|---|
| Canonical-name shadow filter | `@gajae-code/coding-agent/src/skill-state/canonical-skills.ts:2`; `src/extensibility/runtime-skill-discovery.ts:211-217` |
| Explicit directives outrank routing heuristics | `@gajae-code/coding-agent/src/prompts/system/system-prompt.md:22` |
| Leader-inline default / single sequenced executor | bundled `src/defaults/gjc/skills/ultragoal/SKILL.md:201` (single-domain literal reading :213; reuse/resumption :218-226; skip-ralplan :228; merge-coupled :106-115; boundary-once :248) |
| Role routing consumed by native task spawns | `@gajae-code/coding-agent/src/task/index.ts:1764`; config `~/.gjc/agent/config.yml:20-24` |
| token-log.jsonl written by native task machinery | `@gajae-code/coding-agent/src/task/token-log.ts:8` |
| goals.json CAS / brief unguarded-and-first / ledger uncoordinated | `@gajae-code/coding-agent/src/gjc-runtime/ultragoal-runtime.ts:563-578` (brief :567 before CAS :571; numeric guard :574); `src/gjc-runtime/state-writer.ts:543-545,1115-1124,1133-1138` |
| Env-only session resolution for ultragoal CLI write verbs | `@gajae-code/coding-agent/src/gjc-runtime/ultragoal-runtime.ts:311-313` |
| Auto-compaction threshold math (≈850K @ 1M window) | `@gajae-code/agent-core/src/compaction/compaction.ts:262-269,276-285,416-437` (clamp :426; defaults :160-166; adaptive branch off by default); settings `@gajae-code/coding-agent/src/config/settings-schema.ts:1899-1925`; glm-5.3 1M/131K in `@gajae-code/ai/src/models.json` |
| Symlinked skill dirs accepted; dangling = silent skip | `@gajae-code/coding-agent/src/discovery/helpers.ts:453,455` |
| User-scope skills dirs | `@gajae-code/coding-agent/src/extensibility/runtime-skill-discovery.ts:109-119` |
| `--help` renders pre-migration (mutation-safe smoke leg) | `@gajae-code/coding-agent/src/commands/ultragoal.ts:23-25` |
| discover CLI truncates at 20 by name; by-name runtime lookup unlimited | `@gajae-code/coding-agent/src/extensibility/runtime-skill-discovery.ts:53,425,430`; `src/tools/skill.ts:150` |
