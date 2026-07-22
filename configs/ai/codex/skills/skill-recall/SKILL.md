---
name: skill-recall
description: Search the distilled SKILL.md library (ollie_notes project tier + global tier) for procedural know-how before re-deriving a workflow. Use when starting a task that has probably been done before — an evidence-pipeline run, a court-document procedure, a repo-specific gotcha — or when asked "how did we do this last time".
---

# Skill recall — active search of the distilled library

The distiller (`~/repos/hart-agent-homes/tools/distiller/`) curates skills out of past
successful sessions on all hosts into two tiers: this machine's per-repo `.omc/skills/`
(ollie_notes for court work) and the global `~/repos/hart-agent-homes/wesley/skills/`.
Use this deliberately, with a query you compose, before re-deriving a procedure.

## How

```bash
~/repos/hart-agent-homes/tools/distiller/distill retrieve "<what you are trying to do>" \
    --mode active \
    --lib ~/repos/ollie_notes/.omc/skills \
    --global-lib ~/repos/hart-agent-homes/wesley/skills
```

- Phrase the query as the *task*, not keywords — "rebuild the search index without
  re-embedding unchanged chunks" beats "search index rebuild".
- Each hit prints name, description, and score components. Then **read the skill file**
  for full steps/pitfalls/verification before acting (`.omc/skills/<name>.md`, or
  `.omc/skills-pending/` for staged, lower-evidence hits).
- Working outside ollie_notes: pass that repo's `.omc/skills` as `--lib` instead.
- Try one rephrasing if the first query misses; then stop.

## Honesty rules

- "(no match — retrieval stayed quiet)" means **no match**. Proceed from first
  principles; never stretch a weak hit to fit.
- A low-evidence or stale skill is a hint, not an instruction — verify its claims
  against current repo state before following it.
- If a skill proved wrong or stale in use, say so in the session — the nightly
  distiller pass and its calibration log exist to catch exactly that.
