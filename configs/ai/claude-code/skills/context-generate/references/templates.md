# AGENTS.md Templates

## Root Template (target: 60-150 lines)

```markdown
# {Project Name}

{One sentence: what this project is.}

## Architecture

| Directory | Purpose |
|-----------|---------|
{Only directories whose purpose isn't obvious from their name}

## Key Decisions

{Only non-obvious choices — things the model would get wrong without being told}
- "We use X because Y" (only if Y is surprising)

## Gotchas

{Corrections for real mistakes — HIGHEST signal content}
- {Thing the model gets wrong} → {What to do instead}

## References

{Pointers to files the agent reads on-demand — NOT embedded content}
- For build/test commands: see `CLAUDE.md`
- For {domain} patterns: see `docs/ai-context/{domain}.md`
```

## Nested Template (target: 20-50 lines)

```markdown
# {Directory Name}

{One sentence purpose.}

## Key Decisions
{Why this exists, what's unusual about it}

## Gotchas
{Things an agent would get wrong without being told}

## See Also
{Pointers to related directories or reference docs}
```
