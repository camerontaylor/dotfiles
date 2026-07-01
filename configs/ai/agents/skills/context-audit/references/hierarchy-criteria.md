# Hierarchy Criteria: When to Create Nested AGENTS.md

## Create a nested AGENTS.md if ANY apply

| Criterion | Example |
|-----------|---------|
| **Architectural boundary** | Separate pnpm workspace, independent package |
| **Different tech stack** | Python service in a TypeScript monorepo |
| **Non-obvious conventions** | Framework-specific patterns (Hobo models, MobX stores) |
| **Documented gotchas** | Real mistakes that happened in this directory |
| **Complex subsystem** | Module with >3 non-obvious edge cases |

## Skip nested AGENTS.md if ALL apply

| Criterion | Example |
|-----------|---------|
| < 5 files | `utils/` with 3 helpers |
| Purpose obvious from names | `components/Button/Button.tsx` |
| No special conventions | Standard framework patterns |
| No historical gotchas | Zero mistakes from this directory |
| Parent file covers it adequately | One line in parent's structure table suffices |

## Size Targets

| Level | Target Lines | Contains |
|-------|-------------|----------|
| Root | 60-150 | Overview, commands, architecture map, gotchas |
| Major boundary | 20-50 | Purpose, key decisions, gotchas, references |
| Leaf (rare) | 10-20 | Purpose, one gotcha, see-also |

## Realistic File Counts

| Project Size | Expected AGENTS.md Files |
|-------------|------------------------|
| Small (<20 dirs) | 1-3 |
| Medium (20-100 dirs) | 3-8 |
| Large monorepo (100+ dirs) | 5-15 |

The current project has 19 files. Target: 5-12 after audit.
