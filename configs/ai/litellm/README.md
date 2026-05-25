# LiteLLM Proxy Setup

A local LiteLLM proxy that fronts a multi-provider model fleet (Z.AI, Fireworks,
Cerebras, MiniMax, Anthropic) so Claude Code variants and other Anthropic-API
clients can route via different backends without touching their own configs.

The proxy is **not** the OAuth-Opus path — your real Claude Max subscription
talks to Anthropic directly via `ccc`. The proxy is for the eclectic tier
(GLM, Kimi, MiniMax, Llama, Qwen, gpt-oss).

---

## Layout

```
~/.local/dotfiles/configs/litellm/
├── config.yaml                 ← model_list, router, fallbacks (this dir)
├── proxy_wrapper.py            ← Python entry point; ASGI middleware lives here
├── litellm-proxy.service       ← systemd user unit
└── README.md                   ← this file

# Symlinked into XDG locations by deploy.zsh:
~/.config/litellm/config.yaml   → configs/litellm/config.yaml
~/.config/litellm/proxy_wrapper.py
~/.config/systemd/user/litellm-proxy.service

# State (auto-managed):
~/.local/state/litellm/
├── env                         ← provider API keys, regenerated from shell on `ccl`
├── env.sha1                    ← hash for env-change detection (auto-restart)
├── master-key                  ← stable per-machine proxy auth token
└── proxy.log                   ← stdout+stderr append-mode

# Shell glue (lives in dotfiles zsh):
~/.local/dotfiles/zsh/rc.d/10_litellm.zsh   ← _litellm_ensure_service + ccl/ccfw/ccz/cc-fast functions
```

The systemd unit listens on **port 4199** (not 4000 from the LiteLLM reference
docs). Don't change that without updating the alias functions too.

---

## Quick start

```bash
# First call auto-starts the systemd service, regenerates the env file from
# shell env vars, and waits for liveliness:
ccl -p "hi"

# Other entry points (each is a Claude Code variant pointed at a routing tier):
ccc                    # direct Anthropic OAuth, NO proxy (real Opus quota)
ccl                    # proxy → MiniMax (sonnet/haiku-tier via claude-sonnet-4-6)
ccfw                   # proxy → Fireworks fleet (kimi-k2.6, glm-5.1, etc.)
ccz                    # proxy → Z.AI background tier, single-stream (was: cczbg)
ccz-direct             # direct Z.AI api.z.ai shim, kept as fallback (was: ccz)
cc-fast                # proxy → GLM-4.7 on Cerebras (~3000 t/s foreground)
```

Each has a `-happy` variant that runs `happy yolo --dangerously-skip-permissions`
instead of bare `claude` — same env, different harness.

```bash
# Service control + diagnostics:
ccl-status             # systemctl --user status litellm-proxy
ccl-stop               # stop the service
ccl-log                # tail -f proxy.log
ccl-health             # GET /health/readiness + /health (per-deployment)
ccl-probe MODEL [PROMPT]   # one-shot curl to /v1/messages with a model name
```

---

## Model fleet

Listed by `model_name` (the routing key clients send). Each entry shows the
upstream model, provider, and current health status.

### Anthropic-tier mappings (claude-* names → MiniMax)

These exist so older clients hard-coded to Anthropic model names get routed
somewhere. Sub-agent spawns from Claude Code that ask for "claude-sonnet-4-6"
or similar end up on MiniMax via the proxy.

| `model_name` | Upstream | Provider | Notes |
|---|---|---|---|
| `claude-sonnet-4-6` | `MiniMax-M2.5` | minimax/ | `/health` shows unhealthy (probe path mismatch — actual calls work) |
| `claude-haiku-4-5-20251001` | `MiniMax-M2.5` | minimax/ | Same false-negative pattern |

### Z.AI background tier (single-stream subscription discipline)

`max_parallel_requests: 1` — never hammer concurrently. Subscription saturation
risk if you send parallel requests to a Z.AI Coding Plan key.

| `model_name` | Upstream | Notes |
|---|---|---|
| `glm-5.1-bg` | `glm-5.1` on api.z.ai/api/paas/v4 | 200K context, ~50 t/s reasoning |
| `glm-5-bg` | `glm-5` | |
| `glm-5-turbo-bg` | `glm-5-turbo` | |

`/health` may report these as "Insufficient balance" — that's a probe-vs-real
discrepancy on Z.AI's side. Real `/v1/messages` calls succeed when there's
quota.

### Fireworks fast-frontier (high-RPM metered)

100-400 t/s, mid pricing. Used for the role aliases below.

| `model_name` | Upstream |
|---|---|
| `kimi-k2.6` | `accounts/fireworks/models/kimi-k2p6` (262K ctx) |
| `kimi-k2.5` | `accounts/fireworks/models/kimi-k2p5` |
| `glm-5.1-fast` | `accounts/fireworks/models/glm-5p1` |
| `minimax-m2.7` | `accounts/fireworks/models/minimax-m2p7` |

Note: `minimax-m2.5` on Fireworks is **commented out** — Fireworks doesn't
currently have it in their catalog. Re-enable when they add it.

### Cerebras (~3000 t/s wafer-scale silicon)

Two API keys (`CEREBRAS_FREE_API_KEY` for the free tier, `CEREBRAS_API_KEY`
for paid). All Cerebras models use the `cerebras/` LiteLLM provider prefix
(see Gotcha #1 below).

| `model_name` | Upstream | Tier |
|---|---|---|
| `cerebras-free-8b` | `llama3.1-8b` | free (1M tok/day, 30 RPM) |
| `cerebras-paid-8b` | `llama3.1-8b` | paid (1K RPM, 1M tok/min) |
| `cerebras-free-qwen3-235b` | `qwen-3-235b-a22b-instruct-2507` | free |
| `cerebras-paid-qwen3-235b` | `qwen-3-235b-a22b-instruct-2507` | paid (131K ctx) |
| `cerebras-paid-oss120` | `gpt-oss-120b` | paid (131K ctx, 40K max output) |
| `cerebras-paid-glm-4.7` | `zai-glm-4.7` | paid — Z.AI GLM 4.7 hosted on Cerebras silicon |
| `glm-4.7-cerebras` | `zai-glm-4.7` | **gate-friendly alias** for the same model — use this from Claude Code |

**Disabled:** `cerebras-free-oss120` and (implicitly) `cerebras-free-glm-4.7`
— Cerebras has a temporary reduction in free-tier rate limits for these two
models. The 404 with `model_not_found` is misleading; the model exists, your
account is eligible, but the rate budget is currently zero. Re-enable in
config.yaml when Cerebras lifts the reduction.

### OpenAI metered (defined, NOT wired)

| `model_name` | Upstream | Notes |
|---|---|---|
| `gpt-5.4-mini-metered` | `gpt-5.4-mini` | Commented out — forward-looking model name, returns 401 (model not in OpenAI's current catalog) |

### Role aliases (what most harnesses actually call)

These are indirection layers. Easy to retune by editing one `litellm_params`
block instead of every alias function.

| Role | Routes to | Used by | Fallback chain |
|---|---|---|---|
| `fleet-opus` | `kimi-k2.6` (Fireworks) | `ccfw` foreground | `glm-5.1-fast` → `minimax-m2.7` |
| `fleet-sonnet` | `glm-5.1-fast` (Fireworks) | `ccfw` sub-agents | `kimi-k2.6` → `minimax-m2.7` |
| `fleet-haiku` | `llama3.1-8b` (Cerebras free) | `ccfw`/`ccz`/`cc-fast` sub-agents | `cerebras-paid-8b` → `minimax-m2.7` |

Why `fleet-` prefix and not bare `opus`/`sonnet`/`haiku`? See Gotcha #2.

---

## Architecture decisions

### Real Opus bypasses the proxy

`ccc` unsets `ANTHROPIC_BASE_URL` and talks to api.anthropic.com directly. Real
Opus stays on your Claude Max subscription quota (OAuth, not API key).

The earlier `claude-opus-4-6` model in this proxy attempted OAuth passthrough
via `forward_client_headers_to_llm_api: true` — it was returning 401 "Invalid
bearer token" because LiteLLM 1.82.x normalizes incoming `x-api-key` to
`Authorization: Bearer` for the Anthropic provider, which Anthropic OAuth
rejects. Removed; bypass-for-Opus is the chosen architecture.

### Auth uses `x-litellm-api-key` (not `Authorization`)

`general_settings.litellm_key_header_name: "x-litellm-api-key"` lets the proxy
authenticate via a non-default header so `x-api-key` stays free for any future
OAuth-passthrough model. Aliases set the header via:

```bash
ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer $master_key"
```

The `Bearer ` prefix is required by LiteLLM's auth path even though the header
name is custom — easy to miss in the docs.

### Role aliases use `fleet-` prefix

Claude Code does **client-side model name classification** before sending the
request. Names that look like Anthropic tiers (`opus`, `sonnet`, `haiku`)
trigger a subscription check. `fleet-opus`/`fleet-sonnet`/`fleet-haiku` pass
because they contain Anthropic tier substrings AND are recognized as proxy
indirection. Bare `opus` would trigger "Claude Opus is not available with the
Claude Pro plan" before the request reaches the proxy.

### `cc-fast` uses `glm-4.7-cerebras`, not `cerebras-paid-glm-4.7`

Same upstream model, two `model_name` entries. Why?

Claude Code's `--model` validation rejects names starting with `cerebras-`.
Direct curl / `ccl-probe cerebras-paid-glm-4.7` works fine because there's no
client-side gate. But `claude --model cerebras-paid-glm-4.7` 400s with "may
not exist or you may not have access".

`glm-4.7-cerebras` (with `glm-` prefix matching the existing `glm-5.1-bg` /
`glm-5.1-fast` pattern) passes the classifier. Both entries point at the same
`cerebras/zai-glm-4.7` upstream — pick `cerebras-paid-glm-4.7` for direct
curl, `glm-4.7-cerebras` for `claude --model`.

### `cc-fast` only uses GLM-4.7 in the FOREGROUND

Sub-agent spawns and tier-routed requests use the regular fleet via:

```
ANTHROPIC_DEFAULT_OPUS_MODEL=fleet-opus
ANTHROPIC_DEFAULT_SONNET_MODEL=fleet-sonnet
ANTHROPIC_DEFAULT_HAIKU_MODEL=fleet-haiku
ANTHROPIC_SMALL_FAST_MODEL=fleet-haiku
```

GLM-4.7 is fast and cheap but not what you want background agents falling
back to. The split keeps interactive turns blazing while keeping sub-agent
behavior consistent across `ccfw`/`ccz`/`cc-fast`.

---

## The Anthropic-field-strip middleware

`proxy_wrapper.py` registers a pure ASGI middleware
(`StripUnsupportedAnthropicParamsMiddleware`) that drops top-level fields from
incoming `/v1/messages` request bodies before LiteLLM's adapter sees them.

**Currently strips:** `output_config`, `thinking`, `anthropic_version`,
`metadata`, `stream_options`, `reasoning`. All are Anthropic-format fields
that LiteLLM's `/v1/messages` adapter forwards verbatim to non-Anthropic
upstreams. Strict providers like Cerebras 400-reject; lenient providers
(MiniMax, Z.AI, Fireworks) ignore them. Stripping is safe across the board
because every `/v1/messages` target in this proxy is non-Anthropic — real
Opus uses `ccc` and bypasses this middleware entirely.

**Why custom middleware (not `drop_params`):** LiteLLM's `drop_params: true`
and `additional_drop_params` are **ineffective on the `/v1/messages`
pass-through path** — see [LiteLLM Issue #22797](https://github.com/BerriAI/litellm/issues/22797)
and [#26241](https://github.com/BerriAI/litellm/issues/26241). The drop logic
runs against OpenAI-supported-params lists, but Anthropic-only fields flow
through a different translation layer that the drop check never sees.

**Pure ASGI, not BaseHTTPMiddleware:** the latter has a long-standing FastAPI
body-modification bug — replacing `request._receive` only works for the first
`Request.body()` call, not for downstream FastAPI dependency-injected
re-reads. Pure ASGI middleware intercepts at the receive callable level
*before* the `Request` object is constructed, which all consumers honor.

### Limits of this middleware (and what to reach for next)

The middleware does **top-level field strips only**. It does not:

- Recursively strip `cache_control` from nested message-content blocks
- Flatten Anthropic content arrays (`{type: "text", text: "..."}`) to plain
  strings (some providers like Cerebras want strings, not arrays)
- Convert top-level `system` field to a system message (older OpenAI shape)
- Dedupe `tool_call.id` values (Cerebras enforces uniqueness; Anthropic doesn't)
- Fix lowercase agent/tool names that Cerebras rejects

If/when `cc-fast` (or any Cerebras-routed alias) breaks on tool calls or
multi-turn message arrays, the path forward is a structural transformer.
Two options:

1. **Lift the JS Cerebras transformer from
   [musistudio/llms](https://github.com/musistudio/llms)** (used by
   claude-code-router) and port the ~200 lines to a LiteLLM custom callback
   or extend this middleware. Keeps current infrastructure intact.
2. **Run musistudio/llms as a sidecar service** and point LiteLLM at it as
   the upstream for Cerebras model entries only. Same library, different
   surface — get all of CCR's accumulated provider transformers without the
   CLI baggage.

Defer until something actually breaks; current `cc-fast` usage works.

### Adding a new field to strip

1. Edit `proxy_wrapper.py`, add the field name to `_PARAMS_TO_DROP`:
   ```python
   _PARAMS_TO_DROP = ("output_config", "thinking", ..., "your_new_field")
   ```
2. Restart: `systemctl --user restart litellm-proxy`.
3. Verify in `proxy.log`: lines like `[proxy_wrapper] POST /v1/messages
   stripped=['your_new_field']` confirm it's catching incoming requests.

When LiteLLM fixes the pass-through `drop_params` bug, the entire middleware
can be removed in favor of `additional_drop_params: [...]` in
`litellm_settings`.

---

## The `CLAUDE_CODE_ATTRIBUTION_HEADER=0` env var

Claude Code 2.1.36+ sends an undocumented `x-anthropic-billing-header` with
**every request** containing `cc_version=...; cc_entrypoint=...; cch=...;`
where `cch` changes per-request. Anthropic's prompt cache hashes the request
body INCLUDING headers, so this varying value defeats the cache → full prompt
processing on every turn.

Fix: set `CLAUDE_CODE_ATTRIBUTION_HEADER=0` in the env var stack of every
Claude Code invocation. All proxy alias functions in `10_litellm.zsh` and the
direct-provider aliases in `09_claude_code_aliases.zsh` set this. The
worktree mise alias system also injects it into `.env.agent` so background
tasks inherit it.

This was lifted from [anthropics/claude-code#24168](https://github.com/anthropics/claude-code/issues/24168)
— undocumented but stable. Worth setting unconditionally; meaningful savings
when 40+ agent processes are hammering the cache.

---

## Gotchas

### #1: Use the `cerebras/` provider prefix for Cerebras models

```yaml
# WRONG — LiteLLM routes to upstream /v1/responses (Cerebras 404s)
- model_name: foo
  litellm_params:
    model: openai/llama3.1-8b
    api_base: https://api.cerebras.ai/v1
    api_key: os.environ/CEREBRAS_API_KEY

# RIGHT — LiteLLM routes to /v1/chat/completions
- model_name: foo
  litellm_params:
    model: cerebras/llama3.1-8b
    api_key: os.environ/CEREBRAS_API_KEY
```

The `openai/` provider with a Cerebras `api_base` works for the
`/v1/chat/completions` endpoint but breaks on `/v1/messages` (Anthropic-format)
incoming requests because LiteLLM's adapter picks the wrong upstream endpoint
based on provider prefix.

### #2: Claude Code's --model gate is real but reactive, not pre-flight

When `claude --model X -p ...` returns "may not exist or you may not have
access," it can mean:
- The proxy returned a 4xx for the actual request (most common — check proxy.log)
- The model-name classifier rejected it (less common — check if name starts
  with a recognized provider pattern: `glm-`, `kimi-`, `MiniMax-`, `claude-`,
  or contains `opus`/`sonnet`/`haiku`)

It does NOT mean Claude Code has a hard-coded model allowlist — it sends the
request and reactively errors based on the response.

### #3: `/health` probes are unreliable for some providers

LiteLLM's `/health` endpoint always probes via `/chat/completions`. For models
whose `api_base` points at `/v1/messages` (e.g., MiniMax claude-* mappings),
the probe always 404s even though real `/v1/messages` calls succeed. False
negatives are normal — verify with `ccl-probe MODEL` or `claude --model MODEL
-p hi` instead.

Z.AI also returns "Insufficient balance" for `/health` probes when real calls
succeed — same probe-vs-real discrepancy.

### #4: Cerebras free-tier 404s for some models = temporary rate reduction

Cerebras's `/v1/models` endpoint advertises models the free-tier account is
blocked from using. Real `/v1/chat/completions` calls return:

```json
{"message":"Model X does not exist or you do not have access","code":"model_not_found"}
```

This currently affects `gpt-oss-120b` and `zai-glm-4.7` on the free tier
despite docs listing both as free. It's a TEMPORARY reduction per Cerebras
service notice, not a permanent policy or account-state issue. The 404 is
misleading — the model exists, your account is eligible, but the rate budget
is zero.

`cerebras-free-8b` and `cerebras-free-qwen3-235b` are unaffected.

### #5: `/v1/models` lists models the account can't actually use

Always verify with a real `/v1/chat/completions` probe, never trust the
listing endpoint alone for capability questions. This applies to Cerebras
specifically; OpenAI-compatible providers vary.

### #6: Drop `tier` from `model_info` in config.yaml

LiteLLM's `ModelInfo.tier` is a strict pydantic Literal of `'free'|'paid'`.
Any other value (`'background'`, `'fast-frontier'`, `'small-fast'`) silently
drops the deployment via `ValidationError`. The reference config from various
LiteLLM examples uses descriptive tier names — strip them.

### #7: Missing `Bearer ` prefix on `x-litellm-api-key` header

Even with `litellm_key_header_name` customized, LiteLLM's auth path expects
`Bearer ` prefix on the value. Direct curl examples often miss this:

```bash
# WRONG — 401 Unauthorized
curl ... -H "x-litellm-api-key: $LITELLM_MASTER_KEY"

# RIGHT
curl ... -H "x-litellm-api-key: Bearer $LITELLM_MASTER_KEY"
```

The `ccl-probe` and `ccl-health` helpers handle this automatically.

---

## Per-worktree mise alias system

Some webfront worktrees layer a second alias system on top
(`scripts/agent-aliases.zsh` + `scripts/run-agent-alias.sh` + `mise.toml`
`[shell_alias]`). The reason: `mise` automatically loads `.env.agent` for
**background tasks** in that worktree, so spawned processes (test runners,
build orchestrators, etc.) inherit the same provider env vars without the
calling shell needing to export them explicitly.

That layer mirrors `ccfw`/`ccz`/`cc-fast` etc. as worktree-local aliases.
The dotfiles functions (this file's setup) are global and work in any
directory; the worktree mise aliases only fire when `cd`'d into a worktree
that defines them. Both are valid; pick based on whether you need
`.env.agent` for background tasks.

---

## Adding a new model

1. Pick a `model_name` that doesn't trip Claude Code's classifier:
   - Avoid bare `opus`, `sonnet`, `haiku` (subscription-gated)
   - Avoid prefixes that don't match recognized providers (`cerebras-*` is
     known to be rejected by `claude --model`)
   - Use existing patterns: `glm-X.Y-suffix`, `kimi-kX.Y`, `fleet-*` (only
     for the three Anthropic tier names), `MiniMax-MX.Y`

2. Add to `config.yaml` `model_list:` with the right LiteLLM provider prefix:
   - Cerebras → `cerebras/<model>`
   - Z.AI → `openai/<model>` + `api_base: https://api.z.ai/api/paas/v4`
   - Fireworks → `openai/accounts/fireworks/models/<model>` + Fireworks api_base
   - MiniMax → `minimax/<model>`
   - Anthropic → `anthropic/<model>` (real OAuth passthrough is currently
     not configured; if you reintroduce it, see the OAuth section above for
     the LiteLLM 1.82.x bearer-token bug)

3. Add to a fallback chain in `router_settings.fallbacks` if applicable.

4. Restart: `systemctl --user restart litellm-proxy`.

5. Verify with `ccl-health` and `ccl-probe <new-model-name>`.

6. (Optional) Add a wrapper function in
   `~/.local/dotfiles/zsh/rc.d/10_litellm.zsh` if you want a dedicated alias.

7. (Optional) Mirror in worktree `scripts/agent-aliases.zsh` +
   `scripts/run-agent-alias.sh` + `mise.toml` if background-task env
   inheritance matters.

---

## Upgrade LiteLLM

Installed via `uv tool`:

```bash
uv tool upgrade litellm
litellm --version           # confirm new version
systemctl --user restart litellm-proxy
ccl-health                  # confirm everything still loads
```

Watch the changelog for fixes to:
- `/v1/messages` pass-through `drop_params` ([Issue #22797](https://github.com/BerriAI/litellm/issues/22797))
- Anthropic adapter param translation (output_config, thinking_config, metadata.user_id)
- Cerebras provider transformer

If those are fixed, the `output_config` middleware in `proxy_wrapper.py` can
be removed.

---

## Files to know

| Path | Purpose |
|---|---|
| `config.yaml` | model_list, router_settings, litellm_settings, general_settings |
| `proxy_wrapper.py` | Python entry point + `StripUnsupportedAnthropicParamsMiddleware` |
| `litellm-proxy.service` | systemd user unit (port 4199, EnvironmentFile, log dest) |
| `~/.local/dotfiles/zsh/rc.d/10_litellm.zsh` | Shell functions: `_litellm_ensure_service`, `ccl`, `ccfw`, `ccz`, `cc-fast`, `ccl-status`, `ccl-stop`, `ccl-log`, `ccl-health`, `ccl-probe` |
| `~/.local/dotfiles/zsh/env.d/09_claude_code_aliases.zsh` | Direct-provider aliases (ccm, ccz-direct, ccc) — do NOT route through this proxy |
| `~/.local/state/litellm/env` | systemd EnvironmentFile (provider keys, regenerated from shell) |
| `~/.local/state/litellm/master-key` | Stable per-machine LiteLLM master key (auto-generated on first run) |
| `~/.local/state/litellm/proxy.log` | Append-mode stdout+stderr from the systemd service |
