---
name: context-audit
description: Ruthlessly audit AGENTS.md and CLAUDE.md files to eliminate context bloat. Runs in preview mode by default. Use when asked to audit, trim, slim, or optimize context files, AGENTS.md, or CLAUDE.md.
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Context Audit

Eliminate context bloat by applying the Removal Gauntlet to every line. Preview mode by default — no changes without approval.

## Flags

- `--preview` (default): Report proposed cuts, no file changes
- `--apply`: Execute approved cuts after showing report
- `--severity=conservative|standard|aggressive`: How ruthless (default: standard)
- `--directory=path`: Audit one directory only

## Workflow

### 1. Discover files
Find all AGENTS.md and CLAUDE.md files. Count lines and estimate tokens (~4 chars/token).

### 2. Apply Removal Gauntlet
For each file, evaluate every section against the 10 tests in [references/removal-gauntlet.md](references/removal-gauntlet.md). Classify each section:

| Action | When |
|--------|------|
| **KEEP** | Passes gauntlet or preserved by tests 8-9 |
| **CUT** | Fails any of tests 1-7 and not preserved |
| **MOVE** | Wrong file per [references/content-boundaries.md](references/content-boundaries.md) |
| **EXTRACT** | Fails test 7 — better as on-demand reference doc |
| **POINTER** | Replace embedded content with file reference |

### 3. Check content boundaries
Flag overlap between CLAUDE.md and AGENTS.md. Apply boundary rules.

### 4. Check hierarchy
Evaluate which nested AGENTS.md files should exist per [references/hierarchy-criteria.md](references/hierarchy-criteria.md). Flag files that should be deleted entirely.

### 5. Generate report

```
## Context Audit Report
### Summary: X lines → Y lines (Z% reduction) across N files
### Per-file: [table with before/after/action for each file]
### Proposed cuts: [diffs grouped by action type]
### Files to delete: [nested AGENTS.md that don't meet hierarchy criteria]
### Extractions: [content → docs/ai-context/ location]
```

### 6. Apply (if --apply)
- Create backup at `.claude/context-backup/{date}/`
- Apply cuts, moves, extractions
- Verify referenced files exist
- Show final summary

## Severity Levels

| Level | Behavior |
|-------|----------|
| conservative | Only cut obvious bloat (generic advice, file listings, code snippets) |
| standard | Full gauntlet, preserve test 8-9 overrides |
| aggressive | Full gauntlet, only preserve `<!-- PRESERVE -->` tagged content |

## Safeguards
- Backup before any changes
- `<!-- PRESERVE -->` tags override all gauntlet tests
- `<!-- MANUAL -->` blocks preserved (deepinit convention)
- Max 5 skill/reference extractions per audit run
- Cross-tool warning when moving content to `.claude/`-only locations
- Extracted reference docs go to `docs/ai-context/` (visible to all tools)
