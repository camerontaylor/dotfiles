---
name: learner
description: Extract learned skills from a completed session or investigation
---

# Learner

Use this skill after a session uncovered something genuinely non-obvious and reusable.

## Extract only high-value insights

Do not save:
- generic programming advice
- library usage that is easy to look up
- routine refactors or boilerplate
- anything a fresh search or docs read would reveal quickly

Save only:
- codebase-specific gotchas
- framework or tool quirks that took real debugging to uncover
- precise workarounds with concrete recognition patterns
- project-specific decision rules worth remembering

## Output target

Prefer project-level skills in `.omc/skills/`.

Only create files when the session produced a skill-worthy insight. If not, explicitly say:

`No extractable skills found.`

## Required structure

Each saved skill should be a markdown file that explains:
- the core insight
- why it matters here
- how to recognize when it applies
- the exact approach to take next time

Good skills improve future decision-making. They are not copy-paste snippets.
