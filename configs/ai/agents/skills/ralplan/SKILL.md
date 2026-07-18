---
name: ralplan
description: Adversarial consensus planning — a planner subagent drafts, an architect steelmans, and a critic issues a gated verdict (APPROVE/ITERATE/REJECT) over at most 5 iterations, ending in an ADR-backed plan file marked pending approval. Use for non-trivial implementation planning before any build work begins.
---

# Ralplan — Consensus Planning

Ralplan produces an implementation plan through structured adversarial review. Three subagents play fixed roles: **planner** drafts and revises, **architect** challenges the draft with a steelman antithesis, **critic** gates it with a verdict. The loop closes — every revision goes back through both reviewers — until the critic approves or five iterations are exhausted. The result is a single plan file with an ADR and a consensus trail, marked `pending approval`.

## Usage

```
/ralplan <task description>
/ralplan --deliberate <task description>
```

- `--deliberate` — forces deliberate mode for high-risk work: adds a pre-mortem (3 scenarios) and an expanded test plan (unit/integration/e2e/observability). Deliberate mode also auto-enables when the request explicitly signals high risk: auth/security, data migrations, destructive or irreversible changes, production incidents, compliance/PII, public API breakage.

## Planning/execution boundary

This skill is planning-only. The **only** filesystem writes it may perform are creating the `plans/` directory and writing the output plan file `plans/ralplan-<slug>.md`. It MUST NOT edit source files, run mutation-oriented shell commands, commit, push, open PRs, or begin implementation — and it MUST NOT delegate implementation to any agent. The finished plan is marked `pending approval`; the skill **never auto-executes the plan**. Execution is a separate activity the user initiates explicitly after reading the plan.

## The three roles

| Role | `subagent_type` | Job | Writes files? |
|------|-----------------|-----|---------------|
| Planner | `planner` | Draft the plan + RALPLAN-DR deliberation summary; revise on feedback | No — returns plan text |
| Architect | `architect` | Steelman review: strongest antithesis, tradeoff tension, synthesis | No — read-only |
| Critic | `critic` | Quality gate: verdict APPROVE / ITERATE / REJECT with evidence | No — read-only |

**Sequencing is mandatory.** Architect and critic MUST run sequentially, never in the same parallel batch: the architect's review is an input to the critic. Always await the architect's result before invoking the critic.

All three subagents are read-only. The orchestrator (you, running this skill) carries the plan text between them and writes the final artifact.

## Workflow

### Step 0 — Gather input

1. Take the feature/task description from the arguments.
2. **Spec check:** glob `specs/*-spec.md` and look for a spec matching the task (by slug or keywords). If one matches, read it fully and treat it as **primary input**. If the spec contains `FR-###` (functional requirement) or `SC-###` (success criterion) identifiers, those identifiers MUST be preserved in the plan for traceability — every FR/SC either maps to a plan step or is explicitly marked out of scope with a reason.
3. Derive a short kebab-case `<slug>` from the task.
4. Decide mode: **short** (default) or **deliberate** (`--deliberate` or explicit high-risk signals as listed above).

### Step 1 — Planner drafts

Invoke the Agent tool with `subagent_type: "planner"`. The prompt MUST include: the task description, the spec content or path (if found) with the FR/SC preservation requirement, the mode (short/deliberate), and the requirement to return the complete plan plus a **RALPLAN-DR summary**:

- **Principles** (3–5) the plan commits to
- **Decision Drivers** (top 3)
- **Viable Options** (≥2) with bounded pros/cons each; if only one option genuinely survives, an explicit invalidation rationale for each rejected alternative
- The **chosen option justified against the drivers** — not just asserted
- Deliberate mode only: **pre-mortem** (3 scenarios, each framed "it's 6 months later and this failed because…") and an **expanded test plan** covering unit / integration / e2e / observability

Name the planner agent on first spawn (`name: ralplan-planner-<slug>`) so it can be resumed across iterations.

The planner is read-only; it returns the full plan text in its final message. Hold that text — do not write it to disk yet.

### Step 2 — Architect review (sequential)

Invoke `subagent_type: "architect"` with the full draft plan, the RALPLAN-DR summary, and the spec reference (if any). The architect review MUST contain:

- the **strongest steelman antithesis** against the chosen option — the best honest argument that the favored direction is wrong
- at least **one real tradeoff tension** that cannot be waved away
- a **synthesis** path where possible (how to preserve strengths of competing options)
- in deliberate mode: explicit flags for any violation of the plan's own stated principles

Await completion before Step 3. Never launch architect and critic together.

### Step 3 — Critic verdict

Invoke `subagent_type: "critic"` with the draft plan, the architect's full review, and the spec (if any). The critic applies its complete review protocol — pre-commitment predictions, claim verification against the codebase, the six-pass detection scan (duplication, ambiguity, underspecification, principles alignment, coverage gaps, inconsistency), multi-perspective review, and gap analysis — and returns exactly one verdict:

- **APPROVE** — plan is actionable; may carry non-blocking suggestions. Proceed to Step 4.5.
- **ITERATE** — plan needs revision; MUST come with specific, actionable deltas (not "add more detail"). Proceed to Step 4.
- **REJECT** — fundamental flaw: the approach itself is wrong, not fixable by revision. Stop the loop and return to the user with the critic's reasoning; the user decides whether to reframe the task, abandon it, or override.

Any CRITICAL-severity finding blocks APPROVE.

### Step 4 — Closed revision loop (max 5 iterations)

On ITERATE:

1. Collect **all** feedback from both the architect and the critic.
2. **Resume, don't respawn**: send the consolidated feedback to the named planner via SendMessage rather than spawning a fresh planner — it retains its codebase research context, so a revision doesn't re-pay the full exploration cost. Include: the prior plan, the full feedback, and the instruction to address every delta or explicitly justify rejecting it (with rationale recorded in the plan's changelog). If the resume fails, fall back to a fresh planner spawn and note the fallback in the consensus trail. The architect and critic are fresh spawns every pass — their independence is the point; the planner's continuity is the efficiency. (Known tradeoff: a resumed planner can anchor on its own draft; the fresh reviewers are the mitigation.)
3. **Return to Step 2** — the architect re-reviews the revised plan.
4. **Return to Step 3** — the critic re-evaluates.

One iteration = one full planner → architect → critic pass. Count them. If the critic has not returned APPROVE after **5 iterations**, stop looping: take the best version of the plan, list the unresolved objections verbatim in the consensus trail, and present it honestly to the user as "consensus not reached." Do not spin further.

### Step 4.5 — Intent reconciliation gate

Consensus among agents is not consent from the human. Before finalization, reconcile the approved plan against the user's actual intent so the loop has not silently baked in assumptions that conflict with what the user wants.

1. **Collect open items** from the RALPLAN-DR and the architect/critic feedback held in your context: every assumption any role resolved by assumption rather than stated fact; every ambiguity flagged during review; every decision the loop made without explicit user input.
2. **Cross-check prior artifacts**: re-scan the matched `specs/*-spec.md` (and its Assumptions table) for conflicts with the plan. Cite the conflicting artifact and section for anything found.
3. **Confirm one at a time** via `AskUserQuestion`, weakest/highest-impact first — each question states the assumption, where it came from, and 2-4 concrete resolutions.
4. **Divergence re-enters the loop**: if an answer contradicts the plan, route the correction back through Step 4's revision loop, within the same 5-iteration cap.
5. **Record resolutions** under an `## Intent Reconciliation` section of the plan (assumption → user resolution).
6. **Skip if clean**: if the plan has no open assumptions and no prior-artifact conflicts, say so and skip straight to Step 5 — never invent filler questions.

### Step 5 — Write the artifact

Create `plans/` if it does not exist. Write `plans/ralplan-<slug>.md` containing, in order:

1. **Header** — status `pending approval`, date, mode (short/deliberate), iteration count, spec file used (or "none")
2. **RALPLAN-DR summary** — principles, drivers, options with pros/cons, chosen option + justification
3. **Plan body** — context, objectives, guardrails (must have / must NOT have), implementation steps with per-step acceptance criteria and file references, risks with mitigations, verification steps; deliberate mode adds the pre-mortem and expanded test plan
4. **Traceability table** (only if a spec was used) — each FR-###/SC-### mapped to the plan step(s) covering it, or marked out of scope with a reason
5. **ADR** — Decision / Drivers / Alternatives considered / Why chosen / Consequences / Follow-ups
6. **Consensus trail** — per-iteration verdicts (architect stance + critic verdict), what changed between iterations, and any unresolved objections if consensus was not reached

Then present a short summary to the user (plan path, iteration count, final verdict, headline decision) and **stop**. Do not execute, do not offer to execute in the same breath as writing — the plan is `pending approval`.

## Plan file skeleton

```markdown
# Plan: <title>            <!-- plans/ralplan-<slug>.md -->
Status: pending approval | Mode: short|deliberate | Iterations: N | Spec: specs/x-spec.md|none

## RALPLAN-DR
Principles: … (3–5)
Decision drivers: … (top 3)
Options: A … / B … (pros/cons each)
Chosen: <option>, because <justified against drivers>

## Plan
Context / Objectives / Guardrails
Steps (each: action, files, acceptance criteria)
Risks & mitigations / Verification
[deliberate: Pre-mortem ×3 / Test plan: unit, integration, e2e, observability]

## Traceability (if spec)
| FR/SC | Covered by | Notes |

## Intent Reconciliation
<assumption → user resolution> | none open — gate skipped clean

## ADR
Decision / Drivers / Alternatives considered / Why chosen / Consequences / Follow-ups

## Consensus trail
Iter 1: architect — <headline>; critic — ITERATE (<deltas>)
Iter 2: … critic — APPROVE
Unresolved objections: none | <list>
```

## Quality bar (what the critic enforces)

- Six-pass detection scan over the plan (and spec, if present): **A** duplication, **B** ambiguity — vague adjectives (fast/scalable/secure/robust/intuitive) without measurable criteria, **C** underspecification, **D** principles alignment — a conflict with the plan's *own stated principles* is automatically CRITICAL, **E** coverage gaps — FR-###/SC-### with no plan coverage, **F** inconsistency — terminology drift, ordering contradictions.
- Severity scale CRITICAL / HIGH / MEDIUM / LOW; **CRITICAL blocks APPROVE**.
- Principle–option consistency, fair alternatives (no strawmanned options), risk mitigation clarity, testable acceptance criteria ("fast" → "p99 < 200ms"), concrete verification steps.
- Deliberate mode: a missing or weak pre-mortem or test plan is CRITICAL.

## Failure handling

- **No spec found** — proceed from the task description alone; record `Spec: none` in the header.
- **Critic REJECT** — stop immediately, surface the verdict and reasoning to the user. Do not silently restart planning with a different approach; the reframe is the user's call.
- **5 iterations without APPROVE** — write the best plan with unresolved objections listed; never present it as approved.
- **Malformed review** — if the architect omits the antithesis/tension or the critic omits a verdict, re-invoke that agent once naming the missing element; if still missing, note the deficiency in the consensus trail rather than fabricating it.
- **Vague input** — if the task description is too thin to plan at all (no identifiable scope), ask the user for the missing scope before Step 1 rather than burning iterations on guesswork.

## Checklist (before finishing)

- [ ] Architect and critic ran sequentially in every iteration
- [ ] RALPLAN-DR complete: 3–5 principles, top-3 drivers, ≥2 options (or explicit invalidation rationale)
- [ ] Chosen option justified against the drivers, not merely stated
- [ ] Every FR-###/SC-### from the spec traced or explicitly excluded
- [ ] ADR present: Decision / Drivers / Alternatives / Why / Consequences / Follow-ups
- [ ] Consensus trail records every iteration's verdicts
- [ ] Intent reconciliation ran after APPROVE: open assumptions confirmed with the user one at a time, or gate skipped clean and said so
- [ ] Deliberate mode (if active): pre-mortem ×3 + unit/integration/e2e/observability test plan
- [ ] Plan written to `plans/ralplan-<slug>.md`, marked `pending approval`
- [ ] No source files touched, nothing executed, no execution offered as part of this skill

<!-- Adapted from oh-my-claudecode (MIT, © 2025 Yeachan Heo). Detection passes adapted from GitHub spec-kit (MIT). Intent-reconciliation gate and persisted-planner pattern adapted from gajae-code (MIT, © Yeachan Heo). -->
