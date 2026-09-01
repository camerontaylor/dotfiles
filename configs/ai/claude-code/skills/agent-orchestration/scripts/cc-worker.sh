#!/usr/bin/env bash
# cc-worker — run a headless Claude Code worker under a named routing alias.
#
# Why this exists: the cc* aliases (ccz-direct, ccx-direct, ...) live in
# zsh/env.d/09_claude_code_aliases.zsh behind an `[[ -o interactive ]]` guard,
# so they DO NOT EXIST in the non-interactive shell an agent's Bash tool gets.
# This script loads their env via the same source of truth the aliases use
# (dotfiles/scripts/agent-aliases.zsh :: agent_alias_export_env) and then
# invokes `claude -p` with a minimised flag set.
#
# Bash, not zsh: its documented purpose is being run FROM the Bash tool
# (docs/bash-compatibility.md §D), so it must parse and run under bash —
# including macOS stock /bin/bash 3.2 (no assoc arrays, no mapfile; the
# `${arr[@]+…}` guards keep empty arrays safe under `set -u`). The alias env
# itself is zsh-only (typeset -gA — interactive layer, §C), so it is loaded
# through a `zsh -f` bridge below, not sourced.
#
# Every backgrounded worker gets an ENFORCED LIFETIME. Detached workers survive
# their parent session being killed (verified: SIGKILL and SIGTERM both), so
# without a hard bound they accumulate as orphans forever.
#
# Usage:
#   cc-worker.sh <alias> [--tools "Read,Grep"|none] [--schema '<json>']
#                [--bg <logfile>] [--ttl 30m] [--max-turns N] [--cwd <dir>]
#                [--session <uuid>] [--append-prompt <text>]
#                [-- <extra claude flags>] <prompt>
#   cc-worker.sh --list            # every live/finished worker + age
#   cc-worker.sh --reap            # stop workers past their TTL, clear finished
#   cc-worker.sh --reap --all      # stop EVERY cc-worker now
#
# Aliases: cc (real Anthropic) | ccz-direct | ccx-direct | ccd-direct
#          ccm-direct | ccfw-direct | ccz | ccd | ccfw | ccm | cc-fast
set -euo pipefail
shopt -s nullglob

ALIASES_FILE="$HOME/.local/dotfiles/scripts/agent-aliases.zsh"
REG="${CC_WORKER_REGISTRY:-$HOME/.claude/cc-workers}"
mkdir -p "$REG"

# ---------------------------------------------------------------- reaper ----
# A worker is one of: running (unit active / pid alive), finished (exited on its
# own), or orphaned (past TTL and still alive). --reap kills the last kind.

worker_rows () {
  local f f_base id unit pid ttl started alias_name log state age
  for f in "$REG"/*.json; do
    [[ -f $f ]] || continue
    f_base=${f##*/}; id=${f_base%.json}
    unit=$(jq -r '.unit // ""' "$f"); pid=$(jq -r '.pid // 0' "$f")
    ttl=$(jq -r '.ttl_sec // 0' "$f"); started=$(jq -r '.started // 0' "$f")
    alias_name=$(jq -r '.alias // "?"' "$f"); log=$(jq -r '.log // ""' "$f")
    age=$(( $(date +%s) - started ))
    if [[ -n $unit ]] && systemctl --user is-active --quiet "$unit" 2>/dev/null; then
      state=running
    elif [[ -z $unit ]] && (( pid > 0 )) && kill -0 "$pid" 2>/dev/null; then
      state=running
    else
      state=finished
    fi
    [[ $state == running ]] && (( ttl > 0 && age > ttl )) && state=ORPHANED
    printf '%s\n' "$id|$state|$age|$ttl|$alias_name|$unit|$pid|$log"
  done
}

if [[ ${1:-} == --list ]]; then
  printf '%-22s %-9s %8s %8s %-12s %s\n' ID STATE AGE TTL ALIAS TARGET
  worker_rows | while IFS='|' read -r id state age ttl al unit pid log; do
    printf '%-22s %-9s %7ss %7ss %-12s %s\n' "$id" "$state" "$age" "$ttl" "$al" "${unit:-pid=$pid}"
  done
  exit 0
fi

if [[ ${1:-} == --reap ]]; then
  all=0; [[ ${2:-} == --all ]] && all=1
  n=0
  worker_rows | while IFS='|' read -r id state age ttl al unit pid log; do
    if [[ $state == ORPHANED ]] || { (( all )) && [[ $state == running ]]; }; then
      if [[ -n $unit ]]; then
        systemctl --user stop "$unit" 2>/dev/null || true
        systemctl --user reset-failed "$unit" 2>/dev/null || true
      elif (( pid > 0 )); then
        kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 1; kill -KILL "$pid" 2>/dev/null || true
      fi
      printf '%s\n' "stopped $id ($al, age ${age}s)"; n=$((n+1))
    fi
    if [[ $state == finished || $state == ORPHANED ]] || (( all )); then
      rm -f "$REG/$id.json" "$REG/$id.env"
    fi
  done
  printf '%s\n' "reap complete"
  exit 0
fi

# ---------------------------------------------------------------- launch ----
[[ -r $ALIASES_FILE ]] || { printf '%s\n' "cc-worker: missing $ALIASES_FILE" >&2; exit 2; }

alias_name="${1:?usage: cc-worker.sh <alias> [opts] <prompt> | --list | --reap}"; shift

tools="Read,Grep,Glob,Bash"   # "none" = pass --tools "" (cheapest: no tool schemas)
schema="" bglog="" workdir="$PWD" session="" append="" model_override=""
ttl="30m" max_turns=""
extra=()
while (( $# )); do
  case "$1" in
    --tools)         tools="$2"; shift 2 ;;
    --schema)        schema="$2"; shift 2 ;;
    --bg)            bglog="$2"; shift 2 ;;
    --ttl)           ttl="$2"; shift 2 ;;
    --max-turns)     max_turns="$2"; shift 2 ;;
    --cwd)           workdir="$2"; shift 2 ;;
    --session)       session="$2"; shift 2 ;;
    --append-prompt) append="$2"; shift 2 ;;
    --model)         model_override="$2"; shift 2 ;;
    --)              shift; extra=("$@"); break ;;
    *)               break ;;
  esac
done
prompt="${1:?cc-worker: no prompt given}"

# ttl "30m"/"90s"/"2h" -> seconds (suffix case; no ${var: -1} needed)
case $ttl in
  *s) mult=1 ;;
  *h) mult=3600 ;;
  *)  mult=60 ;;
esac
ttl_sec=$(( ${ttl%[smh]} * mult ))

# agent-aliases.zsh is zsh-only (typeset -gA assoc arrays; §C of
# docs/bash-compatibility.md) — bash can neither parse nor run it. Ask a zsh
# subshell to run agent_alias_export_env and print NAME<TAB>VALUE lines, then
# import them as exports here. `have` is defined for the subshell because the
# interactive env chain normally supplies it. Values with embedded tabs/newlines
# would break the pair format — same constraint the old envfile had.
alias_env_pairs() {
  zsh -f -c '
    have() { command -v -- "$1" >/dev/null 2>&1; }
    [[ -r $1 ]] || { print -u2 "cc-worker: missing $1"; exit 2 }
    source $1
    agent_alias_export_env "$2" || exit 3
    local n
    for n in $AGENT_ALIAS_ENV_NAMES; do
      printf "%s\t%s\n" "$n" "${AGENT_ALIAS_ENV[$n]}"
    done
  ' alias_env_pairs "$ALIASES_FILE" "$1"
}
_alias_env=$(alias_env_pairs "$alias_name") || {
  printf '%s\n' "cc-worker: could not load env for alias $alias_name via zsh ($ALIASES_FILE)" >&2
  exit 2
}
AGENT_ALIAS_ENV_NAMES=()
while IFS=$'\t' read -r _n _v; do
  [[ -n $_n ]] || continue
  export "$_n=$_v"
  AGENT_ALIAS_ENV_NAMES+=("$_n")
done <<EOF
$_alias_env
EOF

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

args=()
args=(-p "$prompt" --output-format json --permission-mode bypassPermissions)
[[ -n $model_override ]] && args+=(--model "$model_override")
# NB: an empty/"none" toolset must still emit the flag, otherwise Claude Code
# loads ALL built-in tools (~15k tokens). Never guard this with [[ -n ]].
if [[ $tools == none || -z $tools ]]; then args+=(--tools "")
else args+=(--tools "$tools"); fi
[[ -n $schema ]] && args+=(--json-schema "$schema")
[[ -n $session ]] && args+=(--session-id "$session")
[[ -n $append ]] && args+=(--append-system-prompt "$append")
[[ -n $max_turns ]] && args+=(--max-turns "$max_turns")
# Workers get no MCP servers and no inherited settings: that is the bulk of the
# token overhead (17.4k -> ~2k on a trivial call, measured 2026-08-21).
args+=(--strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources "")
(( ${#extra[@]} )) && args+=("${extra[@]}")

cd "$workdir"

if [[ -z $bglog ]]; then
  exec claude "${args[@]}"
fi

# --------------------------------------------------------- background run ---
# claude's own --bg is incompatible with -p ("--bg and --print conflict").
#
# Preferred path: a systemd transient SERVICE. It runs under the user manager
# (ppid 1/623), not under this shell, so it survives a killed tool call; and
# RuntimeMaxSec guarantees systemd terminates it even if this script dies.
# Fallback (no systemd --user): timeout + setsid, which bounds the lifetime as
# long as the timeout process itself lives.
# Sanitize via tr, not ${var//[^a-z]/}: bash pattern ranges go through the
# locale-aware fnmatch, where [a-z] can match uppercase on macOS (observed:
# 3.2 kept "X" in ccz-direct-happy-X9 while zsh stripped it). BSD tr ranges
# are byte-based, so this matches zsh's behavior deterministically.
id="ccw-$(date +%Y%m%d-%H%M%S)-$$-$(printf '%s' "$alias_name" | tr -Cd 'a-z')"
case $bglog in /*) ;; *) bglog=$PWD/$bglog ;; esac

if systemctl --user is-system-running >/dev/null 2>&1 || systemctl --user show-environment >/dev/null 2>&1; then
  envfile="$REG/$id.env"
  : >"$envfile"; chmod 600 "$envfile"
  for n in ${AGENT_ALIAS_ENV_NAMES[@]+"${AGENT_ALIAS_ENV_NAMES[@]}"}; do
    printf '%s=%s\n' "$n" "${!n}" >>"$envfile"
  done
  printf '%s\n' "PATH=$PATH" >>"$envfile"
  claude_bin=$(command -v claude 2>/dev/null || printf '%s' claude)
  systemd-run --user --quiet --unit="$id" --collect \
    --property=RuntimeMaxSec="$ttl_sec" \
    --property=EnvironmentFile="$envfile" \
    --property=WorkingDirectory="$workdir" \
    --property=StandardOutput="file:$bglog" \
    --property=StandardError="file:${bglog%.json}.err" \
    -- "$claude_bin" "${args[@]}"
  jq -n --arg id "$id" --arg unit "$id.service" --arg a "$alias_name" \
        --arg log "$bglog" --argjson ttl "$ttl_sec" --argjson st "$(date +%s)" \
        '{id:$id,unit:$unit,pid:0,alias:$a,log:$log,ttl_sec:$ttl,started:$st}' >"$REG/$id.json"
  printf '%s\n' "{\"id\":\"$id\",\"unit\":\"$id.service\",\"log\":\"$bglog\",\"ttl_sec\":$ttl_sec}"
else
  setsid timeout --kill-after=30s "$ttl_sec" claude "${args[@]}" \
    >"$bglog" 2>"${bglog%.json}.err" &
  wpid=$!
  jq -n --arg id "$id" --arg a "$alias_name" --arg log "$bglog" \
        --argjson pid "$wpid" --argjson ttl "$ttl_sec" --argjson st "$(date +%s)" \
        '{id:$id,unit:"",pid:$pid,alias:$a,log:$log,ttl_sec:$ttl,started:$st}' >"$REG/$id.json"
  printf '%s\n' "{\"id\":\"$id\",\"pid\":$wpid,\"log\":\"$bglog\",\"ttl_sec\":$ttl_sec}"
fi
