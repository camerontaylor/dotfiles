# Normal Max plan Claude - explicitly unset any CCR vars
alias ccc='unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY && claude'

# Cheap OpenRouter via CCR
alias cc='eval "$(ccr activate)" && claude'


alias cc-minimax='ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" claude'

alias ccz='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=glm-4.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.5-air ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5 ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" claude'
alias ccz='CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ANTHROPIC_DEFAULT_SONNET_MODEL=glm-4.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7-air ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5 ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" API_TIMEOUT_MS="3000000" ANTHROPIC_API_KEY="" happy yolo --dangerously-skip-permissions'

#export GEMINI_API_KEY=...  # set in zsh/env.d/90_secrets.zsh
