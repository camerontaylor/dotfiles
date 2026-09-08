# Handover addendum 1 — resume state and rulings

Date: 2026-09-08 ~14:55 AEST. Author: Claude (fable, dispatcher). Read this
together with `plans/handover-agents-carveout.md` and
`plans/carveout-consumer-traces.md` (commit `fe7f3684`) before resuming.

## Where you are (verified by dispatcher)

Your first run ended mid-flight on a codex usage limit. You left:

- **393 uncommitted entries** in this worktree — a near-complete Task 2/3
  implementation (all of `configs/ai/` deleted, new `67_agents.zsh`, edits to
  `20_symlinks.zsh`, `CLAUDE.md`, `AGENTS.md`, hooks, gate, CI workflow,
  `.gitattributes` deleted).
- `~/.local/agents` fully structured (deploy, configs, scripts, manifests,
  docs, lib, bin, bash) but **zero commits**, 141 pending files.

**Reconcile, don't restart.** Audit your uncommitted work against the
consumer traces (committed after your run; they cite baseline `fa5deb49`),
fix mismatches, then commit in small reviewable conventional-commit chunks —
no mega-commit. Give `~/.local/agents` its initial commits on a `main`
default branch (rename the current empty `agents-carveout` branch there).

## Rulings (owner-sourced, 2026-09-08 conversation — these settle the
conflicts the traces flagged)

1. **Portkey → agents repo.** Owner: "it can be rolled in to the agents
   repo." This overrides the spec's `:54` infra assignment for *file
   ownership*; infra keeps placement/disposition tracking. Note the needed
   spec amendment in your report.
2. **`webfront-root` and `p` do NOT move.** Webfront is retired (owner
   ruling). Leave both untouched in dotfiles; flag them as retirement
   candidates in the report. Deletion is the owner's call, not yours.
3. **Generic bin/ stays.** `bag/fgb/fgd/fgl/lspath/psg` and both
   `agents.slice` cgroup scripts remain in dotfiles (spec constraint 7,
   traces classification). Verify your prior attempt did not move them.
4. **`cc-worker.sh:36` hardcoded path**: after `scripts/agent-aliases.zsh`
   moves, update `~/.claude/skills/agent-orchestration/scripts/cc-worker.sh`
   in place to the new agents-repo path (machine-local file, not in either
   repo) and record the edit in your report.
5. **Live-path transition**: live units on hosts (codexbar timer on ceres,
   portkey unit, paseo watchdog on Macs) exec old dotfiles paths until the
   agents deploy re-links them. Either keep the old paths resolving until
   then, or (preferred) document the exact per-host re-link sequence in the
   report's live-ops section. You still perform **no live-ops**.
6. **The codex git-filter triple** (`.gitattributes:1` +
   `60_git_hooks.zsh:13-23` + `pre-commit:42`) must stay coherent. You
   deleted `.gitattributes` — justify in the report: either the filter
   wiring moves to the agents repo with the codex config, or it is retired
   explicitly. A dangling filter reference breaks every clone.
7. **`81_paseo_providers.zsh` runs on every fleet auto-pull** (traces risk
   item): whatever you did with it, the auto-pull path on main must remain
   working for hosts that have no agents sibling yet — sibling-absence
   tolerance is contract C2.

Everything else in the original handover stands, including both dual-shell
gates and the dry-run diff as required evidence, and the definition of done.
