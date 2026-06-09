# The Removal Gauntlet

Every line in AGENTS.md or CLAUDE.md must survive ALL applicable tests or get cut.

## Tests

| # | Test | Cut if... | Preserve if... |
|---|------|-----------|----------------|
| 1 | **Removal** | Claude doesn't make mistakes without it | Removing it causes real errors |
| 2 | **Duplication** | Another loaded file already says this | This is the canonical source |
| 3 | **Inference** | Inferrable from package.json, Gemfile, tsconfig, or directory names | Requires reading 100+ lines of source to discover |
| 4 | **Staleness** | Contains version numbers, hardcoded paths, or embedded code snippets | Uses capability descriptions or file pointers instead |
| 5 | **Linter** | A linter, formatter, or hook should enforce this | No tooling exists for this rule |
| 6 | **Genericity** | Any competent model already knows this | Project-specific deviation from defaults |
| 7 | **Skill extraction** | Would work better loaded on-demand as a skill or reference doc | Must be known before any task begins |
| 8 | **Historical mistakes** | Model has never made this error in this codebase | Model has repeatedly gotten this wrong here |
| 9 | **Complexity threshold** | Simple concept with <3 edge cases | Subsystem with >3 non-obvious edge cases |
| 10 | **Content boundary** | Belongs in the other file (CLAUDE.md vs AGENTS.md) | Already in the correct file per boundary rules |

## Decision Priority

Tests 8-9 are **preservers** — they override cut decisions from tests 1-7. If content fails tests 1-7 but passes test 8 (model has made this mistake here), KEEP it.

Test 10 is a **mover** — content isn't deleted, just relocated to the correct file.

## Common Patterns

**Always cut:**
- "Write clean code", "Follow best practices", "Handle errors properly"
- File-by-file listings (agent can `ls` and `read`)
- Embedded code examples (agent can read the actual source files)
- Version numbers ("React 18.3", "TypeScript 5.9") — stale within months
- "For AI Agents" / "For New Team Members" boilerplate sections
- Styling/formatting rules (Biome/ESLint/Prettier handles this)
- Obvious tech stack info inferrable from package.json/Gemfile

**Always keep:**
- Exact build/test/lint commands with non-obvious flags
- Domain vocabulary where ambiguity causes real errors
- Corrections for mistakes Claude has actually made in THIS project
- Non-obvious architectural decisions ("we use X because Y")
- Path aliases and import conventions (models get these wrong frequently)
- Things that contradict what the model would assume by default

**Convert to pointer:**
- Code patterns → "See `src/path/to/canonical-example.ts`"
- Testing strategies → "See `docs/ai-context/testing.md`"
- Detailed module docs → "See `dir/README.md`"

## Applying the Gauntlet

For each section in the file:
1. Read the section
2. Run tests 1-7 (cutters). If ANY test says cut → mark for removal
3. Run tests 8-9 (preservers). If EITHER says preserve → override the cut
4. Run test 10 (boundary). If wrong file → mark for relocation
5. For items marked "cut via test 7" → propose skill extraction or pointer
6. Present all proposed changes to user for review before applying
