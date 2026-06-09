# Strategies

Algorithms and templates referenced from `SKILL.md`. Read the section cited from each Phase.

---

## Doomed-Merge Detection (Phase 0)

Phase 0 inspects the working tree state immediately after a merge/rebase/cherry-pick produces conflicts (or, in `RESOLVE_CONFLICTS_PREMERGE_ONLY=1` mode, the simulated `git merge-tree` output) and decides whether to proceed.

### Inputs

- `conflict_count` — `git diff --name-only --diff-filter=U | wc -l`
- `deleted_modified_count` — number of paths that appear with stage 1 + only stage 2 OR only stage 3 in `git ls-files -u`
- `conflict_paths` — full list, used to detect "structural sweep" patterns (e.g., 90% of conflicts in `migrations/` indicates a rebase would be cleaner than a merge)
- `strategy_in_progress` — `merge` | `rebase` | `cherry-pick` | `null` (pre-merge mode)

### Threshold rule

If `conflict_count >= RESOLVE_CONFLICTS_DOOMED_FILE_COUNT` (default 20)
OR `deleted_modified_count >= RESOLVE_CONFLICTS_DOOMED_DM_COUNT` (default 3),
emit a Strategy Advisory.

Both thresholds together do NOT raise the bar — either-or, because either signal alone is enough to suggest a structural problem with the chosen integration approach.

### Strategy Advisory Templates

#### Template: `rebase`
> The branch `{other}` has diverged enough from `{HEAD}` that a merge produces {N} conflicts. Many of these may be the same upstream change conflicting with itself across multiple of your commits. **Recommendation**: `git merge --abort && git rebase {other}`. Resolving conflicts once per upstream commit (rebase) is usually less work than resolving them all at once (merge), and produces a linear history.

When to use this advisory: high `conflict_count` (>20) AND `deleted_modified_count` is low (≤2) AND `strategy_in_progress == "merge"`.

#### Template: `cherry-pick-subset`
> The conflict shape suggests `{other}` contains MORE changes than you actually need. Of the {N} commits since merge-base, only {M} touch files relevant to `{HEAD}`. **Recommendation**: `git merge --abort` and cherry-pick only the relevant commits with `git cherry-pick {commit-range}`. Identify the relevant commits via `git log --oneline {merge-base}..{other} -- {paths-of-interest}`.

When to use this advisory: high `conflict_count` AND most conflicts are in files unrelated to your current branch's work (heuristic: > 60% of conflict paths are NOT in the same top-level dirs as your branch's recent commits).

#### Template: `split-then-merge`
> The branch `{other}` mixes a structural rename/refactor with unrelated changes. Most of the {N} conflicts are caused by the structural change colliding with your work in different files than the refactor itself. **Recommendation**: `git merge --abort`. Ask the upstream maintainer to split the structural change into its own PR. Merge that first, then merge the rest.

When to use this advisory: high `deleted_modified_count` (>3) AND a separable cluster of "all-rename" file paths is detectable in the conflict set.

#### Template: `abort-and-restart`
> The current strategy has accumulated {N} conflicts and {M} deleted-modified pairs. No simpler alternative looks better from the conflict shape alone. **Recommendation**: `git merge --abort` (or rebase/cherry-pick equivalent) and consult a human about how to proceed.

When to use: thresholds tripped but none of the other three templates fits cleanly.

---

## Phase 0 Contract (B2 seam)

Stable contract so a future `choose-integration-strategy` skill can extract Phase 0 without breaking changes:

**Input**:
```
{
  conflict_count: int,
  deleted_modified_count: int,
  conflict_paths: string[],
  strategy_in_progress: "merge" | "rebase" | "cherry-pick" | null
}
```

**Output**:
```
{
  recommendation: "proceed" | "rebase" | "cherry-pick-subset" | "split-then-merge" | "abort-and-restart",
  rationale: string,
  advisory_md: string  // formatted markdown using one of the templates above
}
```

When the future skill is extracted, `resolve-conflicts` will call it as a subroutine at the start of each run; `RESOLVE_CONFLICTS_PREMERGE_ONLY=1` will pass through to the subroutine and short-circuit.

---

## In-flight Doomed-Merge Re-evaluation (AC-P3)

A merge can look tractable at the conflict-count level but still be doomed: if Phase 4 produces many low-confidence asks, the upstream branch's logic is too entangled with HEAD's logic for clean resolution.

**Trigger**: Phase 4 ASK counter exceeds `RESOLVE_CONFLICTS_INFLIGHT_DOOMED_ASK_COUNT` (default 5) during a single session.

**Action**:
1. Re-compute Phase 0 inputs against the current state (some conflicts may have been resolved, but unresolved + asked count toward the new total)
2. Re-emit the Strategy Advisory with a fresh recommendation. Insert at the top of `.conflicts/resolution-log.md` and (if interactive) prompt the user/agent.
3. The user/agent may choose to abort and restart, OR continue with the existing strategy.

The skill does NOT auto-abort even if the in-flight re-evaluation says "abort and restart" — that decision is reserved for the user (or `RESOLVE_CONFLICTS_AUTO_ACT_ADVISORY=1`).

---

## Confidence Scoring (Phase 4)

The C1+C2 hybrid rubric: C1 produces a deterministic 0–1 score from 4 signals, then C2 lets the agent adjust ±0.1 with explicit rationale. The result is compared against `RESOLVE_CONFLICTS_CONFIDENCE_THRESHOLD` (default 0.7).

### The 4 Signals

#### Signal 1: Line-overlap (default weight 40%)

**Question**: Is one side's change a strict superset of the other?

**Computation**:
- Let `a_lines` = unique lines in HEAD's version of the conflict block
- Let `b_lines` = unique lines in other-side's version
- `overlap_ratio = |a_lines ∩ b_lines| / max(|a_lines|, |b_lines|)`
- Score: if `overlap_ratio > 0.7` → **1.0** (one side mostly extends the other; UNION is safe). Else: linear scale `overlap_ratio` (e.g., 0.4 → score 0.4).

#### Signal 2: Contradiction (default weight 30%)

**Question**: Do both sides assign different values to the same identifier within the conflict block?

**Computation**:
- Tokenize each side. Find identifiers that appear on both sides as the LHS of an assignment-like construct: `=`, `:`, `:=`, `let`, `const`, `var`, `func`, `def`, `class`, etc. (language-aware list).
- Let `contradicting_count` = number of identifiers where both sides have an LHS occurrence with different RHS tokens.
- Score: if `contradicting_count == 0` → **1.0** (no contradiction; safe). Else: `1.0 - min(0.2 * contradicting_count, 1.0)` (each contradiction subtracts 0.2; ≥5 contradictions → score 0.0).

#### Signal 3: Touched-symbol (default weight 20%)

**Question**: Do both sides modify the same symbol (function, class, method)?

**Computation**:
- Identify the enclosing symbol(s) for the conflict block via tree-sitter, OR via simple bracket-depth tracking for curly-brace languages, OR via indent-block tracking for Python.
- If both sides' edits are inside the same symbol: score 0.0 (they're contending for the same logical unit).
- If edits are in different symbols (or no symbol context, e.g., top-level constants): score 1.0.

**Graceful degradation**: if neither tree-sitter nor a fallback can determine the symbol (e.g., language has no clear symbol structure, or the conflict block isn't inside any symbol), this signal is **unavailable**. Re-normalize the remaining 3 signal weights to sum to 1.0 (40/30/0/10 → 50/37.5/12.5; 0.4/0.8 = 0.5, etc.) and log the skipped signal in the rationale.

#### Signal 4: Upstream-context (default weight 10%)

**Question**: Does the upstream branch contain a recognizable refactor that touches these lines?

**Computation**:
- Run `git log -p --reverse {merge-base}..{other-side} -- {path}` (already done in Phase 4 step 1).
- Look for commits whose message contains keywords: `refactor`, `rewrite`, `restructure`, `migrate`, `extract`, `inline`, `rename`.
- If such a commit touches the conflict's line range: score 0.5 (the resolution depends on understanding the refactor — proceed cautiously).
- If no such commit, but other commits modified the lines: score 0.7.
- If no upstream commits touched the lines (the conflict is purely on HEAD's side): score 1.0.

### Computing the score

```
weights = config.confidence_weights or default {line_overlap: 0.40, contradiction: 0.30, touched_symbol: 0.20, upstream_context: 0.10}

# Re-normalize if any signal is unavailable
available = [s for s in signals if s.available]
total_weight = sum(weights[s.name] for s in available)
normalized = {s.name: weights[s.name] / total_weight for s in available}

c1_score = sum(s.value * normalized[s.name] for s in available)

# C2 layer: agent may adjust ±0.1 with explicit rationale
c2_adjustment = agent.adjust(c1_score, conflict_block, upstream_context)  # in [-0.1, +0.1]
final_score = clamp(c1_score + c2_adjustment, 0.0, 1.0)

# Decide
if final_score >= threshold:
    auto_resolve(rationale=f"score {final_score:.2f} ≥ threshold {threshold}; signals: {signals}")
else:
    ask_or_defer(rationale=f"score {final_score:.2f} < threshold {threshold}; signals: {signals}")
```

### Worked Examples

**Example A: high confidence**
- Conflict in `src/utils/dates.ts` — both sides added a new export at the bottom of the file; HEAD added `export function startOfWeek()`, other-side added `export function startOfMonth()`.
- Signals: line-overlap=1.0 (no shared lines, both pure-add), contradiction=1.0 (no LHS contradiction), touched-symbol=1.0 (different symbols), upstream-context=1.0 (no upstream commit touched these lines).
- C1 score: 1.0×0.40 + 1.0×0.30 + 1.0×0.20 + 1.0×0.10 = **1.0**
- C2 adjustment: 0 (no nuance to add).
- Final: 1.0 → auto-resolve via UNION. Rationale logged.

**Example B: low confidence**
- Conflict in `packages/api-core/src/handlers/orders.ts` around `applyDiscount()`. Both sides modified the same function body.
- Signals: line-overlap=0.3 (some shared, mostly different), contradiction=0.2 (`discountRate` assigned different values on each side), touched-symbol=0.0 (both inside `applyDiscount`), upstream-context=0.4 (commit `a1b2c3` "refactor: discount logic" in upstream).
- C1 score: 0.3×0.40 + 0.2×0.30 + 0.0×0.20 + 0.4×0.10 = **0.22**
- C2 adjustment: -0.05 ("the upstream refactor changes the discount semantics; conservative resolution requires human judgment").
- Final: 0.17 → ASK with options.

**Example C: graceful degradation (Python project, no tree-sitter)**
- Conflict in a Python file; symbol detection unavailable.
- Available signals: line-overlap=0.6, contradiction=0.8, upstream-context=1.0. Touched-symbol skipped.
- Re-normalize: total of remaining = 0.40 + 0.30 + 0.10 = 0.80. Normalized: 0.50/0.375/0.125.
- C1 score: 0.6×0.50 + 0.8×0.375 + 1.0×0.125 = **0.725**
- Above threshold 0.7 → auto-resolve. Rationale: "touched-symbol signal unavailable (Python without tree-sitter); re-normalized weights 0.50/0.375/0.125."

---

## UNION vs CHOOSE

The single canonical definition of `directly contradicts` (used by Phase 3, Phase 4, AC7):

> **Two conflict-block sides directly contradict if and only if: the same identifier appears on both sides as the left-hand side of an assignment, declaration, or definition, AND the right-hand side differs.** Adjacency-line heuristics (e.g., "within ±2 lines") are NOT part of this definition.

Examples:

| HEAD | Other-side | Contradicts? |
|------|-----------|--------------|
| `const x = 1` | `const x = 2` | YES (same `x`, different RHS) |
| `const x = 1` | `const y = 2` | NO (different identifiers) |
| `import { a } from 'x'` | `import { b } from 'x'` | NO (additive — UNION the specifiers) |
| `function foo() { return 1 }` | `function foo() { return 2 }` | YES (same `foo`, different body) |
| `<div className="a">` (line 5) | `<div className="b">` (line 5) | YES (same JSX prop, different value) |
| New line at line 10: `console.log('a')` | New line at line 10: `console.log('b')` | NO (no LHS — both are pure additions; UNION) |
| `port: 3000` (yaml, top-level) | `port: 4000` | YES |
| `host: localhost` | `database: postgres` | NO (different keys; UNION) |

**Rule**: when in doubt, UNION. The cost of an incorrect UNION (extra noise) is lower than the cost of an incorrect CHOOSE (silent data loss).

---

## Mid-Conflict Re-Entry

State detection table:

| State file present | Operation in progress |
|--------------------|----------------------|
| `.git/REBASE_HEAD` OR `.git/rebase-merge/` OR `.git/rebase-apply/` | rebase |
| `.git/CHERRY_PICK_HEAD` | cherry-pick |
| `.git/MERGE_HEAD` | merge |

**Precedence when multiple are present** (rare but possible if a previous operation crashed without cleanup):

> **REBASE > CHERRY_PICK > MERGE**

If `.git/REBASE_HEAD` exists, treat as rebase regardless of other markers. This precedence is cited from SKILL.md § Mid-Conflict Re-Entry as the authoritative rule for AC6.

**Re-entry behavior**:
1. If `.conflicts/.gitignore` already exists with the correct content (`*\n!.gitignore`), skip Phase 1 Steps A/B (don't re-write)
2. Re-derive Phase 0 strategy advisory from the current state (an in-progress operation may have become doomed since the last check — e.g., the user resolved 3 files manually but discovered 5 more in the process)
3. Continue from Phase 1 Step C onward

---

## Force-Merge Override

`RESOLVE_CONFLICTS_FORCE_MERGE=1` skips Phase 0's strategy advisory (no abort recommendation, even if thresholds tripped). All other phases still run normally.

**What still happens**: Phase 1 still backs up deleted-modified pairs. Phase 4 confidence scoring still runs. AC-P3 in-flight doomed-merge re-evaluation may still fire mid-Phase-4 (the user can opt out of in-flight by also setting `RESOLVE_CONFLICTS_INFLIGHT_DOOMED_ASK_COUNT=999`).

**When to use**: when the user has independently decided that the current strategy is correct despite the conflict shape, and wants to push through.
