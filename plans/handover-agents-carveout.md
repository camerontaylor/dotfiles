# Handover: fleet consolidation Phase 1 — agents carve-out

Date: 2026-09-08. Author: Claude (fable), with owner (Cameron) decisions.
Implementer: astra (codex). Status: authorized to implement **on a branch**;
merge/deploy authority stays with the owner.

## What this is

Begin executing `docs/fleet-consolidation.md` (read it first — it is the
direction document; owner decisions are recorded in it). This phase covers:
the placement-policy adoption (M1), the **agents-repo carve-out** (owner
confirmed 2026-09-08: agent setup becomes its own repo — it is conceptually
distinct from dotfiles and carves out some of dotfiles' messiest parts), and
two retirements (litellm, webfront docs-side). Nothing else: M2–M6 are out of
scope.

Required reading before any edit, in order:

1. `CLAUDE.md` — the dual-shell/BSD portability rules are **binding** for
   everything under `scripts/`, `zsh/`, `bash/`, `bin/`, both drivers.
2. `docs/fleet-consolidation.md` — direction, placement tree, the
   agents-repo line and its two guardrails.
3. `docs/fleet-census-units.md` + `docs/fleet-census-installers.md` —
   file:line evidence for everything you'll touch.
4. `AGENTS.md:134-149` (carve-out triple convention) and
   `specs/split-infrastructure-out-of-dotfiles-spec.md` — the approved split
   contracts. The sibling order is dotfiles → secrets → infra → agents, with
   tolerated sibling absence. **Follow these conventions; do not invent new
   ones. If this handover conflicts with them, follow them and flag the
   conflict in your report.**
5. `~/.local/infra/deploy` — the house pattern for a sibling repo's deploy
   (deploy_ln symlinks, warn-not-fail, human-only enablement). Mirror it.

## Hard rules

- **Worktree only.** You are already inside a Paseo-managed worktree of
  dotfiles on branch `agents-carveout` (your cwd). All dotfiles changes
  happen here. The main checkout at `~/.local/dotfiles` belongs to other
  live sessions — read-only reference at most; never edit, commit, or run
  anything mutating there. Never commit to main; never merge; you may push
  the `agents-carveout` branch, never main.
- **Never run `./deploy.zsh` / `./deploy.bash` against the live home.**
  `--dry-run` only. The fleet auto-pulls main — that is why main stays clean.
- **Secrets:** never read `~/.local/secrets`, never commit plaintext, never
  relocate rendered secret files (e.g. the openclaw-mcp EnvFile is a rendered
  copy — moved configs keep *referencing* rendered paths in place).
- **Concurrent-edit warning:** `scripts/setup-paseo.sh` and
  `configs/ai/codex/config.toml` have uncommitted changes in the main working
  tree from another session. Your worktree branches from HEAD so you won't see
  them — note in your report that the owner must reconcile those edits with
  your move of `setup-paseo.sh` before merging.
- **Dual-shell gates are mandatory evidence**, not suggestions:
  `scripts/tests/shell-syntax-gate.sh --all` must pass in the worktree, and
  `diff <(./deploy.zsh --dry-run) <(./deploy.bash --dry-run)` must be empty
  modulo timestamps, with the dry-run delta vs. pre-change output showing
  only your intended changes.

## Delegation: use claude-zai (GLM-5.3) workers for bulk work

Owner instruction: rely on claude-zai for delegable work (consumer-tracing
sweeps, mechanical file moves' reference audits, drafting) and do the
integration, judgement, and review yourself.

**Primary mechanism — Paseo subagents.** You are a Paseo-managed agent; use
agent-scoped `create_agent` (Paseo MCP) with `provider: "claude-zai/glm-5.3"`,
`settings: { modeId: "auto", thinkingOptionId: "high" }`, one bounded task
per subagent, `notifyOnFinish: true`. Demand file:line citations in every
subagent prompt; spot-check before acting — uncited claims from a cheap
model are the main failure mode.

**Fallback — headless workers**, only if Paseo MCP is unavailable to you.
The `cc*` aliases do NOT exist in non-interactive shells; check
`${Z_AI_API_KEY:+set}` first (the daemon environment may lack it — if unset,
this route is dead, stay with Paseo subagents):

```bash
W=~/.claude/skills/agent-orchestration/scripts/cc-worker.sh   # bash, not zsh
bash $W ccz-direct --tools "Read,Grep,Glob" --cwd <narrowest-dir> \
  --bg /tmp/w-<name>.json --ttl 20m "<task — demand file:line citations>"
bash $W --list    # poll; empty log = still running
bash $W --reap    # when done
```

## Task 1 — placement policy into CLAUDE.md (M1)

Add a short "Where does a new thing go" section to `CLAUDE.md` (≤20 lines):
the decision tree from `docs/fleet-consolidation.md` in compact form plus a
pointer to that doc. Do not duplicate the whole doc.

## Task 2 — bootstrap the agents repo and carve out

Create `~/.local/agents` as a fresh git repo (sibling convention). Give it a
`deploy` modeled on infra's, an `AGENTS.md` stating its scope (the line test:
"if I stopped doing AI-agent work tomorrow, would I still want this?" — no →
belongs here), and a README indexing contents.

Move list (current dotfiles locations; census has deploy-mechanism cites):

| What | From |
|---|---|
| cc*/ccz alias layer | `zsh/env.d/09_claude_code_aliases.zsh`, `scripts/agent-aliases.zsh`, `bin/` cc*/yolo-class wrappers (verify the exact set — trace which bin/ entries are agent-routing) |
| LLM git workflow | `scripts/commit-conventional`, `scripts/generate-commit-msg` |
| paseo | `scripts/setup-paseo.sh`, `scripts/paseo-watchdog` |
| portkey | `configs/ai/portkey/` (incl. its .service) |
| openclaw-mcp | `configs/openclaw-mcp/` |
| codexbar / llm-quota | `configs/ai/codexbar/`, `scripts/setup-llm-quota.sh` |
| codex config | `configs/ai/codex/` |
| ccr-router | `configs/ai/ccr-router/` — move, but flag as retirement candidate (census: unreferenced, stale internal paths) |
| any remaining `configs/ai/*` | assess each against the line test; list your call per item in the report |

For **every** moved file, first delegate a consumer sweep (who references it:
fragments, symlink lines in `scripts/deploy.d/20_symlinks.zsh`, git hooks,
docs, `docs/cli-tools.md`, other scripts), then update every consumer. Known
wiring you must handle:

- `20_symlinks.zsh:133` (portkey unit), `:142-144` (openclaw-mcp, ceres-gated),
  `:152-157` (codexbar set) — these symlink lines move to the agents repo's
  deploy, ceres-gating preserved.
- `generate-commit-msg` may be wired into git hooks/config — trace before
  moving; keep the hook working (indirection is acceptable).
- Shell integration: dotfiles reserves gitignored numbered slots (90–99
  local; 96–99 agents hooks per the split spec). The agents repo's deploy
  drops/links its env fragment (the alias layer) into a reserved slot —
  dotfiles must never source `~/.local/agents` directly. Find the documented
  slot convention in the spec/AGENTS.md and follow it exactly.
- Add a dotfiles fragment `67_agents.zsh` modeled on `66_infra.zsh:76-89`
  (clone/pull sibling, run its deploy, warn-not-fail, absent-sibling
  tolerated) — respecting the C2 order dotfiles → secrets → infra → agents.
- Installation stays with the tool layer: do NOT move any installer logic
  for the agent CLIs themselves (mise/npm entries stay in dotfiles). Config
  only.

The agents repo is new code with no bash-3.2 legacy burden, but its deploy
runs on stock macOS too — stay BSD-clean (CLAUDE.md foot-gun tables apply).

## Task 3 — retirements

- **litellm** (replaced by portkey, owner ruling): delete
  `configs/ai/litellm/` on the branch; do not move it to agents. Record the
  live-ops follow-up in your report: makemake has a dangling
  `~/.config/systemd/user/litellm-proxy.service` symlink to clean, plus any
  host still running the service. **Do not perform live-ops yourself** — no
  ssh'ing to hosts to stop/disable anything.
- **webfront** (retired, owner ruling): dotfiles holds no webfront files
  (compose lives in `~/repos/deploy`, out of scope). Just ensure no dotfiles
  doc/config still points at webfront as live; list what you find.

## Task 4 — report

Write `plans/agents-carveout-report.md` on the branch: what moved (old →
new path), every consumer updated (file:line), per-item calls on the
"assess each" rows, retirement-candidate flags, the live-ops follow-up list
(makemake dangling unit; webfront container/postgres cleanup on ceres; any
litellm remnants), the setup-paseo.sh reconciliation note, verification
evidence (gate output, dry-run diff before/after), and open questions.
Commit everything to the branch with conventional-commit messages.

## Definition of done

Branch `agents-carveout` contains: CLAUDE.md policy section, the carve-out
with all consumers updated, litellm deleted, `67_agents.zsh`, and the report.
`~/.local/agents` exists as a coherent repo with its own deploy. Both gates
pass; dry-run diff shows only intended deltas. Nothing merged, nothing
deployed, no live host mutated.
