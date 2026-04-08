# Content Boundaries: CLAUDE.md vs AGENTS.md

## Rule

CLAUDE.md = **how to work here** (commands, stack, project-wide rules).
AGENTS.md = **what lives where** (structure, per-directory conventions, navigation).

## Boundary Table

| Content Type | CLAUDE.md | AGENTS.md | Rationale |
|-------------|-----------|-----------|-----------|
| Build/test/lint commands | YES | no | Universal project commands |
| Project-wide gotchas | YES | no | Apply everywhere |
| Stack choices (non-obvious) | YES | no | High-level decisions |
| Path aliases / import rules | YES | no | Apply to all imports |
| Directory structure map | no | YES | Navigation/orientation |
| Per-directory conventions | no | YES | Localized patterns |
| Directory-specific gotchas | no | YES | Scoped warnings |
| Module relationships | no | YES | Architecture navigation |
| What a directory contains | no | YES | Orientation only |

## Overlap Resolution

When content appears in BOTH files:
1. Determine which file it belongs to per the table above
2. Keep it in the correct file
3. Delete it from the other file
4. If genuinely needed in both locations, keep in CLAUDE.md (higher priority loading) and add a one-line pointer from AGENTS.md

## Cross-Tool Visibility

- CLAUDE.md: Loaded by Claude Code only
- AGENTS.md: Loaded by Claude Code, Cursor, Copilot, Codex, Windsurf, Zed, and 20+ tools
- `.claude/skills/`: Claude Code only
- `docs/ai-context/`: Visible to all tools (preferred extraction target for cross-tool content)

When extracting content from AGENTS.md, prefer `docs/ai-context/` over `.claude/skills/` unless the content is Claude-specific.
