# File Classes

Classification rules for `resolve-conflicts`. Every conflicted file gets exactly one class. The class determines the resolution method.

Classes (in detection order — first match wins):

1. `deleted-modified` — handled in Phase 1, never auto-resolved
2. `binary` — always ASK
3. `lockfile` — regenerate via package manager
4. `generated` — regenerate via codegen command
5. `imports` — UNION
6. `tests` — UNION
7. `additive-config` — UNION if both sides only ADD; escalate if same key modified differently
8. `struct` — project-specific structural files; ASK
9. `code-logic` — default fallback; goes to Phase 4 with confidence rubric

---

## 1. `deleted-modified`

**Detection**: `git ls-files -u` shows the path with stage 1 (base) but only stage 2 OR stage 3 (not both) at non-zero mode. The "missing" stage indicates one side deleted the file while the other modified it.

**Resolution method**: NEVER auto. Phase 1 backs up the modified version + writes analysis report; Phase 4 (or pending-review handoff) resolves.

**Examples**: `docs/old-readme.md` deleted on main, modified on feature branch.

---

## 2. `binary`

**Detection**: `git ls-files --eol {path}` returns `binary` for the eol field, OR the file extension matches a known binary glob:

```
*.png  *.jpg  *.jpeg  *.gif  *.webp  *.ico  *.bmp  *.tiff
*.pdf  *.zip  *.tar  *.gz  *.tgz  *.bz2  *.xz  *.7z
*.mp3  *.mp4  *.wav  *.ogg  *.webm  *.mov  *.avi
*.woff  *.woff2  *.ttf  *.otf  *.eot
*.so  *.dylib  *.dll  *.exe  *.o  *.a
*.psd  *.ai  *.sketch  *.fig
*.db  *.sqlite  *.sqlite3
```

**Resolution method**: always ASK. Cannot reason about binary diffs textually.

---

## 3. `lockfile`

**Detection**: filename matches one of:

```
package-lock.json  yarn.lock  pnpm-lock.yaml  npm-shrinkwrap.json
Cargo.lock  go.sum  Gemfile.lock  Pipfile.lock  poetry.lock  uv.lock
composer.lock  mix.lock  pubspec.lock
```

**Resolution method**: delete the conflicted file, run the matching reinstall command (see Generated File Regenerators below).

---

## 4. `generated`

**Detection** (any one signal triggers):
- File header contains `// AUTO-GENERATED`, `# AUTO-GENERATED`, `<!-- AUTO-GENERATED`, `@generated`, `DO NOT EDIT`, `DO NOT MODIFY` (case-insensitive)
- Filename matches a known generated glob (see table below)
- File listed in `.gitattributes` with `linguist-generated=true`

**Resolution method**: delete the conflicted file, run the regenerator command from `.omc/resolve-conflicts.json` `regenerators` (or the default for the matching glob below).

### Default Generated File Regenerators

| Glob | Regenerator |
|------|-------------|
| `package-lock.json` | `npm install` |
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile=false` |
| `yarn.lock` | `yarn install` |
| `Cargo.lock` | `cargo build` |
| `go.sum` | `go mod tidy` |
| `Gemfile.lock` | `bundle install` |
| `Pipfile.lock` | `pipenv install` |
| `poetry.lock` | `poetry lock --no-update` |
| `uv.lock` | `uv lock` |
| `**/routeTree.gen.ts` | (project-defined; e.g., webfront: `vp run dev --no-open --build-only`) |
| `**/schema.gen.ts`, `**/schema.gen.js` | (project-defined; e.g., `pnpm db:generate`) |
| `**/__generated__/**` | (project-defined; require config override) |
| `**/*.pb.go`, `**/*.pb.ts` | `protoc --{lang}_out=...` (project-defined) |
| `**/graphql.generated.ts` | `pnpm codegen` (project-defined) |
| `**/dist/**`, `**/build/**`, `**/.next/**`, `**/.turbo/**` | should NOT be in git; flag and skip |

**If regenerator unknown**: do NOT hand-merge. Downgrade class to `code-logic` and pass to Phase 4 with the rationale "regenerator not configured for this generated file; agent must decide".

---

## 5. `imports`

**Detection**: ALL conflict blocks in the file are within the contiguous import region at the top of the file. Language-specific import region detection:

| Language | Import region heuristic |
|----------|------------------------|
| TypeScript / JavaScript | Contiguous `import` / `export ... from` / `require(...)` lines from line 1 |
| Python | Contiguous `import` / `from ... import` lines from line 1 (skipping shebang and module docstring) |
| Go | The `import (` block, OR contiguous `import "..."` lines |
| Rust | Contiguous `use` lines (and `extern crate`) at top of file or module |
| Java / Kotlin | Contiguous `import` lines after the package declaration |
| Ruby | Contiguous `require` / `require_relative` lines from the top |
| C / C++ | Contiguous `#include` lines |

**Resolution method**: UNION. Concatenate both sides' import lines. Dedupe identical lines. Order: HEAD imports first, then other-side imports not in HEAD. If the project's existing imports show alphabetical sorting, sort the unioned result.

**Edge case**: if the same module is imported with different specifiers (`import { a } from 'x'` on HEAD, `import { b } from 'x'` on other-side), merge specifiers: `import { a, b } from 'x'`.

---

## 6. `tests`

**Detection**: file path matches:

```
**/*.test.{ts,tsx,js,jsx,mjs,cjs}
**/*.spec.{ts,tsx,js,jsx,mjs,cjs}
**/__tests__/**
**/test_*.py
**/*_test.py
**/tests/**
**/*_test.go
**/spec/**
**/*_spec.rb
**/*Test.java
**/*Tests.java
```

**Resolution method**: UNION. Concatenate both sides' test cases. If the SAME test name appears on both sides with different bodies, this is a `directly contradicts` case — escalate to Phase 4 (do not silently pick one).

---

## 7. `additive-config`

**Detection**: filename ends in `.json`, `.yaml`, `.yml`, `.toml`, `.ini`, AND inspection shows both sides only ADD keys at the same nesting level (no key has different values on both sides).

**Resolution method**: UNION at the structural level (merge keys). If both sides modify the SAME key with different values, the resolution method is `directly contradicts` per `references/strategies.md § UNION vs CHOOSE` — escalate to Phase 4 with class downgrade to `code-logic`.

**Edge case `package.json`**: `dependencies` / `devDependencies` blocks merge by union; `version` field is NOT additive (escalate); `scripts` block is additive-merge.

---

## 8. `struct`

**Detection**: project-defined via `.omc/resolve-conflicts.json` `struct_globs` array, OR matches one of the common structural globs:

```
**/migrations/**           — DB migrations (ordering matters)
**/routes/**.{ts,tsx,js}   — file-based routes (registration order may matter)
**/schema.{prisma,sql}     — schema definitions (semantic merge required)
**/openapi.{yaml,json}     — API spec (semantic merge required)
**/proto/**.proto          — Protobuf definitions
```

**Resolution method**: ASK. Structural files often have ordering or semantic constraints that simple UNION breaks.

---

## 9. `code-logic`

**Detection**: default class. Any source file extension not matched above:

```
.ts .tsx .js .jsx .mjs .cjs
.py .pyx
.go
.rs
.rb
.java .kt .scala .groovy
.c .cpp .cc .h .hpp
.cs
.swift
.php
.lua .pl
.ex .exs
.erl .hrl
.zig
.dart
```

**Resolution method**: Phase 4 confidence rubric (see `references/strategies.md § Confidence Scoring`).

---

## Classification edge cases

**Mixed-region conflicts** (e.g., one block in imports + one block in code body): the file is class `code-logic`. UNION imports inside Phase 4 as a sub-step, then resolve the body conflict via the rubric.

**Unknown extension**: default to `code-logic`. Confidence rubric will likely score low (no upstream context match for unknown ecosystems) and the conflict will reach an ASK.

**Empty file vs deleted**: `git ls-files -u` will distinguish these. An empty stage 0 means deleted (not present); empty stage 2 or 3 means present but empty (extremely unusual — treat as `code-logic`).
