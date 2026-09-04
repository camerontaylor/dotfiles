#!/usr/bin/env bash
# Claude Code statusLine: PS1-style user@host:dir prefix + model name.

# Read stdin once into a variable so it can be reused
input=$(cat)

# Extract current working directory from JSON (fall back to shell cwd)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
cwd="${cwd:-$(pwd)}"

# Build PS1-style prefix using ANSI colors (green user@host, blue dir)
user=$(whoami)
host=$(hostname -s)
prefix=$(printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' "$user" "$host" "$cwd")

# Publish the plan-quota slice for agents/UI to read (free: no network call, no token).
# rate_limits is ABSENT until the first API response and after a window resets --
# absent means "no data", not zero, so a failed extraction leaves any prior file intact.
quota_out="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-latest.json"
if printf '%s' "$input" | jq -c 'select(.rate_limits != null) | {
        fetched_at: now,
        source: "claude-code-statusline",
        session_id: .session_id,
        rate_limits: .rate_limits,
        cost: .cost,
        context_window: .context_window
    }' > "${quota_out}.tmp" 2>/dev/null && [ -s "${quota_out}.tmp" ]; then
    mv -f "${quota_out}.tmp" "$quota_out"
else
    rm -f "${quota_out}.tmp"
fi

# Model display name, if present in the statusline payload
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

if [ -n "$model" ]; then
    printf '%s \033[00m|\033[00m %s\n' "$prefix" "$model"
else
    printf '%s\n' "$prefix"
fi
