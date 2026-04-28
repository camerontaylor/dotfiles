# CCR (claude-code-router) default routing flag (2026-04-27)
#
# USE_CCR=1 routes ccl/ccfw/ccz/cc-fast (+ -happy variants) through CCR on
# port 3456 instead of LiteLLM /v1/messages on :4199 (the legacy/broken
# path). CCR auto-translates Anthropic Messages -> OpenAI Chat Completions
# and forwards to LiteLLM's /v1/chat/completions, which works correctly
# unlike LiteLLM 1.83.14's experimental /v1/messages?beta=true SSE
# truncation regression.
#
# Per-alias overrides (used during cutover or for ad-hoc rollback):
#   USE_CCR_CCL=0     -- ccl + ccl-happy fall back to LiteLLM /v1/messages
#   USE_CCR_CCFW=0    -- ccfw + ccfw-happy fall back
#   USE_CCR_CCZ=0     -- ccz + ccz-happy fall back
#   USE_CCR_CC_FAST=0 -- cc-fast + cc-fast-happy fall back
#
# Real Opus path (`ccc`, direct Anthropic OAuth) is NOT affected by this
# variable. ccc bypasses both CCR and LiteLLM entirely.
export USE_CCR=1
