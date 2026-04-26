#!/usr/bin/env python3
"""LiteLLM proxy entry point for systemd service.

Two responsibilities:

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
_FILTER_PREFIXES = (
    "/v1/messages",
    "/anthropic/v1/messages",
)


class StripUnsupportedAnthropicParamsMiddleware:
    """Pure ASGI middleware that strips known-incompatible top-level fields.

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
        if not any(path.startswith(prefix) for prefix in _FILTER_PREFIXES):
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
            hits = [p for p in _PARAMS_TO_DROP if p in data]
            if hits:
                for param in _PARAMS_TO_DROP:
                    data.pop(param, None)
                body = json.dumps(data, separators=(",", ":")).encode("utf-8")
                # Update Content-Length so downstream framing is correct
                _patch_content_length(scope, len(body))
                print(
                    f"[proxy_wrapper] POST {path} stripped={hits} new_len={len(body)}",
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


# Inject middleware BEFORE LiteLLM starts uvicorn. The FastAPI app is
# module-level in litellm.proxy.proxy_server, so importing it here grabs the
# unstarted instance; add_middleware mutates it in place.
from litellm.proxy.proxy_server import app  # noqa: E402

app.add_middleware(StripUnsupportedAnthropicParamsMiddleware)
print(
    f"[proxy_wrapper] StripUnsupportedAnthropicParamsMiddleware installed; "
    f"dropping {_PARAMS_TO_DROP} on {_FILTER_PREFIXES}",
    file=sys.stderr,
    flush=True,
)

from litellm.proxy.proxy_cli import run_server  # noqa: E402

run_server()
