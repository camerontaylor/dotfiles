---
name: resolve-conflicts
description: Autonomously resolve git merge/rebase/cherry-pick conflicts using forge-style tiered phases. Detects doomed merges and recommends alternative integration strategies before resolving. Defaults to UNION for non-contradicting changes. Regenerates generated files instead of hand-merging. Backs up deleted-modified work before any resolution. Worktree-fleet safe via RESOLVE_CONFLICTS_NONINTERACTIVE=1. Composes with commit-commands and engram-commit-hygiene.
---

<Purpose>
Resolve git conflicts autonomously while never silently discarding work. Forks the antinomyhq/forge resolve-conflicts skill with relaxed gates for low-risk phases (auto), a confidence-scored gate for high-risk code logic (Phase 4), and an upstream Phase 0 advisory that recommends aborting and re-integrating with a different strategy when the chosen one is doomed. The skill is a behavioral specification — an executing agent reads it and follows the imperative MUST/SHOULD/MAY directives.
</Purpose>

<Use_When>
- Git operation produced conflict markers (`<<<<<<< HEAD`, `=======`, `>>>>>>>`) in any file
- `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, or `.git/CHERRY_PICK_HEAD` exists (mid-conflict re-entry)
- User says "resolve conflicts", "fix the merge", "merge {branch}", "rebase onto {branch}", "finish the merge"
- An agent reads any file containing conflict markers
- Pre-merge advisory requested (`RESOLVE_CONFLICTS_PREMERGE_ONLY=1`)
</Use_When>

<Do_Not_Use_When>
- Pre-commit hook failures (lint, format, typecheck) — different problem class, fix the underlying issue
- Generating commit messages — delegate to `engram-commit-hygiene` or `conventional-commits`
- Pushing or creating PRs — delegate to `commit-commands:commit-push-pr`
- Non-git VCS (Mercurial, Fossil, etc.) — git only
- Squash/rebase history rewriting beyond what's needed to resolve conflicts
</Do_Not_Use_When>

<Forge_Lineage>
Forks `antinomyhq/forge` `resolve-conflicts` skill (https://github.com/antinomyhq/forge/tree/main/.forge/skills/resolve-conflicts). Intentional divergences:

1. **Relaxed gates 0–3**: forge requires user approval before each phase; this skill auto-proceeds Phases 0–3 (backups, regeneration, low-risk merges) so it doesn't block parallel agent runs.
2. **Confidence-scored Phase 4**: forge always asks on code logic; this skill applies a 4-signal rubric and only asks below threshold (default 0.7).
3. **Phase 0 doomed-merge detection**: forge starts at backups; this skill first checks whether the chosen integration strategy is even right, and may recommend abort+retry with a different strategy.
4. **Worktree-fleet mode**: `RESOLVE_CONFLICTS_NONINTERACTIVE=1` defers all asks to `.conflicts/pending-review.md` instead of blocking.
</Forge_Lineage>

<Execution_Policy>
- **Never silently discard work.** Deleted-modified pairs are ALWAYS backed up before any resolution decision (Phase 1).
- **Classify before resolving.** Every conflicted file gets a `FileClass` label (see `references/file-classes.md`). The class determines the resolution method, not guesswork.
- **UNION is the default for non-contradicting changes.** Two sides adding different lines (imports, tests, additive config keys) MUST be unioned without prompting. See `references/strategies.md` § UNION vs CHOOSE for the single canonical "directly contradicts" definition.
- **Regenerate, don't hand-merge.** Generated files (lockfiles, codegen output) MUST be regenerated from source, never line-merged.
- **Load upstream context for code-logic conflicts.** Before resolving any `code-logic` class conflict, run `git log -p {merge-base}..{other-side} -- {path}` to load the refactor that caused the conflict. Cite the relevant commit in the resolution rationale.
- **Verify before handoff.** Phase 5 runs the project's verification command (see `references/verification.md`) on touched files. Failure blocks the commit.
- **In-flight doomed-merge re-evaluation.** If Phase 4 produces more than `RESOLVE_CONFLICTS_INFLIGHT_DOOMED_ASK_COUNT` (default 5) low-confidence asks during a single session, re-run Phase 0 thresholds and emit a fresh strategy advisory.
- **Non-interactive mode never blocks.** When `RESOLVE_CONFLICTS_NONINTERACTIVE=1`, every ASK is deferred to `.conflicts/pending-review.md` (append-only); the skill continues with the most-conservative resolution (typically: skip the file, mark pending, move on).
- **Configurable, not patchable.** Thresholds, weights, and verification commands are tuned via env vars or `.omc/resolve-conflicts.json`. Do NOT modify SKILL.md to change a default.
</Execution_Policy>

<Phase_0_Strategy_Advisory>
**Trigger**: every invocation, before Phase 1. Auto-acts unless `RESOLVE_CONFLICTS_FORCE_MERGE=1`.

**Inputs**:
- Conflict count: `git diff --name-only --diff-filter=U | wc -l`
- Deleted-modified count: `git ls-files -u | awk '{print $4}' | sort -u | xargs -I{} git ls-files -u -- {} | awk '$1==000000 || $1==0 {c++} END {print c}'` (or equivalent — count paths where one side has stage 0 and the other has stage 2 or 3 with non-zero mode)
- For `RESOLVE_CONFLICTS_PREMERGE_ONLY=1` mode: simulate via `git merge-tree --write-tree {HEAD} {other}` and parse the conflict markers from the output

**Phase 0 Contract** (stable, so a future `choose-integration-strategy` skill can call in without breaking changes):
- Input: `{ conflict_count: int, deleted_modified_count: int, conflict_paths: string[], strategy_in_progress: "merge" | "rebase" | "cherry-pick" | null }`
- Output: `{ recommendation: "proceed" | "rebase" | "cherry-pick-subset" | "split-then-merge" | "abort-and-restart", rationale: string, advisory_md: string }`

**Doomed-merge thresholds** (configurable via env vars):
- `RESOLVE_CONFLICTS_DOOMED_FILE_COUNT` (default 20)
- `RESOLVE_CONFLICTS_DOOMED_DM_COUNT` (default 3)

If thresholds tripped, emit one of the four advisories per `references/strategies.md` § Strategy Advisory Templates. In interactive mode, ASK whether to proceed with the original strategy or follow the advisory. In non-interactive mode, write the advisory to `.conflicts/pending-review.md` and continue with the original strategy unless the user has set `RESOLVE_CONFLICTS_AUTO_ACT_ADVISORY=1`.

**`RESOLVE_CONFLICTS_PREMERGE_ONLY=1`**: run Phase 0 ONLY against the simulated `git merge-tree` output and exit. Never touches the working tree. Useful for pre-merge "should I do this?" checks.
</Phase_0_Strategy_Advisory>

<Phase_1_Backups>
**Trigger**: always, after Phase 0. Auto. NEVER destructive.

**Step A (FIRST FILESYSTEM OPERATION, ATOMIC)**: create `.conflicts/.gitignore` containing exactly:
```
*
!.gitignore
```
Write this BEFORE any other file inside `.conflicts/`. This MUST be the first write in Phase 1.

**Step B (verification gate)**: run `git check-ignore .conflicts/test-marker`. If it returns non-zero (i.e., the file would NOT be ignored), abort Phase 1 with explicit error: "`.conflicts/.gitignore` did not take effect — refusing to proceed; risk of committing backup data."

**Step C (deleted-modified detection)**: parse `git ls-files -u`. For each path where one side has stage 0 (deleted) and the other has stage 2 or 3 (modified):
1. Read the modified version into memory
2. Write to `.conflicts/backups/{ISO8601-timestamp}-{path-with-slashes-replaced-by-double-dash}` — e.g., `.conflicts/backups/2026-04-20T12-34-56Z-src--auth--middleware.ts`
3. Append a record to `.conflicts/analysis-{ISO8601-timestamp}.md` describing: the path, which side deleted, which side modified, line counts, and a unified diff against the merge base
4. Mark the path as ASK-pending (or, in non-interactive mode, defer to `.conflicts/pending-review.md`)

**Step D**: do NOT resolve any deleted-modified conflict in this phase. Resolution happens in Phase 4 (or via the pending-review handoff).
</Phase_1_Backups>

<Phase_2_Regenerate_Generated>
**Trigger**: after Phase 1. Auto.

For each conflicted file, classify per `references/file-classes.md`. If class is `generated` or `lockfile`:
1. Delete the conflicted version: `rm {path}` (the conflict markers are no longer needed — we're regenerating)
2. Run the regeneration command per `references/file-classes.md` § Generated File Regenerators (or per `.omc/resolve-conflicts.json` `regenerators` override)
3. Stage the regenerated file: `git add {path}`
4. Append to `.conflicts/resolution-log.md`: `{path} — class: generated, method: regenerate, command: {cmd}`

**Never hand-merge generated files.** If regeneration fails (command not found, command errored), do NOT fall back to manual merge — defer to Phase 4 with class downgrade to `code-logic` and a note in the rationale.
</Phase_2_Regenerate_Generated>

<Phase_3_Low_Risk_Merges>
**Trigger**: after Phase 2. Auto, default UNION.

For each remaining conflicted file, classify. If class is `imports`, `tests`, `additive-config`, or `struct`:
1. Read the conflict block(s)
2. Apply the resolution method per `references/strategies.md` § UNION vs CHOOSE — default is UNION (concatenate both sides, dedupe identical lines, preserve order: HEAD lines first, then other-side lines not already in HEAD)
3. For `imports` specifically: dedupe by import path; sort per project convention if discoverable from existing import order (or leave in concat order)
4. For `additive-config` (`.json`/`.yaml`/`.toml`): if both sides only ADD keys at the same level, merge keys; if both sides modify the SAME key with different values, this is a `directly contradicts` case — escalate to Phase 4
5. Stage the file: `git add {path}`
6. Append to `.conflicts/resolution-log.md`: `{path} — class: {class}, method: union, lines_a: {n}, lines_b: {n}, lines_out: {n}`
</Phase_3_Low_Risk_Merges>

<Phase_4_High_Risk_Code_Logic>
**Trigger**: after Phase 3. Confidence-gated.

For each remaining conflicted file (class `code-logic`, `binary`, or downgraded from generated):

1. **Load upstream context** (MUST):
   ```
   git log -p --reverse {merge-base}..{other-side} -- {path}
   ```
   Read the output. Identify the commit(s) that touched the conflicted lines. Note the commit subject(s) for the rationale.

2. **Apply the C1+C2 confidence rubric** (see `references/strategies.md` § Confidence Scoring):
   - Compute the 4 signals (line-overlap, contradiction, touched-symbol, upstream-context)
   - Apply weights (default 40/30/20/10; configurable via `.omc/resolve-conflicts.json` `confidence_weights`)
   - If a signal cannot be computed (e.g., touched-symbol on a non-curly-brace language without tree-sitter), re-normalize remaining weights to sum to 1.0 and log the skipped signal in the rationale
   - Apply C2 layer: agent may adjust the C1 score by ±0.1 with explicit rationale

3. **Decide**:
   - If score ≥ `RESOLVE_CONFLICTS_CONFIDENCE_THRESHOLD` (default 0.7): auto-resolve, write the resolution + rationale + per-signal scores to `.conflicts/resolution-log.md`, stage the file
   - If score < threshold: ASK with numbered options OR (non-interactive) defer to `.conflicts/pending-review.md`

4. **ASK format** (interactive mode):
   ```
   Conflict in {path} (class: code-logic, confidence: {score}, threshold: {threshold})
   Upstream context: {commit subjects}

   (1) Take HEAD version: {one-line description}
   (2) Take other-side version: {one-line description}
   (3) Apply proposed merge: {one-line description}
   (4) Apply alternative: {one-line description, if any}
   (N) Abort merge and request human review
   ```
   Option `(N) Abort merge and request human review` MUST always be present as the final option.

5. **Increment Phase 4 ASK counter**. If counter exceeds `RESOLVE_CONFLICTS_INFLIGHT_DOOMED_ASK_COUNT` (default 5), trigger in-flight doomed-merge re-evaluation: re-run Phase 0 thresholds against the current state and emit a fresh advisory.

6. **Binary class**: always ASK (cannot reason about binary diffs). Same numbered-options format.
</Phase_4_High_Risk_Code_Logic>

<Phase_5_Verification>
**Trigger**: after Phase 4 completes (no pending unresolved files). Auto.

1. Discover the verify command per `references/verification.md` § Discovery Ladder (7 tiers)
2. Run the discovered command, scoped to touched files when possible
3. Append to `.conflicts/resolution-log.md`:
   ```
   verification: {touched-files | whole-project | skipped}
   verification_command: {cmd}
   verification_exit_code: {code}
   ```
4. If exit code is non-zero: do NOT proceed to Phase 6. Append failure output to `.conflicts/resolution-log.md` and ASK (or defer to pending-review).
5. If verification was skipped (Tier 7, no command discovered), the `verification: skipped` flag MUST be present. The downstream commit skill will refuse to commit unless `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1`.
</Phase_5_Verification>

<Phase_6_Handoff>
**Trigger**: Phase 5 verification passed (or was skipped with explicit flag). Auto.

Working tree state at handoff: all conflict markers gone, all formerly-conflicted files staged, `.conflicts/resolution-log.md` complete, `.conflicts/.gitignore` in place.

**Non-interactive mode (`RESOLVE_CONFLICTS_NONINTERACTIVE=1`)**: invoke `commit-commands:commit --non-interactive` (or the equivalent flag for whichever commit skill the user has installed). Pass `.conflicts/resolution-log.md` as context for the commit message body.

**Interactive mode**: emit a one-line "ready to commit" message and exit. Do NOT author the merge commit message — that responsibility belongs to `commit-commands:commit` or `engram-commit-hygiene`.

This skill never writes commit messages itself.
</Phase_6_Handoff>

<Mid_Conflict_Re_Entry>
The skill MUST detect mid-conflict state at every invocation:
- `.git/MERGE_HEAD` exists → merge in progress
- `.git/REBASE_HEAD` or `.git/rebase-merge/` or `.git/rebase-apply/` exists → rebase in progress
- `.git/CHERRY_PICK_HEAD` exists → cherry-pick in progress

Precedence when multiple are present (see `references/strategies.md` § Mid-Conflict Re-Entry for the table): **REBASE > CHERRY_PICK > MERGE**.

On mid-conflict re-entry:
1. Skip Phase 1 Steps A/B if `.conflicts/.gitignore` already exists with correct content
2. Re-derive Phase 0 strategy from the current state (the in-progress strategy may already be doomed retroactively)
3. If doomed thresholds tripped, recommend `git merge --abort` (or `git rebase --abort` / `git cherry-pick --abort`) and restart with the advised strategy
4. Otherwise proceed normally from Phase 1 Step C
</Mid_Conflict_Re_Entry>

<Configuration>
**Environment variables** (all optional):
- `RESOLVE_CONFLICTS_NONINTERACTIVE=1` — defer all ASKs to `.conflicts/pending-review.md`; never block
- `RESOLVE_CONFLICTS_FORCE_MERGE=1` — skip Phase 0 advisory; always proceed (still backs up deleted-modified)
- `RESOLVE_CONFLICTS_PREMERGE_ONLY=1` — run only Phase 0 against simulated `git merge-tree`; never touches working tree
- `RESOLVE_CONFLICTS_CONFIDENCE_THRESHOLD=0.7` — Phase 4 auto-resolve threshold (0.0–1.0)
- `RESOLVE_CONFLICTS_DOOMED_FILE_COUNT=20` — Phase 0 conflict-count threshold
- `RESOLVE_CONFLICTS_DOOMED_DM_COUNT=3` — Phase 0 deleted-modified-count threshold
- `RESOLVE_CONFLICTS_INFLIGHT_DOOMED_ASK_COUNT=5` — Phase 4 ASK count that triggers in-flight Phase 0 re-evaluation
- `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1` — let downstream commit skill commit even when verification was skipped (Tier 7)
- `RESOLVE_CONFLICTS_AUTO_ACT_ADVISORY=1` — in non-interactive mode, automatically follow Phase 0 strategy advisory (e.g., abort and switch to rebase)

**`.omc/resolve-conflicts.json`** (optional, repo-local config):
```json
{
  "verify": "vp test --changed && vp staged",
  "verify_scope": "changed-files",
  "regenerators": {
    "**/routeTree.gen.ts": "vp run dev --no-open --build-only",
    "**/schema.gen.ts": "pnpm db:generate",
    "package-lock.json": "npm install",
    "pnpm-lock.yaml": "pnpm install --frozen-lockfile=false",
    "yarn.lock": "yarn install"
  },
  "confidence_weights": {
    "line_overlap": 0.40,
    "contradiction": 0.30,
    "touched_symbol": 0.20,
    "upstream_context": 0.10
  },
  "inflight_doomed_ask_count": 5
}
```
</Configuration>

<Tool_Usage>
The executing agent uses standard git plumbing — no shell scripts ship with this skill:
- `git status --short` — quick state check
- `git ls-files -u` — list unmerged files with their stage info
- `git diff --name-only --diff-filter=U` — list conflicted paths
- `git log -p --reverse {base}..{other} -- {path}` — load upstream context
- `git show :1:{path}` / `:2:{path}` / `:3:{path}` — read base / ours / theirs versions
- `git merge-tree --write-tree {HEAD} {other}` — simulate merge for `PREMERGE_ONLY` mode
- `git merge --abort` / `git rebase --abort` / `git cherry-pick --abort` — undo in-progress integration
- `git check-ignore {path}` — verify `.gitignore` is taking effect
- `git add {path}` — stage resolved files

File ops via Read, Write, Edit, Bash. Project-specific commands (regenerators, verification) discovered per `references/verification.md`.
</Tool_Usage>

<Examples>
<Good>
**Union of imports (Phase 3, AC7)**:
Both sides added new imports at the top of `src/auth.ts`. HEAD added `import { jwt } from 'jsonwebtoken'`; other-side added `import { z } from 'zod'`. Resolution: union both, dedupe none, output:
```ts
import { jwt } from 'jsonwebtoken';
import { z } from 'zod';
```
No prompt. Logged: `src/auth.ts — class: imports, method: union, lines_a: 1, lines_b: 1, lines_out: 2`.
</Good>

<Good>
**Regenerate routeTree.gen.ts (Phase 2, AC2)**:
`packages/app/src/routeTree.gen.ts` has 200 lines of conflict markers. Class: `generated` (matches glob `**/routeTree.gen.ts` per file-classes.md). Resolution: `rm packages/app/src/routeTree.gen.ts && cd packages/app && vp run dev --no-open --build-only` (regenerator from config), stage. No hand-merging. Logged: `class: generated, method: regenerate, command: vp run dev --no-open --build-only`.
</Good>

<Good>
**Asking on logic conflict (Phase 4, AC8)**:
`packages/api-core/src/handlers/orders.ts` has a code-logic conflict around the discount calculation. Confidence rubric scores: line-overlap 0.3, contradiction 0.2, touched-symbol 0.0 (both sides modified `applyDiscount()`), upstream-context 0.4 (commit `a1b2c3d` "refactor: discount logic" in upstream). Weighted score: 0.3×0.4 + 0.2×0.3 + 0.0×0.2 + 0.4×0.1 = 0.22. Below 0.7 threshold → ASK with options (1) take HEAD, (2) take upstream refactor, (3) propose merged version, (N) abort merge and request human review.
</Good>

<Good>
**Doomed-merge advisory (Phase 0, AC5)**:
Detected 47 conflicted files and 5 deleted-modified pairs after attempting `git merge feature/big-refactor`. Both thresholds tripped (>20 files OR >3 dm). Phase 0 advisory recommends `split-then-merge`: "the upstream branch contains both a structural rename and unrelated logic changes — split the rename into its own commit, merge that first, then merge the remaining changes." Auto-act in non-interactive mode if `RESOLVE_CONFLICTS_AUTO_ACT_ADVISORY=1`; otherwise ASK or defer.
</Good>

<Good>
**Deleted-modified backup (Phase 1, AC1)**:
`docs/old-readme.md` deleted on HEAD, modified on other-side (added a section about the new feature). Phase 1: `.conflicts/.gitignore` written first. `.conflicts/backups/2026-04-20T15-22-09Z-docs--old-readme.md` written. `.conflicts/analysis-2026-04-20T15-22-09Z.md` records: HEAD deleted (43 lines removed), other-side modified (+18 lines, in section "Quick Start"). Marked ASK-pending. NOT resolved in Phase 1 — passed to Phase 4 with class `code-logic` and the deleted-modified flag.
</Good>

<Bad>
**Picking one side without union**:
Both sides added test cases to `auth.test.ts`. Bot picked HEAD (only its tests survived), losing 3 new test cases from upstream. AC7 violation — should have UNION'd.
</Bad>

<Bad>
**Hand-merging package-lock.json**:
Bot edited 1200 lines of pnpm-lock.yaml conflict markers manually. Result: lockfile drift, broken dependency resolution. AC2 violation — should have `rm pnpm-lock.yaml && pnpm install`.
</Bad>

<Bad>
**Committing without verify**:
Bot resolved 8 conflicts, ran `git commit -m "merge"`, didn't run typecheck. Compilation broke on the next CI run. AC4 violation — Phase 5 verification was skipped without setting the `verification: skipped` flag.
</Bad>

<Bad>
**Pushing through 30 conflicts without checking strategy**:
Bot ran through 30 file conflicts via merge, took 6 hours, ended up with 14 ASK-prompts. The right answer was to abort and rebase. AC5 violation — Phase 0 advisory should have fired at the start; AC-P3 in-flight re-evaluation should have fired after the 6th Phase 4 ASK.
</Bad>
</Examples>

<Escalation_And_Stop_Conditions>
- **Phase 0 thresholds tripped**: emit strategy advisory; ASK in interactive, defer in non-interactive (or auto-act if `RESOLVE_CONFLICTS_AUTO_ACT_ADVISORY=1`)
- **Non-interactive mode + ASK needed**: defer to `.conflicts/pending-review.md`, continue with most-conservative resolution (skip + mark pending), never block
- **Verification failure (Phase 5)**: do NOT proceed to Phase 6; ASK or defer; never auto-revert resolutions
- **Phase 4 ASK count exceeds threshold**: re-trigger Phase 0 advisory mid-flight (AC-P3)
- **Phase 1 Step B fails (`.gitignore` not effective)**: abort with explicit error; refuse to write any backups
- **`git check-ignore` not available** (extremely old git): warn, write `.gitignore` anyway, proceed; document risk in `resolution-log.md`
- **Mid-conflict state ambiguous** (multiple HEAD files): apply precedence REBASE > CHERRY_PICK > MERGE per references/strategies.md
</Escalation_And_Stop_Conditions>

<Final_Checklist>
Each item cites the section that enforces it. A reviewer can verify the SKILL.md by walking this list.

- [ ] **AC1** — Deleted-modified backup-then-ask: `Phase 1` Steps A–D; never Phase 1 auto-resolves
- [ ] **AC2** — File-class classification before resolution: `Phase 2` and `Phase 3` both call out `references/file-classes.md`; Phase 4 also classifies
- [ ] **AC3** — Upstream context loaded for code-logic: `Phase 4` step 1 (`git log -p ...`)
- [ ] **AC4** — Post-resolution verification + skip-flag: `Phase 5` writes `verification:` field; skipped requires `RESOLVE_CONFLICTS_ALLOW_UNVERIFIED=1`
- [ ] **AC5** — Doomed-merge detection BEFORE Phase 1: `Phase 0` runs first; thresholds in `Configuration`
- [ ] **AC6** — Mid-conflict re-entry with precedence: `Mid_Conflict_Re_Entry` cites `references/strategies.md § Mid-Conflict Re-Entry`
- [ ] **AC7** — UNION default; single canonical "directly contradicts" definition: `Execution_Policy` + `references/strategies.md § UNION vs CHOOSE`
- [ ] **AC8** — Confidence scoring with re-normalization: `Phase 4` step 2; defaults in `Configuration`; rubric in `references/strategies.md § Confidence Scoring`
- [ ] **AC9** — Composability with handoff contract: `Phase 6` (non-interactive auto-invokes `commit-commands:commit --non-interactive`; interactive emits "ready to commit"); never authors commit message
- [ ] **AC10** — Skill placement + frontmatter: this file at `.claude/skills/resolve-conflicts/SKILL.md` (project-local) symlinked from `~/.codex/skills/resolve-conflicts`; frontmatter has `name` and `description`
- [ ] **AC-P1** — Each AC verifiable by reading SKILL.md: this checklist itself
- [ ] **AC-P2** — Confidence weights configurable: `Configuration` `.omc/resolve-conflicts.json` `confidence_weights` key
- [ ] **AC-P3** — In-flight doomed-merge re-evaluation: `Execution_Policy` bullet + `Phase 4` step 5
</Final_Checklist>

<Composes_With>
- **`commit-commands:commit`** — receives the staged index from Phase 6, authors the merge commit message
- **`engram-commit-hygiene`** — provides commit message standards for the downstream commit
- **`modern-git`** — reference for advanced git workflows (rebase, worktree, rerere) the executing agent may need
- This skill does NOT replace any of the above — it produces a clean staged index and hands off
</Composes_With>

<Advanced>
**Routing Phase 4 ASKs through the consensus loop instead of a human**:
For agent-fleet operation where you want adversarial review of low-confidence resolutions instead of human prompts, set `RESOLVE_CONFLICTS_NONINTERACTIVE=1` AND configure a wrapper that reads `.conflicts/pending-review.md` and dispatches each entry to `omc-plan --consensus` (Planner proposes a resolution, Architect challenges, Critic validates). The wrapper writes the consensus resolution back to the working tree and re-runs Phase 5. This is documented as an integration pattern; the wrapper itself is out of scope for this skill.

**Future split into `choose-integration-strategy`**:
Phase 0's contract (input/output schema documented in `Phase_0_Strategy_Advisory`) is intentionally stable so that a future `choose-integration-strategy` skill can be extracted without breaking changes. The extraction would: (a) move Phase 0 to the new skill, (b) have `resolve-conflicts` invoke the new skill at the start of each run, (c) keep `RESOLVE_CONFLICTS_PREMERGE_ONLY=1` as a passthrough for backward compatibility.

**Multi-repo workflows**:
For monorepo workspaces (pnpm, yarn, cargo), the verification command discovered in Phase 5 MUST be scoped to the workspace package(s) containing touched files — see `references/verification.md` § Monorepo Scoping. Running verification at repo root in a large monorepo can OOM (e.g., webfront's `vp check` at root).
</Advanced>
