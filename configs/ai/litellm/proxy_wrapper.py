#!/usr/bin/env python3
"""LiteLLM proxy entry point for systemd service.

CCR CUTOVER NOTE (2026-04-27):
  As of CCR (claude-code-router) deployment on ceres:3456 as the Anthropic-
  format frontend, /v1/messages traffic is served by CCR — NOT by LiteLLM.
  LiteLLM now serves /v1/chat/completions (OpenAI format) for CCR-translated
  traffic. The ASGI middleware below now protects BOTH paths:

  - /v1/messages top-level Anthropic-param stripping is retained as a safety
    net for the USE_CCR=0 / USE_CCR_<alias>=0 rollback path.
  - /v1/chat/completions nested message stripping is active on the production
    CCR path. CCR can preserve Claude Code's prior assistant thinking history
    as `messages[*].thinking`; strict OpenAI-compatible providers (Fireworks)
    reject that field before LiteLLM's fallback chain can recover.

  DO NOT delete these middlewares — and DO NOT remove the
  `litellm.use_chat_completions_url_for_anthropic_messages = True` flag below
  — until the rollback path itself is decommissioned AND CCR/LiteLLM have a
  native provider-safe sanitizer for translated chat-completions requests.
  Plan: ../../webfront/.omc/plans/ccr-litellm-frontend.md

Three responsibilities (LEGACY — the production path now uses CCR; these
remain only for the USE_CCR=0 rollback hatch):

1. OAuth passthrough (legacy): clean_headers + forward_client_headers_to_llm_api
   in config.yaml lets Claude Code's x-api-key (OAuth token) flow through to
   Anthropic. (Currently no Anthropic-routed model in config.yaml uses this,
   but the wiring is preserved for future use.)

2. Strip incompatible Anthropic /v1/messages params before LiteLLM's adapter
   forwards them to upstream providers. LiteLLM's `drop_params: true` and
   `additional_drop_params` are INEFFECTIVE on the /v1/messages pass-through
   path — see https://github.com/BerriAI/litellm/issues/22797. Cerebras's
   strict request validation rejects unknown params with HTTP 400, so we
   strip them at the proxy boundary via Starlette middleware.

3. Coerce non-streaming Anthropic /v1/messages requests with large
   max_tokens into upstream-streaming + accumulated-JSON-to-client. Fireworks
   (and other reasoning-tier upstreams) reject `max_tokens > 4096` without
   `stream=true`, so any fallback chain that traverses Fireworks 400s on
   real Claude Code skill traffic. LiteLLM has no built-in flag for this
   coercion (`litellm_params.stream: true` forces SSE on BOTH legs, breaking
   non-streaming clients). We do it ourselves at the ASGI boundary.

4. Strip CCR-translated chat-completions message fields that are Anthropic
   transcript metadata rather than OpenAI Chat Completions input. The concrete
   production failure this prevents is Fireworks rejecting `messages[*].thinking`
   when ccz falls back from exhausted Z.AI glm-5.3-bg to glm-5.3-fast/kimi.
"""
import json
import sys


# Strip these top-level fields from incoming /v1/messages request bodies.
# This is a top-level field-strip only — nested fields (like `cache_control`
# inside message content blocks) need a structural transformer (see CCR-style
# pattern at musistudio/llms — out of scope here until something breaks).
#
# Rationale per field (all of these are Anthropic-format fields that LiteLLM's
# /v1/messages adapter forwards verbatim to non-Anthropic upstreams that
# either reject them strictly or ignore them; stripping is safe because all
# proxy /v1/messages targets are non-Anthropic):
# - output_config:    extended-thinking config; Cerebras returns 400
# - thinking:         older Anthropic thinking control; Cerebras rejects
# - anthropic_version: occasionally body-level; harmless to drop
# - metadata:         user_id tracking; not honored by upstream OpenAI providers
# - stream_options:   OpenAI streaming hint; Anthropic clients sometimes inject
# - reasoning:        OpenAI Responses API holdout; doesn't belong on Cerebras
_PARAMS_TO_DROP = (
    "output_config",
    "thinking",
    "anthropic_version",
    "metadata",
    "stream_options",
    "reasoning",
)

# Match POST routes carrying Anthropic-format request bodies. count_tokens is
# usually safe but no harm in filtering both.
_ANTHROPIC_FILTER_PREFIXES = (
    "/v1/messages",
    "/anthropic/v1/messages",
)

# Match CCR -> LiteLLM production traffic. CCR translates Anthropic Messages to
# OpenAI Chat Completions but currently leaves prior assistant thinking history
# on message objects. Fireworks' chat-completions validator rejects that as an
# extra input (`messages[N].thinking`), which breaks LiteLLM fallbacks.
_CHAT_COMPLETIONS_FILTER_PREFIXES = (
    "/v1/chat/completions",
    "/chat/completions",
)

_CHAT_MESSAGE_PARAMS_TO_DROP = (
    "thinking",
)

_CHAT_CONTENT_BLOCK_TYPES_TO_DROP = frozenset(("thinking", "redacted_thinking"))

# Top-level fields dropped unconditionally from /v1/chat/completions bodies.
# CCR's Anthropic transformer adds `enable_thinking: true` alongside
# `reasoning` when translating Claude Code's `thinking: {...}`. Fireworks
# 400s on the boolean too. The reasoning field itself gets TRANSLATED rather
# than dropped — see _translate_reasoning_to_effort below. (2026-04-28)
_CHAT_TOP_LEVEL_PARAMS_TO_DROP = (
    "enable_thinking",
)

# Per-model gate for stream coercion. Triggering on max_tokens is a poor
# proxy: it's a *cap* not a prediction, and the underlying problem is a
# provider/model property (Fireworks reasoning models time out without
# streaming on long generations; their /chat/completions endpoint also
# rejects max_tokens > 4096 outright without stream=true). Trigger on the
# model name instead — it matches reality and is what the routing taxonomy
# tracks anyway.
#
# CURRENTLY DISABLED (empty set) — 2026-04-27.
#
# Reason: LiteLLM 1.83.14's experimental Anthropic pass-through
# (`POST /v1/messages?beta=true`) truncates outbound SSE streams to the
# client. Verified empirically against multiple upstreams (Fireworks
# glm-5.3-fast AND Cerebras zai-glm-4.7) — both stop emitting SSE chunks
# after only a handful of content_block_delta events, never sending
# message_stop, and uvicorn logs "ASGI callable returned without
# completing response." This is upstream of the proxy_wrapper layer; the
# accumulator below works correctly when fed valid SSE but cannot fix a
# truncated source. Until LiteLLM fixes its stream forwarding, coercing
# Fireworks-bound non-streaming requests to streaming would just convert
# every such request into a 502 with a truncation error — strictly worse
# than the original 400 from Fireworks.
#
# When LiteLLM is upgraded (or a config switch unbreaks streaming),
# repopulate this set with the direct-Fireworks deployments:
#   {"kimi-k2.6", "kimi-k2.5", "glm-5.3-fast", "minimax-m2.7",
#    "fleet-opus", "fleet-sonnet"}
# and verify a streamed glm-5.3-fast request emits a `message_stop` event
# before re-enabling.
#
# Source of truth: model_list in config.yaml.
_STREAM_COERCION_MODELS = frozenset()


class StripUnsupportedAnthropicParamsMiddleware:
    """Pure ASGI middleware that strips known-incompatible request fields.

    Implemented at the ASGI level (not BaseHTTPMiddleware) because the latter
    has a long-standing FastAPI body-modification bug: replacing
    request._receive does not propagate to downstream handlers that re-read
    the body via Starlette's `Request.body()` cache or FastAPI's dependency
    injection. Pure ASGI middleware modifies the receive callable BEFORE the
    Request object is constructed, which all downstream consumers honor.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http" or scope.get("method") != "POST":
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "")
        is_anthropic_messages = any(
            path.startswith(prefix) for prefix in _ANTHROPIC_FILTER_PREFIXES
        )
        is_chat_completions = any(
            path.startswith(prefix) for prefix in _CHAT_COMPLETIONS_FILTER_PREFIXES
        )
        if not is_anthropic_messages and not is_chat_completions:
            await self.app(scope, receive, send)
            return

        # Drain the full body (handle chunked / multi-message receives).
        chunks = []
        more_body = True
        while more_body:
            msg = await receive()
            if msg["type"] == "http.disconnect":
                # Nothing more to do; let downstream see the disconnect.
                async def disconnect_receive():
                    return msg
                await self.app(scope, disconnect_receive, send)
                return
            chunks.append(msg.get("body", b""))
            more_body = msg.get("more_body", False)

        body = b"".join(chunks)

        # Try to strip the unsupported params; fail open on any parse error.
        try:
            data = json.loads(body)
        except (json.JSONDecodeError, ValueError):
            data = None

        if isinstance(data, dict):
            hits = []
            if is_anthropic_messages:
                hits.extend([p for p in _PARAMS_TO_DROP if p in data])
                if hits:
                    for param in _PARAMS_TO_DROP:
                        data.pop(param, None)
            if is_chat_completions:
                for param in _CHAT_TOP_LEVEL_PARAMS_TO_DROP:
                    if param in data:
                        data.pop(param, None)
                        hits.append(param)
                translation_hit = _translate_reasoning_to_effort(data)
                if translation_hit:
                    hits.append(translation_hit)
                hits.extend(_strip_chat_completions_message_params(data))
            if hits:
                body = json.dumps(data, separators=(",", ":")).encode("utf-8")
                # Update Content-Length so downstream framing is correct
                _patch_content_length(scope, len(body))
                preview = ", ".join(hits[:12])
                if len(hits) > 12:
                    preview = f"{preview}, ... +{len(hits) - 12} more"
                print(
                    f"[proxy_wrapper] POST {path} stripped=[{preview}] "
                    f"new_len={len(body)}",
                    file=sys.stderr,
                    flush=True,
                )

        # Replay the (possibly modified) body to downstream as a single message.
        sent = False

        async def replay_receive():
            nonlocal sent
            if sent:
                # After the body, signal end-of-stream by waiting for any
                # further client messages (e.g. disconnect).
                return {"type": "http.disconnect"}
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}

        await self.app(scope, replay_receive, send)


def _translate_reasoning_to_effort(data):
    """Translate OpenAI o1-style `reasoning: {effort, enabled}` to Fireworks/
    Cerebras-style top-level `reasoning_effort: "low"|"medium"|"high"`.

    CCR's Anthropic transformer emits the o1 nested-object shape, but our
    actual upstreams (Fireworks, Cerebras, Z.AI, MiniMax) implement the
    Chat Completions extension as a plain string field instead. Without
    translation, Fireworks 400s with "Extra inputs are not permitted,
    field: 'reasoning'" — and the thinking signal is lost.

    Returns a `hits` string for logging if translation happened, else None.
    Fail-safe: if `reasoning` is unparseable or `enabled` is false, drop it
    silently rather than synthesize a default.
    """
    reasoning = data.get("reasoning")
    if reasoning is None:
        return None
    data.pop("reasoning", None)
    if not isinstance(reasoning, dict):
        return "reasoning(non-dict, dropped)"
    if reasoning.get("enabled") is False:
        return "reasoning(enabled=false, dropped)"
    effort = reasoning.get("effort")
    if effort not in ("low", "medium", "high"):
        return "reasoning(unknown-effort, dropped)"
    # Don't overwrite if caller already set reasoning_effort directly.
    if "reasoning_effort" not in data:
        data["reasoning_effort"] = effort
    return f"reasoning->reasoning_effort:{effort}"


def _strip_chat_completions_message_params(data):
    """Remove Anthropic-only transcript metadata from OpenAI chat messages."""
    messages = data.get("messages")
    if not isinstance(messages, list):
        return []

    hits = []
    for message_index, message in enumerate(messages):
        if not isinstance(message, dict):
            continue

        for param in _CHAT_MESSAGE_PARAMS_TO_DROP:
            if param in message:
                message.pop(param, None)
                hits.append(f"messages[{message_index}].{param}")

        content = message.get("content")
        if not isinstance(content, list):
            continue

        filtered_content = []
        removed_content = False
        for block_index, block in enumerate(content):
            if (
                isinstance(block, dict)
                and block.get("type") in _CHAT_CONTENT_BLOCK_TYPES_TO_DROP
            ):
                hits.append(f"messages[{message_index}].content[{block_index}]")
                removed_content = True
                continue
            filtered_content.append(block)

        if removed_content:
            message["content"] = filtered_content if filtered_content else ""

    return hits


def _patch_content_length(scope, new_length):
    """Update the Content-Length header in the ASGI scope to match new body."""
    headers = scope.get("headers", [])
    new_headers = []
    seen = False
    for name, value in headers:
        if name.lower() == b"content-length":
            new_headers.append((name, str(new_length).encode("ascii")))
            seen = True
        else:
            new_headers.append((name, value))
    if not seen:
        new_headers.append((b"content-length", str(new_length).encode("ascii")))
    scope["headers"] = new_headers


class StreamAccumulationError(Exception):
    """Raised when SSE accumulation produces a definite error response.

    Distinguishes "upstream told us this failed" (should map to a structured
    error JSON with the right status code) from "we couldn't parse the stream"
    (should fail open and pass the SSE through unchanged).
    """

    def __init__(self, message, status_code=502, error_payload=None):
        super().__init__(message)
        self.status_code = status_code
        self.error_payload = error_payload


class MaxTokensStreamCoercionMiddleware:
    """ASGI middleware that coerces non-streaming Anthropic /v1/messages
    requests for Fireworks-bound models into upstream-streaming +
    accumulated-JSON responses to the client.

    Required because Fireworks' /chat/completions endpoint rejects non-streaming
    requests with max_tokens > 4096 ("Requests with max_tokens > 4096 must have
    stream=true") AND has an HTTP-layer timeout (~60s) that long generations on
    reasoning models breach without streaming. LiteLLM's deployment-level
    `litellm_params.stream: true` forces SSE on BOTH legs (would return SSE to
    a JSON-expecting client), so we coerce at the ASGI boundary instead.

    Trigger: per-model gate (see _STREAM_COERCION_MODELS). Includes both
    direct Fireworks deployments and models with a Fireworks fallback.

    Strategy:
      1. Drain the request body, parse JSON.
      2. If `stream` is false/unset AND model is in the gate set: rewrite
         body to `stream: true`, replay downstream.
      3. Capture the response stream. If 200 + text/event-stream, parse the
         Anthropic Messages SSE events into a single Messages JSON envelope
         and return as application/json.
      4. Error events in the stream → return a structured error JSON with
         the appropriate status code (502 by default).
      5. Truncated streams (no message_stop received) → 502 with an explicit
         "stream closed before completion" error.
      6. Any unexpected parse failure → fail open: pass the SSE through
         unchanged so we never make things worse.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http" or scope.get("method") != "POST":
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "")
        if not any(path.startswith(prefix) for prefix in _ANTHROPIC_FILTER_PREFIXES):
            await self.app(scope, receive, send)
            return

        # Drain the full body
        chunks = []
        more_body = True
        while more_body:
            msg = await receive()
            if msg["type"] == "http.disconnect":
                async def _disc():
                    return msg
                await self.app(scope, _disc, send)
                return
            chunks.append(msg.get("body", b""))
            more_body = msg.get("more_body", False)
        body = b"".join(chunks)

        # Parse and decide
        try:
            data = json.loads(body)
        except (json.JSONDecodeError, ValueError):
            data = None

        try:
            client_stream = bool(data.get("stream")) if isinstance(data, dict) else False
            requested_model = data.get("model") if isinstance(data, dict) else None
        except (TypeError, ValueError):
            client_stream = False
            requested_model = None

        should_coerce = (
            isinstance(data, dict)
            and not client_stream
            and isinstance(requested_model, str)
            and requested_model in _STREAM_COERCION_MODELS
        )

        if not should_coerce:
            await _replay_body(self.app, scope, body, send)
            return

        # Mutate body: stream=true upstream
        data["stream"] = True
        new_body = json.dumps(data, separators=(",", ":")).encode("utf-8")
        _patch_content_length(scope, len(new_body))

        captured_status = [None]
        captured_headers = [list()]
        captured_chunks = []

        async def capture_send(message):
            mtype = message.get("type")
            if mtype == "http.response.start":
                captured_status[0] = message.get("status")
                captured_headers[0] = list(message.get("headers", []))
            elif mtype == "http.response.body":
                captured_chunks.append(message.get("body", b""))

        sent_state = {"replayed": False}

        async def replay_receive():
            if sent_state["replayed"]:
                return {"type": "http.disconnect"}
            sent_state["replayed"] = True
            return {"type": "http.request", "body": new_body, "more_body": False}

        await self.app(scope, replay_receive, capture_send)

        status = captured_status[0] or 500
        headers = captured_headers[0]
        full_body = b"".join(captured_chunks)

        content_type = b""
        for k, v in headers:
            if k.lower() == b"content-type":
                content_type = v
                break

        # Pass-through cases: non-200, or non-SSE response body
        if status != 200 or b"text/event-stream" not in content_type.lower():
            await send({"type": "http.response.start", "status": status, "headers": headers})
            await send({"type": "http.response.body", "body": full_body, "more_body": False})
            return

        # Try to accumulate. Three outcomes:
        #   1. Success → JSON body, status 200.
        #   2. StreamAccumulationError → upstream error or truncation; emit a
        #      structured error JSON with the carried status code.
        #   3. Anything else → unexpected parse failure; fail open and pass
        #      the raw SSE through unchanged so the client at least sees what
        #      it would have seen without us.
        try:
            accumulated = _accumulate_anthropic_messages_sse(full_body)
            json_body = json.dumps(accumulated).encode("utf-8")
            response_status = status
        except StreamAccumulationError as exc:
            err_payload = exc.error_payload or {
                "type": "error",
                "error": {"type": "api_error", "message": str(exc)},
            }
            json_body = json.dumps(err_payload).encode("utf-8")
            response_status = exc.status_code
            print(
                f"[proxy_wrapper] coerce stream error model={data.get('model')} "
                f"status={response_status} message={exc!s}",
                file=sys.stderr,
                flush=True,
            )
        except Exception as exc:
            print(
                f"[proxy_wrapper] SSE accumulation failed ({exc!r}); "
                f"passing SSE through unchanged",
                file=sys.stderr,
                flush=True,
            )
            await send({"type": "http.response.start", "status": status, "headers": headers})
            await send({"type": "http.response.body", "body": full_body, "more_body": False})
            return

        new_headers = []
        for k, v in headers:
            kl = k.lower()
            if kl in (b"content-type", b"content-length", b"transfer-encoding"):
                continue
            new_headers.append((k, v))
        new_headers.append((b"content-type", b"application/json"))
        new_headers.append((b"content-length", str(len(json_body)).encode("ascii")))

        if response_status == status:
            print(
                f"[proxy_wrapper] coerced stream→json model={data.get('model')} "
                f"max_tokens={data.get('max_tokens')} sse_in={len(full_body)} "
                f"json_out={len(json_body)}",
                file=sys.stderr,
                flush=True,
            )

        await send({"type": "http.response.start", "status": response_status, "headers": new_headers})
        await send({"type": "http.response.body", "body": json_body, "more_body": False})


async def _replay_body(app, scope, body, send):
    """Replay a drained request body to the inner ASGI app."""
    sent = [False]

    async def replay_receive():
        if sent[0]:
            return {"type": "http.disconnect"}
        sent[0] = True
        return {"type": "http.request", "body": body, "more_body": False}

    await app(scope, replay_receive, send)


def _accumulate_anthropic_messages_sse(body):
    """Parse an Anthropic Messages SSE event stream into a single Messages JSON.

    Reference: https://docs.anthropic.com/en/api/messages-streaming

    Tolerates upstream quirks observed in the wild (e.g. Fireworks GLM-5p1
    emitting `thinking_delta` chunks targeted at a block declared as
    `type: text`): each delta type gets its own accumulator field on the block
    regardless of the block's declared type. Whatever the upstream sent, we
    surface back to the client.

    Usage notes:
      - message_start carries the initial usage envelope including
        cache_creation_input_tokens / cache_read_input_tokens.
      - message_delta usage carries the cumulative output_tokens at end of
        stream — absolute, NOT incremental. We use dict.update() so the final
        message_delta usage replaces output_tokens while preserving the
        input/cache fields from message_start.

    Raises StreamAccumulationError on:
      - error events in the stream (with the upstream payload preserved)
      - truncated streams (no message_stop received before EOF)
      - malformed streams (no message_start)
    """
    text = body.decode("utf-8", errors="replace").replace("\r\n", "\n")

    message = None
    blocks = {}  # index -> content block dict
    received_stop = False

    for raw_event in text.split("\n\n"):
        raw_event = raw_event.strip()
        if not raw_event:
            continue

        event_type = None
        data_payload = None
        for line in raw_event.split("\n"):
            if line.startswith(":"):
                continue  # SSE comment
            if line.startswith("event:"):
                event_type = line[6:].strip()
            elif line.startswith("data:"):
                data_str = line[5:].strip()
                try:
                    data_payload = json.loads(data_str)
                except (json.JSONDecodeError, ValueError):
                    data_payload = None
        if data_payload is None:
            continue

        et = data_payload.get("type") or event_type
        if not et:
            continue

        if et == "message_start":
            msg_obj = data_payload.get("message")
            if isinstance(msg_obj, dict):
                message = dict(msg_obj)
                message["content"] = []
        elif et == "content_block_start":
            idx = data_payload.get("index")
            cb = data_payload.get("content_block") or {}
            block = dict(cb)
            blk_type = block.get("type")
            if blk_type == "text" and "text" not in block:
                block["text"] = ""
            elif blk_type == "thinking" and "thinking" not in block:
                block["thinking"] = ""
            elif blk_type == "tool_use" and not isinstance(block.get("input"), str):
                block["input"] = ""  # accumulated as JSON string, parsed at stop
            blocks[idx] = block
        elif et == "content_block_delta":
            idx = data_payload.get("index")
            block = blocks.get(idx)
            if block is None:
                continue
            delta = data_payload.get("delta") or {}
            dt = delta.get("type")
            if dt == "text_delta":
                block["text"] = (block.get("text") or "") + (delta.get("text") or "")
            elif dt == "thinking_delta":
                block["thinking"] = (block.get("thinking") or "") + (delta.get("thinking") or "")
            elif dt == "signature_delta":
                block["signature"] = delta.get("signature") or block.get("signature") or ""
            elif dt == "input_json_delta":
                if not isinstance(block.get("input"), str):
                    block["input"] = ""
                block["input"] = block["input"] + (delta.get("partial_json") or "")
        elif et == "content_block_stop":
            idx = data_payload.get("index")
            block = blocks.get(idx)
            if block is None:
                continue
            if block.get("type") == "tool_use" and isinstance(block.get("input"), str):
                input_str = block["input"]
                if input_str:
                    try:
                        block["input"] = json.loads(input_str)
                    except (json.JSONDecodeError, ValueError):
                        block["input"] = {}
                else:
                    block["input"] = {}
        elif et == "message_delta":
            if message is None:
                continue
            delta = data_payload.get("delta") or {}
            for k, v in delta.items():
                message[k] = v
            usage = data_payload.get("usage")
            if isinstance(usage, dict):
                cur_usage = message.get("usage")
                if not isinstance(cur_usage, dict):
                    cur_usage = {}
                cur_usage.update(usage)
                message["usage"] = cur_usage
        elif et == "message_stop":
            received_stop = True
        elif et == "error":
            # Mid-stream upstream error. Surface the payload verbatim with a
            # 502 (the HTTP layer succeeded but the upstream chunked an error
            # mid-generation; "Bad Gateway" is the closest fit).
            err = data_payload.get("error") or data_payload
            raise StreamAccumulationError(
                f"upstream stream error: {json.dumps(err)}",
                status_code=502,
                error_payload={"type": "error", "error": err},
            )
        elif et == "ping":
            # SSE keep-alive heartbeat; ignore.
            pass

    if message is None:
        # No envelope ever arrived. Likely a corrupted or truncated stream
        # before message_start; let the caller fall open and pass the SSE
        # through unchanged — at least the client sees the original bytes.
        raise ValueError("no message_start event found in SSE stream")

    if not received_stop:
        # Stream ended before message_stop. Could be a connection drop, an
        # upstream timeout, or a proxy/load-balancer truncation. Whatever the
        # cause, the message we have is partial — returning it as a 200
        # success would silently corrupt the conversation. Emit an explicit
        # error so the caller (e.g. Claude Code's retry path) can decide
        # what to do.
        raise StreamAccumulationError(
            "stream truncated before message_stop",
            status_code=502,
            error_payload={
                "type": "error",
                "error": {
                    "type": "api_error",
                    "message": "Upstream stream closed before completion",
                },
            },
        )

    message["content"] = [blocks[i] for i in sorted(blocks.keys())]
    return message


# Inject middleware BEFORE LiteLLM starts uvicorn. The FastAPI app is
# module-level in litellm.proxy.proxy_server, so importing it here grabs the
# unstarted instance; add_middleware mutates it in place.
import litellm  # noqa: E402
from litellm.proxy.proxy_server import app  # noqa: E402

# Order matters: Starlette's add_middleware wraps outside-in. The LAST call is
# OUTERMOST. We want Strip to act on the request first (cleaning out fields
# like `thinking`/`metadata` that could change body shape) and Coerce to see
# the cleaned body, so Coerce is added first (inner) and Strip is added
# second (outer). On the response path, Coerce captures and transforms the
# inner SSE before Strip sees it; Strip is a no-op on responses.
app.add_middleware(MaxTokensStreamCoercionMiddleware)
print(
    f"[proxy_wrapper] MaxTokensStreamCoercionMiddleware installed; "
    f"coercing non-stream requests for {sorted(_STREAM_COERCION_MODELS)} "
    f"on {_ANTHROPIC_FILTER_PREFIXES}",
    file=sys.stderr,
    flush=True,
)

app.add_middleware(StripUnsupportedAnthropicParamsMiddleware)
print(
    f"[proxy_wrapper] StripUnsupportedAnthropicParamsMiddleware installed; "
    f"dropping {_PARAMS_TO_DROP} on {_ANTHROPIC_FILTER_PREFIXES}; "
    f"dropping top-level {_CHAT_TOP_LEVEL_PARAMS_TO_DROP} and "
    f"{_CHAT_MESSAGE_PARAMS_TO_DROP} on messages for "
    f"{_CHAT_COMPLETIONS_FILTER_PREFIXES}",
    file=sys.stderr,
    flush=True,
)

# Disable LiteLLM's experimental Responses-API adapter for Anthropic-format
# /v1/messages requests. When Claude Code 2.1.119+ sends ?beta=true, LiteLLM
# inspects the deployment's provider prefix; for openai/-prefixed models it
# would normally POST upstream /responses (OpenAI Responses API). Z.AI's
# OpenAI-compat surface (/api/paas/v4) does NOT implement /responses, so the
# adapter 404s; Claude Code then renders the misleading "model may not exist
# or you may not have access" error. This flag forces /chat/completions for
# all openai/-prefixed deployments, which Z.AI (and every other openai-compat
# upstream we use) supports natively.
#
# Source: litellm/llms/anthropic/experimental_pass_through/messages/handler.py
#   _should_route_to_responses_api() — checks this module attribute.
#
# 2026-04-28: pinned to litellm 1.81.14, which predates this flag. The
# Responses-API adapter that the flag disables also predates this version,
# so the setattr below is harmless on 1.81.14 (no lookup code consults it)
# and re-arms the flag automatically if/when LiteLLM is upgraded back to
# 1.82.x+.
litellm.use_chat_completions_url_for_anthropic_messages = True
_litellm_version = getattr(litellm, "__version__", "?")
print(
    f"[proxy_wrapper] use_chat_completions_url_for_anthropic_messages=True "
    f"(litellm=={_litellm_version}; "
    f"flag is no-op on <1.82, active on >=1.82)",
    file=sys.stderr,
    flush=True,
)

from litellm.proxy.proxy_cli import run_server  # noqa: E402

run_server()
