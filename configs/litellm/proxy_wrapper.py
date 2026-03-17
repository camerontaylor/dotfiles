#!/usr/bin/env python3
"""Patches LiteLLM to forward Authorization header for OAuth passthrough, then starts proxy."""
import litellm.proxy.litellm_pre_call_utils as utils

_orig_fn = utils.LiteLLMProxyRequestSetup._get_forwardable_headers


def _patched(headers):
    result = _orig_fn(headers)
    for h, v in headers.items() if hasattr(headers, "items") else []:
        if h.lower() == "authorization":
            result[h] = v
            break
    return result


utils.LiteLLMProxyRequestSetup._get_forwardable_headers = staticmethod(_patched)

from litellm.proxy.proxy_cli import run_server  # noqa: E402

run_server()
