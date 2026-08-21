# Claude Code routing aliases — worker roster

Source of truth (do not duplicate values here when they change):
- `~/.local/dotfiles/zsh/env.d/09_claude_code_aliases.zsh` — interactive aliases + `_name()` callable clones
- `~/.local/dotfiles/scripts/agent-aliases.zsh` — `agent_alias_define_env` / `agent_alias_export_env`, the programmatic path
- `~/.local/dotfiles/configs/ai/portkey/config.json` — Portkey fleet routes and fallback chains

Both alias files are interactive-only (`[[ -o interactive ]] || return 0`). Only
`scripts/agent-aliases.zsh` is safe to source from a non-interactive shell.

## Direct routes (bypass Portkey, one provider per alias)

| Alias | Provider / base URL | Model tiers | Notes |
|---|---|---|---|
| `cc` / `ccc` | Anthropic (default) | plan default | Unsets every override. Only first-party route. Don't pass `--model` — that's what preserves the 1M-context variant. |
| `ccz-direct` | Z.AI `api.z.ai/api/anthropic` | opus→`glm-5.3`, sonnet/haiku/small-fast→`glm-5-turbo` | The workhorse for bulk survey/draft. `ANTHROPIC_MODEL` unset → pass `--model glm-5.3`. |
| `ccx-direct` / `ccx` | OpenRouter `openrouter.ai/api` | all tiers → `stealth/ox-alpha` | **Free trial, ends ~2026-08-28. Prompts retained by an anonymous provider — build work only, never personal/court/triage data.** |
| `ccd-direct` | DeepSeek `api.deepseek.com/anthropic` | opus/sonnet→`deepseek-v4-pro[1m]`, haiku/subagent→`deepseek-v4-flash` | Only direct route that splits tiers across two models (same base URL serves both). |
| `ccm-direct` | MiniMax `api.minimax.io/anthropic` | all tiers → `MiniMax-M2.7` | `cc-minimax` is the M2.5 backward-compat alias. **Returned `API Error: 402 insufficient balance` on 2026-08-21** — account needs topping up before this route is usable. |
| `ccfw-direct` | Fireworks `api.fireworks.ai/inference` | opus→`kimi-k2p6`, sonnet→`minimax-m2p7`, haiku→`gpt-oss-120b` | Fallback for when Portkey-routed `ccfw` misbehaves. |

## Portkey-routed fleet (gateway on `ceres.webfront.app:8787`)

`ccz`, `ccd`, `ccm`, `ccfw`, `cc-fast` resolve `fleet-*` model names to provider
chains with fallbacks defined in the Portkey config. They need a local Portkey
token (`~/.local/state/portkey/local-api-key`, auto-fetched over SSH from the
gateway host) and use a much shorter `API_TIMEOUT_MS` (75s vs 3000s for direct).

`ccd`/`ccd-haiku` pin `provider.only=["DeepSeek"]` with `allow_fallbacks=false` —
provider isolation over resilience, so `ccd` fails hard when DeepSeek is down.

## `-happy` variants

Every `-direct` alias has a `-happy` twin that launches `happy yolo
--dangerously-skip-permissions` instead of `claude`, for the mobile/Happy
harness. Not useful for headless orchestration — `cc-worker.sh` targets the
plain `claude` binary.

## Shared invariants

- `CLAUDE_CODE_ATTRIBUTION_HEADER=0` everywhere: the per-request billing header
  changes each turn and breaks Anthropic prompt caching (anthropics/claude-code#24168).
- `ENABLE_TOOL_SEARCH=false` on `ccz`/`ccx`/`ccfw` direct routes — non-Anthropic
  models handle deferred tool schemas poorly. Default elsewhere is `auto:5`.
- `CLAUDE_CODE_SUBAGENT_MODEL=""` on direct routes: subagents inherit the parent's
  route rather than falling back to an Anthropic model name the provider can't serve.
- One base URL per process. Every tier must be a model the pinned provider serves;
  a leftover `opus`/`sonnet` alias name from a previous shell will 404.

## Retiring the ox-alpha trial

When `--model stealth/ox-alpha` starts returning 404, delete:
1. the `ccx-direct` / `ccx-direct-happy` / `ccx` aliases and `_ccx-direct*` clones in `zsh/env.d/09_claude_code_aliases.zsh`
2. the `ccx-direct|ccx-direct-happy|ccx)` case in `scripts/agent-aliases.zsh`
3. the `openrouter/stealth/ox-alpha` entry in `openclaw.json`
4. the `ccx-direct` row in this file and the mapping in `scripts/cc-worker.sh`
