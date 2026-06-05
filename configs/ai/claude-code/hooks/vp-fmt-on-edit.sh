#!/usr/bin/env bash
# PostToolUse hook — Pattern A "format-on-edit".
#
# After Claude edits a JS/TS file that lives in a Vite+ workspace, run
# `vp fmt --fix` on just that file (honoring the oxfmt settings in the nearest
# vite.config.*). This keeps the file in commit-format at all times, so the
# pre-commit / vite formatter has nothing left to reformat — which removes the
# "File has been modified since read" stale-edit failures at their source.
#
# When the formatter actually changes the file, we hand Claude a diff via
# `additionalContext` so its in-context copy isn't silently stale (a
# deterministic, targeted "reread" without dumping the whole file).
#
# Fully defensive: any non-applicable file, missing tool, broken vp install,
# uninstalled worktree, or formatter error => silent no-op (exit 0). It never
# blocks an edit (PostToolUse runs after the tool already applied).

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
command -v vp >/dev/null 2>&1 || exit 0

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

# Only formats oxfmt/vp handles; everything else is a no-op.
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.mts|*.cts|*.vue|*.css|*.scss|*.json) ;;
  *) exit 0 ;;
esac

# Walk up to the nearest Vite+ workspace (a directory with a vite.config.*).
# vp resolves its config + oxfmt rules from there.
dir=$(CDPATH= cd -- "$(dirname -- "$file")" && pwd) || exit 0
root=""
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if ls "$dir"/vite.config.* >/dev/null 2>&1; then
    root="$dir"
    break
  fi
  dir=$(dirname -- "$dir")
done
[ -n "$root" ] || exit 0

before=$(cat -- "$file" 2>/dev/null) || exit 0

# Format just this file, from the workspace root so vite.config oxfmt applies.
# Timeboxed and silenced: on ANY failure we leave the file as-is and say nothing.
( cd -- "$root" && timeout 25 vp fmt --fix -- "$file" ) >/dev/null 2>&1 || exit 0

after=$(cat -- "$file" 2>/dev/null) || exit 0
[ "$before" != "$after" ] || exit 0   # formatter changed nothing -> stay quiet

diff=$(diff -- <(printf '%s' "$before") <(printf '%s' "$after") 2>/dev/null | head -200)
[ -n "$diff" ] || exit 0

ctx="vp fmt --fix (oxfmt) reformatted this file AFTER your edit: ${file}
Your in-context copy is now STALE — disk differs. Changes ('<' your edit, '>' formatted):
${diff}

If you will edit this file again, re-read it first so your old_string matches disk."

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
