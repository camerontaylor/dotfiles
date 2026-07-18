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

# Model display name, if present in the statusline payload
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

if [ -n "$model" ]; then
    printf '%s \033[00m|\033[00m %s\n' "$prefix" "$model"
else
    printf '%s\n' "$prefix"
fi
