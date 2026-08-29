---
name: gjc-orchestration
description: Dispatch and drive gjc coding agents — planning-lane policy (writer-mandatory ralplan, decomposition triggers), the execution-contract levers (context, routing, accounting), the built-in workflow skills, paseo dispatch mechanics, and the plan→implement handoff. Consult whenever handing coding/planning work to a gjc agent from any other agent (claude, codex, harmony, gjc) or from the desktop.
metadata:
  version: "2.1.0"
---

# GJC orchestration

Canonical copy: `~/.local/dotfiles/configs/ai/agents/skills/gjc-orchestration/`.
The `~/repos/hart/skills/` and `~/.claude/skills/` entries are symlinks into
it — edit here, not through a symlink.

gjc (`~/.local/bin/gjc`, config `~/.gjc/agent/config.yml`) is registered as a
paseo ACP provider. Contract facts below are **verified against gjc 0.15.5 on
ceres, 2026-08-29** (0.15.3 → 0.15.5 upgraded mid-day; claims re-verified) (citations in `skills/ultragoal-prep/SKILL.md`'s
pinned-claims table); paseo dispatch mechanics (§4, §5, §7) were re-verified
2026-08-29 against paseo 0.7.0-beta.2 at the tool-schema level — the
0.5.0-beta.4 → 0.7.0-beta.2 jump renamed one settings key (see §4).

## 1. Verify the built-ins cheaply (no agent, no tokens)

```bash
gjc --version            # 0.15.5 pinned; re-verify contract claims on upgrade
gjc skills list          # bundled workflow skills: deep-interview, ralplan, autoresearch, ultragoal
gjc skills read ralplan  # full skill contract (also ultragoal, deep-interview, autoresearch)
gjc models               # configured models
```

The four bundled workflow skills are **canonical and hard shadow-filtered**: a
filesystem skill named `ultragoal`/`ralplan`/`deep-interview`/`autoresearch`
always resolves to the bundled definition, in every skills directory, with no
config override. Do not reimplement their protocols in dispatch prompts —
name them and let the gjc agent load its own contract. Behavioral policy goes
in **brief preambles** (explicit directives contractually outrank
skill-default routing heuristics) or in renamed companion skills — see
**`ultragoal-prep`** (shared from dotfiles `configs/ai/agents/skills/` via
`~/.agents/skills`, discovered through gjc's tracked `customDirectories`),
which carries the execution-contract preamble and pre-flight checklist for
multi-goal runs.
(A separate generic `ralplan` skill exists for Claude Code at
`~/.claude/skills/ralplan` — that one runs the protocol *in a claude
session*; when the executor is a gjc agent, use the gjc built-in.)

## 2. Planning-lane policy

- **Writer-mandatory**: any plan warranting a ralplan runs through
  `gjc ralplan --write` with stage artifacts, so the condensing `final` stage
  engages and caps/receipts are enforced rather than convention. Record stage
  byte-counts into the plan header:
  `wc -c .gjc/_session-*/plans/ralplan/<run-id>/*`.
  Hand-authoring is acceptable only below the **skip-ralplan boundary**
  (bundled ultragoal SKILL.md:228): scope small enough to skip ralplan may
  skip the writer too. Never hand-append amendment/supersession layers to a
  frozen plan — that is the failure mode this policy exists to kill.
- **Structural decomposition trigger** (decided at plan kickoff from the
  spec's component topology, never by task count): >1 independent domain, or
  a shared invariant surface consumed by multiple domains → a small
  **foundation plan** (freezes shared contracts: schema, events, budgets,
  precedence, acceptance authority) + **domain plans** consuming those
  contracts as non-negotiable inputs, each sized to one reviewable surface.
  Single-domain scope → single plan. Chaining is manual; record sequencing in
  the foundation plan.
- **PLANNING-STUCK path**: the 5-iteration cap ending without consensus (CLI
  exit 3) is terminal — do not blind-retry, and do not resolve residual
  findings as inline amendments. Carve the contested domain into a **fresh
  scoped ralplan run** (fresh `--run-id` = fresh budget) consuming the
  converged remainder as frozen input, so the contested part gets a full
  adversarial loop.
- **Frozen-contract change path**: a domain run discovering a frozen contract
  is wrong **blocks**; a scoped foundation amendment run changes the contract
  under adversarial review; affected domain plans get a stale-input review
  pass before resuming.
- **Before create-goals**: run `ultragoal-prep`'s pre-flight (consolidation
  check, invariant audit, seam naming, validation batches at creation) and
  paste its execution-contract preamble into the brief.

## 3. Execution-contract levers (all shipped, compose them)

- **Context**: leader-inline is the ultragoal **default** (bundled
  SKILL.md:201 — it does *not* delegate internally on its own); the
  `ultragoal-prep` preamble flips multi-goal runs to story-scoped fresh
  native executors + ≤3–5-file slices via resumption (SKILL.md:218-226) +
  boundary `/compact`//`/handoff` + a <150K leader checkpoint ceiling.
  **Auto-compaction will not save you**: with default thresholds a 1M-window
  model (glm-5.3) auto-compacts only near **850K tokens** — manual boundary
  compaction is the operative lever (decided 2026-08-29: no threshold config
  change; preamble-behavioral only).
- **Routing**: `~/.gjc/agent/config.yml` `task.agentModelOverrides`
  (executor→`zai/glm-5.3-flash`, architect→`glm-5.3:max`,
  planner→`glm-5.3:high`, critic→`gpt-5.6-sol:xhigh`) engages **only for
  gjc-native `task` spawns inside a gjc session**. External agent spawns
  (e.g. claude-zai) bypass routing entirely.
- **Accounting**: `token-log.jsonl` in the session dir is written **only by
  native task spawns** — external spawns leave no per-subagent token/cost
  trail. If a run should be measurable, native spawning is mandatory.
- **Subagent reuse/resumption** (SKILL.md:218-226): resume same-role
  subagents instead of re-paying context ramp-up; typed routing for
  running/queued/terminal states.
- **Fork-context budgets**: off by default — subagents start with ~zero
  inherited context; everything they need goes in the task payload.
- **Review cost**: validation batches declared at creation
  (`--validation-batch-json`) with boundary-once heavyweight review
  (SKILL.md:248) — the default; keep it.
- **Session/state facts** (bite when driving runs from shells): ultragoal
  state is **cwd-relative** (`<cwd>/.gjc/_session-<id>/ultragoal/`), and the
  ultragoal CLI write verbs resolve their session **from `GJC_SESSION_ID`
  env only** — no `--session-id` fallback; wrong cwd + right env reports a
  clean "missing". One driver per durable run, always — see
  `ultragoal-prep`'s one-driver rule for the mtime-band/pgrep protocol and
  the write-mechanics grounds (CAS goals, unguarded-and-first brief write,
  uncoordinated ledger appends).

## 4. Creating a gjc agent (paseo `create_agent` — verified 2026-08-29, paseo 0.7.0-beta.2)

```json
{
  "title": "Ralplan: <task>",
  "provider": "gjc/zai/glm-5.3",
  "workspaceId": "<ws-id>",            // omit = current workspace; create_workspace first for isolation
  "settings": { "modeId": "default", "thinkingOptionId": "high" },
  "notifyOnFinish": true,
  "labels": { "task": "ralplan", "spec": "<slug>" },
  "initialPrompt": "<brief — see §6>"
}
```

**Provider format is the #1 trap.** It MUST be `gjc/<model-id>`
(e.g. `gjc/zai/glm-5.3`). Bare `gjc` fails with
`provider must be provider/model, for example codex/gpt-5.4 at provider`.
On 2026-08-28 this format error was misread as "gjc rejects settings
payloads" and cost three throwaway probe agents.

**Settings that work on gjc creates** (key names re-checked against the
0.7.0-beta.2 `create_agent` schema 2026-08-29; runtime behaviour verified
live 2026-08-28):

- `modeId`: `default` for anything that writes files/artifacts. `plan`
  **blocks writes** — read-only review lanes only, never a ralplan owner.
- `thinkingOptionId`: `minimal | low | medium | high | xhigh | max`. Omitted
  → gjc's per-model default (glm-5.3 → `max`).
- `features`: e.g. `{ "auto_accept": true }` for unattended runs.
  **Renamed from `featureValues` in paseo 0.7.** `settings` is
  `additionalProperties: false`, so the old key is now a hard schema
  rejection, not a silently-ignored no-op (2026-08-29).

**Thinking vs role routing.** `modelRoles`/`agentModelOverrides` apply
automatically **only to gjc-native `task` role spawns inside a gjc session**.
Paseo-spawned gjc agents get nothing automatic — pin model (provider string)
and thinking per spawn, or accept defaults.

**Driving it:** follow-ups via `send_agent_prompt`; status via
`get_agent_status`. Do not poll — `notifyOnFinish` arrives on its own.
Children spawned by a gjc agent carry `labels["paseo.parent-agent-id"]`.

## 5. Headless one-shots (no paseo — flags re-verified 2026-08-29, gjc 0.15.5)

```bash
gjc -p --no-session "<prompt>"              # process and exit
gjc -p --smol zai/glm-5.3-flash "<prompt>"  # cheap fast model
```

ralplan/ultragoal are stateful multi-agent workflows — give them a persistent
agent, not `-p`.

## 6. The workflow built-ins from outside

You cannot `/skill:` from outside gjc. The invocation **is the dispatch
prompt naming the skill** — naming an execution skill also counts as opting
in. A good brief is self-contained: spec path, output path, hard constraints,
boundary, and (for multi-goal ultragoal) the `ultragoal-prep` preamble.

### ralplan — consensus planning (planner → architect → critic, ≤5 passes)

```
Run the gjc built-in **ralplan** skill (/skill:ralplan), deliberate mode.
Plan <milestone/scope> against the spec at <spec path>.
Hard constraints: <bullets>.
Use gjc ralplan --write with native role subagents; record stage byte-counts.
Write the final plan to <output path> marked "pending approval".
PLANNING ONLY: no source changes, no installs, no commits, no implementation.
Pre-resolved decisions (do not re-open): <intent items>.
```

- "Deliberate mode" for auth/security, migration, destructive, or
  public-API-breakage risk.
- Headless agents cannot answer ralplan's ask-gates: pre-resolve intent in
  the brief (deep-interview upstream is the clean way), or stand by via
  pendingPermissions / `send_agent_prompt`.
- **Native role subagents + `--write` are the required path** (§2): stage
  receipts enforce the iteration cap and produce an auditable run under
  `.gjc/_session-*/plans/ralplan/<run-id>/`. Paseo-spawned lanes make
  caps/receipts convention — that convention produced a 133KB five-layer
  supersession monolith once; don't repeat it.
- End states: **pending approval** → approve via follow-up, or pre-set
  `gjc.ralplan.autoHandoff: ultragoal` in project `.gjc/config.yml`.
  **PLANNING-STUCK** → the fresh-scoped-run path in §2, then escalate to a
  human with the scoped plan — never inline amendments.

### ultragoal — durable implementation (goal ledger + verification gates)

```
Approved: the plan at <path>. Invoke /skill:ultragoal with that plan.
<paste the ultragoal-prep execution-contract preamble here>
Execute every goal, verify each against its acceptance criteria,
checkpoint with evidence.
```

- Dispatch as its own gjc agent (`modeId: default`); it owns
  `goals.json`/`ledger.jsonl` and runs fail-closed quality gates
  (cleaner/architect/red-team cohort on a frozen source hash + terminal
  critic verdict) before completion checkpoints.
- **Leader-inline is the default execution shape** — without the preamble it
  will implement everything in one accumulating leader session. The preamble
  (and only the preamble) selects story-scoped fresh native executors,
  slices, boundary compaction, and the <150K ceiling.
- `ask` is blocked while a run is active — blockers are recorded durably.
  Progress: `GJC_SESSION_ID=<id> gjc ultragoal status --json` **from the
  repo that owns the run** (state is cwd-relative; env is the only session
  source). Expect long runs; the finish notification is the signal.
- Small bounded work may skip ralplan and go straight to ultragoal or a plain
  executor dispatch (skip-ralplan boundary, §2).

### deep-interview — requirements before spec

```
Run the gjc built-in **deep-interview** skill (/skill:deep-interview) on:
<raw request>. Interview <who answers> and produce a spec at <path>.
```

- Socratic ambiguity-gating, one question at a time. In a headless dispatch
  the **dispatcher is the interviewee** — answer via `send_agent_prompt` or
  relay to the human. Don't run it unattended with nobody answering.
- Chain: deep-interview → spec (topology enumerated) → §2 decomposition
  decision → ralplan (per plan) → ultragoal-prep pre-flight → ultragoal.

## 7. Gotchas

1. Bare `gjc` provider → hard error; always `gjc/<model-id>` (2026-08-28).
2. `modeId: plan` blocks the plan writes themselves (2026-08-28).
3. Don't poll running agents; notifications are the contract (2026-08-28).
4. A gjc agent under paseo has the agent-scoped paseo MCP injected — it can
   spawn its own sub-fleet; `modelRoles` won't reach those children
   automatically (2026-08-28).
5. `Request was aborted` transients happen on creates — retry once before
   diagnosing (2026-08-28).
6. External executor spawns (claude-zai etc.) silently bypass role routing
   AND token accounting — a run "delegating" through them looks cheaper and
   is unmeasurable. Native task spawns only for goal work (2026-08-29).
7. `gjc ultragoal status` without `GJC_SESSION_ID` exits 1; with env but the
   wrong cwd it exits 0 reporting `"missing"` — assert on output content,
   never exit codes (2026-08-29, empirical).
8. The companion skills reach gjc through the `~/.agents` dotfiles symlink +
   `customDirectories`; if that chain breaks, they vanish from discovery with
   **zero diagnostic** — re-run the `ultragoal-prep` smoke after gjc upgrades
   and dotfiles moves/redeploys. A same-named skill under `~/.gjc/skills/`
   silently outranks the tracked copies — don't put one there (2026-08-29).
9. `gjc skills discover` truncates its listing at 20 candidates, sorted by
   name, no flag to raise it — with >20 skills in `~/.agents/skills`,
   late-alphabet names silently drop off the list. Never use it as an
   existence check; runtime by-name loading is unaffected
   (`findRuntimeSkillByName` does an unlimited targeted scan) (2026-08-29).
10. paseo renamed `settings.featureValues` → `settings.features` in 0.7, and
    `settings` is `additionalProperties: false` — so a payload written
    against 0.5 fails the schema outright. Re-check the `create_agent`
    schema on every paseo minor bump; the §4 provider-format error message
    is unchanged, so the two failures look alike (2026-08-29).
