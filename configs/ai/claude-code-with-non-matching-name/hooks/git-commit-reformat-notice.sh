#!/usr/bin/env bash
# PostToolUse hook (Bash) — Pattern B "commit-time reread safety net".
#
# When Claude runs `git commit` in a repo that has commit-time formatters
# (husky / lint-staged / pre-commit / a pre-commit git hook), those hooks may
# reformat the committed files. Claude's in-context copies of those files are
# then STALE, which later shows up as "String to replace not found" on the next
# Edit. This hook detects that situation and hands Claude the list of committed
# code files with a re-read nudge.
#
# This is the belt-and-suspenders to the per-edit format-on-edit hook: it only
# matters when format-on-edit isn't active (e.g. vp not installed in a worktree)
# yet a commit-time formatter still rewrote files.
#
# Fully defensive: not a git commit, no formatter tooling, no recent commit, or
# any error => silent no-op (exit 0). PostToolUse cannot block.

input=$(cat)

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0
# Only react to an actual git commit invocation.
printf '%s' "$cmd" | grep -Eq '(^|[;&| ])git([[:space:]]+-[^;&|]*)?[[:space:]]+commit\b' || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
{ [ -n "$cwd" ] && [ -d "$cwd" ]; } || cwd="$PWD"
root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" 2>/dev/null || exit 0

# Only repos that actually reformat at commit time.
has_fmt=0
[ -x .git/hooks/pre-commit ] && has_fmt=1
[ -e .husky/pre-commit ] && has_fmt=1
[ -e .pre-commit-config.yaml ] && has_fmt=1
grep -q '"lint-staged"' package.json 2>/dev/null && has_fmt=1
[ "$has_fmt" = 1 ] || exit 0

# Only if a commit actually just landed (HEAD committed in the last 90s) — this
# filters out failed commits (HEAD unchanged) and non-commit git commands.
ct=$(git log -1 --format=%ct 2>/dev/null) || exit 0
now=$(date +%s)
{ [ -n "$ct" ] && [ $((now - ct)) -lt 90 ]; } || exit 0

# Committed files a formatter would touch.
files=$(git diff-tree --no-commit-id --name-only -r --root HEAD 2>/dev/null \
        | grep -Ei '\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|vue|css|scss|json|md)$')
[ -n "$files" ] || exit 0

sha=$(git rev-parse --short HEAD 2>/dev/null)
ctx="git commit ${sha} landed in a repo with commit-time formatters (husky/lint-staged/pre-commit). Those hooks may have reformatted the committed files, so your in-context copies of them may now be STALE. Before your next Edit to any of these, re-read it so old_string matches disk:
${files}"

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
