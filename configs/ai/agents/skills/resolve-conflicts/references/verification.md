# Verification

Phase 5 runs the project's verification command on the touched files (or whole project, with explicit logging) to catch broken resolutions before handoff. This file describes how the executing agent discovers the right command.

---

## Discovery Ladder

Tried in order; first match wins. The matched tier is logged to `.conflicts/resolution-log.md` as `verification_tier: {n}`.

### Tier 1 — Explicit override

If `.omc/resolve-conflicts.json` exists at the repo root AND has a `verify` key:
```json
{
  "verify": "vp test --changed && vp staged",
  "verify_scope": "changed-files"
}
```
Use it directly. `verify_scope` may be `"changed-files"` (the executing agent appends touched-file paths to the command if the command supports it) or `"whole-project"` (run as-is).

### Tier 2 — `package.json scripts.test:related`

If `package.json` has `scripts["test:related"]`, use:
```
{package_manager} run test:related -- {touched-files-relative-to-repo-root}
```
where `{package_manager}` is `pnpm` if `pnpm-lock.yaml` exists, else `yarn` if `yarn.lock` exists, else `npm`.

### Tier 3 — `vp` binary + `vite.config.ts` (Webfront-style monorepo)

If ALL of these are true:
- `vp` is on PATH
- A `vite.config.ts` (or `.js`, `.mjs`) exists somewhere in the workspace
- The cwd is inside a workspace package containing touched files (per pnpm/yarn/npm workspace detection — see Monorepo Scoping below)

Use:
```
cd {package_root_containing_touched_files} && vp test --changed && vp staged
```

**NEVER** run `vp check` at the monorepo root in webfront — it OOMs. Always scope to a package.

### Tier 4 — `package.json scripts.test`

If `package.json` has `scripts["test"]`, use it (whole-suite, slower):
```
{package_manager} test
```
Mark `verify_scope: "whole-project"` in the log.

### Tier 5 — Cargo

If `Cargo.toml` exists:
```
cargo check && cargo test
```
Scope to package via `--package {name}` if in a Cargo workspace and touched files map to a single package.

### Tier 6 — Python

If `pyproject.toml` exists AND `pytest` is installed:
```
pytest {touched-test-files-or-modules}
```

If `pytest` is not installed but `python -m unittest` discovers tests:
```
python -m unittest discover
```

If neither: skip to Tier 7.

### Tier 7 — Skip with explicit log

No verify command discovered. Write to `.conflicts/resolution-log.md`:
```
verification: skipped
verification_tier: 7
verification_reason: "no command discovered for this repo (tried tiers 1-6)"
```

The downstream commit skill MUST refuse to commit when `verification: skipped` unless `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1` is set in the environment.

---

## Monorepo Scoping

Many monorepos OOM or take a very long time when verification runs at the root. The discovery ladder MUST scope to the workspace package(s) containing touched files.

### Detection

| Marker | Workspace type |
|--------|---------------|
| `pnpm-workspace.yaml` | pnpm |
| `package.json` with `workspaces` array | yarn / npm |
| `Cargo.toml` with `[workspace]` | cargo |
| `lerna.json` | lerna (legacy) |

### Scoping algorithm

1. Identify the workspace root (directory containing the workspace marker)
2. Read the workspace's package list (e.g., parse `pnpm-workspace.yaml` `packages:` glob)
3. For each touched file, find the longest-matching package directory
4. Group touched files by package
5. Run the verify command once per package containing touched files, scoped to that package's directory

For pnpm specifically:
```bash
# Determine touched packages
for f in $touched_files; do
  pnpm exec --workspace-concurrency=1 sh -c 'echo $PWD' \
    --filter "...{$f}" 2>/dev/null
done | sort -u
```

(In practice the executing agent uses simpler heuristics: walk up from each touched file looking for the nearest `package.json`.)

### Webfront specifics

- Workspace root: `/home/ctaylor/repos/webfront/` (`pnpm-workspace.yaml` present)
- Verify command in `packages/app/`: `cd packages/app && vp test --changed && vp staged`
- Verify command in `packages/api-core/`: `cd packages/api-core && vp staged && pnpm exec tsc --noEmit` (per CLAUDE.md, api-core has its own typecheck not covered by root)
- **Never `vp check` at repo root** (OOMs; documented in CLAUDE.md)

---

## Override Schema

`.omc/resolve-conflicts.json` (optional, repo-local):

```json
{
  "verify": "vp test --changed && vp staged",
  "verify_scope": "changed-files",
  "verify_per_package": {
    "packages/api-core": "vp staged && pnpm exec tsc --noEmit",
    "packages/app": "vp test --changed && vp staged"
  },
  "regenerators": {
    "**/routeTree.gen.ts": "vp run dev --no-open --build-only",
    "package-lock.json": "npm install"
  },
  "confidence_weights": {
    "line_overlap": 0.40,
    "contradiction": 0.30,
    "touched_symbol": 0.20,
    "upstream_context": 0.10
  },
  "struct_globs": [
    "drizzle/migrations/**",
    "schema.prisma"
  ],
  "inflight_doomed_ask_count": 5
}
```

If `verify_per_package` is set, it takes precedence over `verify` for any package matching one of its keys. Useful for monorepos where different packages have different test runners.

---

## Failure Handling

If the verification command exits non-zero:

1. Capture stdout + stderr (last 200 lines if longer)
2. Append to `.conflicts/resolution-log.md`:
   ```
   verification: failed
   verification_command: {cmd}
   verification_exit_code: {code}
   verification_output: |
     {captured-output}
   ```
3. Do NOT proceed to Phase 6
4. Do NOT auto-revert the resolutions (the resolutions may be correct; the failure may be a pre-existing issue)
5. ASK with options:
   - `(1) Show full output and let me investigate`
   - `(2) The failure is pre-existing — proceed to commit anyway`
   - `(3) Revert all resolutions and abort the merge`
   - `(N) Abort merge and request human review`

In non-interactive mode, defer to `.conflicts/pending-review.md` with the captured output and stop. Do NOT create a commit when verification has failed.

---

## Skip Handling (AC4 detail)

When Tier 7 fires (no command discovered), the `.conflicts/resolution-log.md` MUST include:

```
verification: skipped
verification_tier: 7
verification_reason: "no command discovered for this repo (tried tiers 1-6)"
```

The downstream commit skill (`commit-commands:commit` or `engram-commit-hygiene`) MUST inspect `.conflicts/resolution-log.md` and refuse to author the merge commit if `verification: skipped` is present, UNLESS `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1` is set in the environment.

This prevents silent skipping: a user who genuinely has no verification (e.g., a documentation-only repo) opts in explicitly via the env var, rather than the skill silently degrading.

---

## Examples

### Webfront monorepo, touched files in `packages/api-core/`

Discovery: Tier 3 matches (`vp` on PATH, `vite.config.ts` exists, cwd in workspace). Override at Tier 1 sets `verify_per_package` for `packages/api-core` → `vp staged && pnpm exec tsc --noEmit`.

```
cd /home/ctaylor/repos/webfront/packages/api-core
vp staged && pnpm exec tsc --noEmit
```

Logged: `verification: changed-files, verification_tier: 1 (override)`.

### Generic Node project with `test:related`

Discovery: Tier 2 matches.

```
pnpm run test:related -- src/auth/middleware.ts src/auth/types.ts
```

Logged: `verification: changed-files, verification_tier: 2`.

### Rust workspace, touched files in `crates/server/`

Discovery: Tier 5 matches.

```
cargo check --package server && cargo test --package server
```

Logged: `verification: changed-files, verification_tier: 5`.

### Documentation-only repo (no test runner)

Discovery: tiers 1–6 all miss. Tier 7 fires.

```
.conflicts/resolution-log.md:
verification: skipped
verification_tier: 7
verification_reason: "no command discovered for this repo (tried tiers 1-6)"
```

The user runs `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1 git merge ...` if they want to proceed without verification.
