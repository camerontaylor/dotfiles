---
name: context-generate
description: Generate minimal, context-efficient AGENTS.md files. Replaces deepinit with a lean-first approach. Use when asked to generate, create, or init AGENTS.md files.
tools: Read, Write, Glob, Grep, Bash
---

# Context Generate

Generate AGENTS.md files that are minimal by design. Every line must survive the Removal Gauntlet.

## Flags

- `--root-only`: Only generate root AGENTS.md (default)
- `--full`: Generate root + nested files at architectural boundaries
- `--verbose`: Slightly more detail (still gauntlet-compliant)

## Workflow

### 1. Analyze codebase
- Read package.json / Gemfile / pyproject.toml for stack info
- Read tsconfig.json for path aliases
- List top-level directories
- Read existing CLAUDE.md to avoid duplication

### 2. Determine hierarchy
Apply criteria from [context-audit/references/hierarchy-criteria.md](../context-audit/references/hierarchy-criteria.md). Only create nested files at genuine architectural boundaries.

### 3. Generate files
Use templates from [references/templates.md](references/templates.md). Root: 60-150 lines. Nested: 20-50 lines.

Sections: Architecture (non-obvious dirs only), Key Decisions (surprising choices only), Gotchas (real mistakes only), References (pointers, not content).

### 4. Content boundary enforcement
Per [context-audit/references/content-boundaries.md](../context-audit/references/content-boundaries.md):
- Commands, stack, project-wide gotchas → CLAUDE.md (don't duplicate)
- Structure, per-directory conventions → AGENTS.md

## Never Generate

File listings, code snippets, version numbers, generic advice, content in CLAUDE.md, content inferrable from package.json/Gemfile/tsconfig, boilerplate sections, styling rules.

## Deepinit Migration

Detect `<!-- Generated: -->` comments → warn about existing files → suggest `context-audit` first.
