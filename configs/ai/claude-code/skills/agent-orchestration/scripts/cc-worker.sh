#!/usr/bin/env zsh
# cc-worker — run a headless Claude Code worker under a named routing alias.
#
# Why this exists: the cc* aliases (ccz-direct, ccx-direct, ...) live in
# zsh/env.d/09_claude_code_aliases.zsh behind an `[[ -o interactive ]]` guard,
# so they DO NOT EXIST in the non-interactive shell an agent's Bash tool gets.
# This script loads their env via the same source of truth the aliases use
# (dotfiles/scripts/agent-aliases.zsh :: agent_alias_export_env) and then
# invokes `claude -p` with a minimised flag set.
#
# Usage:
#   cc-worker.sh <alias> [--tools "Read,Grep"|none] [--schema '<json>']
#                [--bg <logfile>] [--cwd <dir>] [--session <uuid>]
#                [--append-prompt <text>] [-- <extra claude flags>] <prompt>
#
# Aliases: cc (real Anthropic) | ccz-direct | ccx-direct | ccd-direct
#          ccm-direct | ccfw-direct | ccz | ccd | ccfw | ccm | cc-fast
set -euo pipefail
emulate -L zsh

ALIASES_FILE="$HOME/.local/dotfiles/scripts/agent-aliases.zsh"
[[ -r $ALIASES_FILE ]] || { print -u2 "cc-worker: missing $ALIASES_FILE"; exit 2 }

alias_name="${1:?usage: cc-worker.sh <alias> [opts] <prompt>}"; shift

tools="Read,Grep,Glob,Bash"   # "none" = pass --tools "" (cheapest: no tool schemas)
schema="" bglog="" workdir="$PWD" session="" append="" model_override=""
typeset -a extra
while (( $# )); do
  case "$1" in
    --tools)         tools="$2"; shift 2 ;;
    --schema)        schema="$2"; shift 2 ;;
    --bg)            bglog="$2"; shift 2 ;;
    --cwd)           workdir="$2"; shift 2 ;;
    --session)       session="$2"; shift 2 ;;
    --append-prompt) append="$2"; shift 2 ;;
    --model)         model_override="$2"; shift 2 ;;
    --)              shift; extra=("$@"); break ;;
    *)               break ;;
  esac
done
prompt="${1:?cc-worker: no prompt given}"

# Load the alias's routing env into this subshell only.
source "$ALIASES_FILE"
agent_alias_export_env "$alias_name"

# agent_alias_export_env sets ANTHROPIC_DEFAULT_*_MODEL but not always
# ANTHROPIC_MODEL (ccz-direct/ccm-direct/ccfw-direct omit it), while the
# interactive alias compensates with an explicit `--model`. Mirror that here.
if [[ -z $model_override ]]; then
  case "$alias_name" in
    ccz-direct|ccz-direct-happy) model_override="glm-5.3" ;;
    ccm-direct|ccm-direct-happy) model_override="MiniMax-M2.7" ;;
    ccfw-direct)                 model_override="accounts/fireworks/models/minimax-m2p7" ;;
    ccd-direct|ccd-direct-happy) model_override="deepseek-v4-pro[1m]" ;;
    ccx-direct|ccx-direct-happy|ccx) model_override="stealth/ox-alpha" ;;
  esac
fi

typeset -a args
args=(-p "$prompt" --output-format json --permission-mode bypassPermissions)
[[ -n $model_override ]] && args+=(--model "$model_override")
# NB: an empty/"none" toolset must still emit the flag, otherwise Claude Code
# loads ALL built-in tools (~15k tokens). Never guard this with [[ -n ]].
if [[ $tools == none || -z $tools ]]; then args+=(--tools "")
else args+=(--tools "$tools"); fi
[[ -n $schema ]] && args+=(--json-schema "$schema")
[[ -n $session ]] && args+=(--session-id "$session")
[[ -n $append ]] && args+=(--append-system-prompt "$append")
# Workers get no MCP servers and no inherited settings: that is the bulk of
# the token overhead (17.4k -> ~2k on a trivial call, measured 2026-08-21).
args+=(--strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources "")
(( ${#extra} )) && args+=("${extra[@]}")

cd "$workdir"

# NB: claude's own --bg is incompatible with -p ("--bg and --print conflict"),
# so backgrounding is done here by detaching the process. Poll the log for the
# JSON result; the file is complete once the process exits.
if [[ -n $bglog ]]; then
  nohup claude "${args[@]}" >"$bglog" 2>"${bglog%.json}.err" &
  print -r -- "{\"pid\":$!,\"log\":\"$bglog\",\"alias\":\"$alias_name\"}"
  exit 0
fi
exec claude "${args[@]}"
