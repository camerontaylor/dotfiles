---
name: agent-orchestration
description: Delegate work to other CLI agents — headless Claude Code workers on alternate model routes (ccz-direct/GLM, ccx-direct/ox-alpha, ccd-direct/DeepSeek, cc/Anthropic), codex, gemini, or other live Claude sessions. Use when asked to fan out work, run a survey/draft cheaply, "use ccz for this", delegate to a cheaper model, run agents in parallel/background, or orchestrate multiple CLIs.
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Agent orchestration

Delegate work to a *separate process* — a Claude Code worker on a different model route, another CLI agent, or another live session — instead of doing it in this context.

## Choose the mechanism first

| Situation | Use | Why |
|---|---|---|
| Read-heavy search/analysis, result summarised back | in-session subagent (`Agent` tool) | no process overhead, cheapest |
| Bulk survey/draft where a cheap model suffices | **`cc-worker.sh ccz-direct`** | GLM-5.3 at a fraction of Opus cost |
| Same, on the free trial route | **`cc-worker.sh ccx-direct`** | free until ~2026-08-28; **see data policy below** |
| N independent units of work | `cc-worker.sh ... --bg <log>` per unit | true parallelism, own context each |
| Second opinion from a different model family | `codex mcp-server` MCP, or `codex exec` | different training, different failure modes |
| Something another *live* session already knows | `ListAgents` + `SendMessage` | no re-derivation, no new process |

Agent teams are **deliberately disabled** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "0"` in user settings, 2026-08-21). Don't propose them. Named subagents therefore stay ordinary subagents whose results return to the caller — which is what every recipe below depends on.

Do **not** delegate: single-file edits, sequential work with dependencies, or anything where writing the handover costs more than doing the task.

## The one non-obvious fact

**The `cc*` aliases do not exist in a Bash tool call.** `~/.local/dotfiles/zsh/env.d/09_claude_code_aliases.zsh` opens with `[[ -o interactive ]] || return 0`, so a non-interactive `zsh -c` sees neither `ccz-direct` nor `_ccz-direct`. Verified: `zsh -c 'whence -w ccz-direct'` → `none`.

Three ways in, in order of preference:

1. **`scripts/cc-worker.sh`** (bundled here) — sources `~/.local/dotfiles/scripts/agent-aliases.zsh` and calls `agent_alias_export_env <alias>`, the same source of truth the aliases use. Use this.
2. `CLAUDE_ALIAS_TEST=1 source ~/.local/dotfiles/zsh/env.d/09_claude_code_aliases.zsh` → gives the `_ccz-direct` callable clones.
3. `zsh -ic 'ccz-direct -p "..."'` — works, but pays full interactive rc startup and the terminal-restore wrapper.

## Usage

```bash
W=~/.claude/skills/agent-orchestration/scripts/cc-worker.sh

# survey/draft on GLM-5.3, read-only toolset
zsh $W ccz-direct --tools "Read,Grep,Glob" --cwd /path/to/repo \
  "Survey src/ for every call site of foo(). Cite file:line for each."

# structured result you can parse
zsh $W ccz-direct --tools none \
  --schema '{"type":"object","properties":{"count":{"type":"integer"}},"required":["count"]}' \
  "How many days in a leap year?"

# fan out, then collect
for t in auth billing search; do
  zsh $W ccz-direct --tools "Read,Grep" --cwd "$PWD" --bg "/tmp/w-$t.json" \
    "Audit the $t module for unhandled error paths. Cite file:line."
done
# each --bg call prints {"pid":...,"log":...}; poll until each log is non-empty
```

`--session <uuid>` gives a resumable multi-turn worker. `--append-prompt` adds role framing. `-- <flags>` passes anything else through to `claude`.

## Cost model (measured 2026-08-21, trivial prompt)

The flags matter more than the model. Overhead *before any work happens*:

| Config | Input tokens |
|---|---|
| `claude -p` with default config | 17,414 |
| `--tools "Read,Grep,Glob,Bash"` (wrapper default) | ~3,900 |
| `--tools none` | 1,700–2,000 |
| `+ --system-prompt` (replaces, not appends) | 240 |

Also: **worker `cwd` is not free.** The same call cost 20,597 tokens in `/tmp` vs 23,827 in `~/repos/hart`, because CLAUDE.md auto-discovery loads the repo's context. Point workers at the narrowest useful directory.

## Traps that cost an hour each

- **`--tools ""` fails open.** A shell guard like `[[ -n $tools ]]` drops the flag and the worker silently gets all 26 built-in tools (~15k tokens). `cc-worker.sh` takes `--tools none` for this reason.
- **`--bg` conflicts with `-p`.** Claude Code rejects the combination. `cc-worker.sh --bg <log>` detaches the process itself instead.
- **`--bare` refuses OAuth.** It reads only `ANTHROPIC_API_KEY`/`apiKeyHelper`, so it returns `Not logged in` on subscription auth. Don't reach for it as the "fast path".
- **One base URL, all tiers.** The `-direct` aliases must pin every `ANTHROPIC_DEFAULT_*_MODEL` to one provider's model. `CLAUDE_CODE_SUBAGENT_MODEL=""` means a worker's own subagents inherit its route — a `ccz-direct` worker's subagents are also GLM, not Anthropic.
- **`agent_alias_export_env` omits `ANTHROPIC_MODEL`** for `ccz-direct`/`ccm-direct`/`ccfw-direct`; the interactive alias compensates with an explicit `--model`. `cc-worker.sh` re-adds it per alias. If you bypass the wrapper, pass `--model` yourself.
- **Secrets are inherited, not sourced.** `$Z_AI_API_KEY` etc. reach a Bash tool call only because the session was launched from an interactive shell. Under cron/systemd they are absent and the worker fails on auth. Check with `${VAR:+set}` — never echo the value.
- **Nested workers inherit `bypassPermissions`.** `cc-worker.sh` passes it so workers don't stall on prompts. Scope them with `--tools` and `--cwd`, not with trust.

## Data policy — read before choosing a route

`ccx-direct` (OpenRouter `stealth/ox-alpha`) has prompts and completions **retained by an anonymous provider**. Never point it at personal, court, triage, or inbox data. It is a build-work-only route, free until roughly **2026-08-28**; when `--model stealth/ox-alpha` starts 404ing the trial is over and the aliases should be deleted.

`ccz-direct`, `ccd-direct`, `ccm-direct`, `ccfw-direct` are third-party inference too — apply the same judgement, less severely. Only `cc` is first-party Anthropic.

## Division of labour

Established practice: route bulk research and drafting to `ccz-direct`, then do an active review/consolidation pass on the expensive model. This only works if the handover demands **reviewable output** — citations to `file:line`, a decision log, reversible changes only — so the review pass can audit rather than reconstruct. Write that requirement into the worker's prompt every time.

Judge routes on cost-per-completed-task, not cost-per-token: a cheap model that needs three corrections is not cheap.

## Other CLIs

- **Codex**: cheapest MCP surface available — `codex mcp-server` exposes exactly 2 tools (`codex`, `codex-reply`) for ~616 tokens of schema. Register with `claude mcp add codex -- codex mcp-server`. Compare: `claude mcp serve` exposes 26 tools for ~27k tokens; only use that when a *non-Claude* client needs to call Claude.
- **Local mesh**: `openclaw mcp serve` (9 tools, ~918 tokens) is already registered; `openclaw attach` binds a Claude Code session to a gateway session with scoped tools.
- **Known broken as of 2026-08-21**: `codex exec` fails with `refresh token was already used` (needs `codex logout && codex login`, despite `codex login status` reporting success), and `gemini` has no auth method configured. Check before building either into a pipeline.

See `reference/aliases.md` for the full route roster.

## Before reporting a delegated result

- Did the worker actually exit? A `--bg` log that is empty means still running, not finished.
- Did it cite sources? Uncited claims from a cheap model are the main failure mode.
- Did it write files you did not expect? `cc-worker.sh` runs with `bypassPermissions`; check `git status`.
