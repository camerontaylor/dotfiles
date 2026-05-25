# CCR (claude-code-router) legacy routing flag (2026-04-27)
#
# Portkey owns the default proxy path for ccfw/ccz/cc-fast (+ -happy variants)
# on ceres.webfront.app:8787. Set USE_CCR=1 only for temporary rollback to the older
# CCR on port 3456.
#
# Per-alias overrides (used during cutover or for ad-hoc rollback):
#   USE_CCR_CCFW=1    -- ccfw + ccfw-happy use CCR
#   USE_CCR_CCZ=1     -- ccz + ccz-happy use CCR
#   USE_CCR_CC_FAST=1 -- cc-fast + cc-fast-happy use CCR
#
# Real Opus path (`ccc`, direct Anthropic OAuth) is NOT affected by this
# variable. ccc bypasses both CCR and Portkey entirely.
export USE_CCR=0
