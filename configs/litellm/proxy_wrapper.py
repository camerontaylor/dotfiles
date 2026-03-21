#!/usr/bin/env python3
"""LiteLLM proxy entry point for systemd service.

OAuth passthrough works via clean_headers + forward_client_headers_to_llm_api:
- Proxy authenticates via x-litellm-api-key (custom header, stripped after auth)
- Claude Code's x-api-key (OAuth token) is preserved and forwarded to Anthropic
- No monkey-patching needed — LiteLLM's built-in header forwarding handles it
"""
from litellm.proxy.proxy_cli import run_server

run_server()
