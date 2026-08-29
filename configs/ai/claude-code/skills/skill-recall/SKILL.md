---
name: skill-recall
description: Search the distilled SKILL.md library (project + global tiers) for procedural know-how before re-deriving a workflow. Use when starting a task that has probably been done before — a build/deploy/debug/migration procedure, a repo-specific gotcha, an ops runbook step — or when the user says "how did we do this last time".
argument-hint: "<what you are trying to do>"
---

# Skill recall — active search of the distilled library

The distiller (`~/repos/hart-agent-homes/tools/distiller/`) curates skills out of past
successful sessions into two tiers: the current project's `.agent/skills/` and the global
`~/repos/hart-agent-homes/wesley/skills/`. A reactive hook already injects close matches
at prompt time; **this skill is the liberal path** — use it deliberately, with a query you
compose, when you want know-how the hook didn't volunteer.

## How

```bash
~/repos/hart-agent-homes/tools/distiller/distill retrieve "<what you are trying to do>" \
    --mode active --lib "$PWD/.agent/skills"
```

- Phrase the query as the *task*, not keywords — retrieval is hybrid FTS + embedding
  cosine, so "roll back a bad deploy without losing the migration" beats "deploy rollback".
- Each hit prints name, description, and score components. Then **Read the skill file**
  for the full steps/pitfalls/verification before acting on it:
  `.agent/skills/<name>.md` (or `skills-pending/` for staged, lower-evidence hits).
- `--scope <slug>` narrows to one project's skills when working across repos.
- Try one rephrasing if the first query misses; then stop.

## Honesty rules

- "(no match — retrieval stayed quiet)" means **no match**. Proceed from first
  principles; never stretch a weak hit to fit.
- Skills cite `source_sessions` and carry `evidence_count` / `last_confirmed` — a
  low-evidence or stale skill is a hint, not an instruction. Verify its claims against
  current repo state before following it (that is itself the most-promoted skill).
- If a skill proved wrong or stale in use, say so in the session — the SessionEnd
  distiller run and the calibration log exist to catch exactly that.
