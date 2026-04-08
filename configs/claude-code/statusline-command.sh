#!/usr/bin/env bash
# Claude Code statusLine wrapper
# Blends PS1-style user@host:dir prefix with the OMC HUD output.

# Read stdin once into a variable so it can be reused
input=$(cat)

# Extract current working directory from JSON (fall back to shell cwd)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
cwd="${cwd:-$(pwd)}"

# Build PS1-style prefix using ANSI colors (green user@host, blue dir)
user=$(whoami)
host=$(hostname -s)
prefix=$(printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' "$user" "$host" "$cwd")

# Run the OMC HUD with the same stdin, capture its output
hud_output=$(printf '%s' "$input" | node /home/ctaylor/.claude/hud/omc-hud.mjs 2>/dev/null)

# Combine: prefix | HUD output (skip separator if HUD produced nothing)
if [ -n "$hud_output" ]; then
    printf '%s \033[00m|\033[00m %s\n' "$prefix" "$hud_output"
else
    printf '%s\n' "$prefix"
fi
