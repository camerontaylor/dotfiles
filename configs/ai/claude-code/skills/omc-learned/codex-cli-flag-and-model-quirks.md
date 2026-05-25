---
name: Codex CLI flag and model quirks
description: Use when invoking codex CLI from scripts, ralplan critic passes, or any non-interactive Codex workflow — the obvious flags don't work and the obvious model is unsupported.
triggers:
  - codex --approval-mode
  - codex unexpected argument
  - codex o4-mini not supported
  - "model is not supported when using Codex with a ChatGPT account"
  - codex exec usage
  - critic codex
  - ralplan --critic codex
scope: personal
category: expertise
---

# Codex CLI Flag and Model Quirks

## The Insight

The `codex` CLI (OpenAI Codex CLI v0.120.0+) has two non-obvious failure modes that bite every time you script against it:

1. **`--approval-mode` does not exist.** Many examples and older documentation reference `--approval-mode full-auto` or similar. The actual flag is `--full-auto`. Passing `--approval-mode` produces:
   ```
   error: unexpected argument '--approval-mode' found
     tip: to pass '--approval-mode' as a value, use '-- --approval-mode'
   ```

2. **`o4-mini` is not available with a ChatGPT account.** Selecting it via `-m o4-mini` (or via config) produces a 400 error mid-stream:
   ```
   ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'o4-mini' model is not supported when using Codex with a ChatGPT account."}}
   ```
   The default model works. There is no public list of which models are blocked under ChatGPT-account auth — assume the default is the only safe choice unless you've verified otherwise for your account tier.

The principle: Codex CLI is OpenAI's tool, but its flag surface and model availability are not just renames of the old surface — both have been quietly tightened, and the error messages are emitted late (sometimes after the prompt has been ingested), so a failure looks like a content/prompt problem rather than a CLI configuration problem.

## Why This Matters

When using ralplan with `--critic codex` (or any pipeline that shells out to Codex from another agent), a misconfigured Codex invocation looks like an agent failure, not a CLI failure. You'll spend time tweaking prompts before noticing that the actual error is in the first few lines of stderr. Both errors are hard to Google because the OpenAI documentation site reflects a different surface than the bundled CLI binary.

## Recognition Pattern

This applies when:

- Invoking `codex` non-interactively (e.g., `codex exec ...`) from Bash, scripts, or another agent
- Errors of the form "unexpected argument" referencing approval/model flags
- 400 errors with `invalid_request_error` after the session has already started
- `ralplan --critic codex` immediately failing without producing a verdict

Quick verification of installed surface:

```bash
codex exec --help | head -40
# Look for: --full-auto (NOT --approval-mode)
# Look for: -m, --model <MODEL> (no list of valid models in help)
```

## The Approach

1. **Use `--full-auto` for non-interactive runs.** This grants the equivalent of "auto-approve everything" without the rejected `--approval-mode` flag.

2. **Omit `-m` unless you've verified the model works for your account.** The default model is the safe choice. If a specific model is required, test it standalone first:
   ```bash
   echo "say hello" | codex exec --full-auto -m <candidate-model> -
   # If you get "model not supported", drop the -m flag.
   ```

3. **Pipe prompts via stdin with the `-` argument**: this is the documented pattern and avoids quoting issues with multi-line prompts:
   ```bash
   cat /tmp/prompt.md | codex exec --full-auto -
   ```

4. **Capture and inspect stderr immediately** when wrapping Codex in another agent. The 400 errors appear early in the output and are easy to miss if you're tailing only the structured response section.

5. **Do NOT fall back to interactive `codex` from a script** as a workaround — interactive mode requires a TTY and will hang silently when run from a non-TTY context.

## Example

Working invocation from a Bash subagent (e.g., ralplan critic):

```bash
cat > /tmp/codex-critic.md << 'EOF'
You are a critic. Evaluate this plan: ...
EOF

# Correct: --full-auto, no -m, stdin via -
cat /tmp/codex-critic.md | codex exec --full-auto - 2>&1 | tail -200
```

Broken patterns to avoid:

```bash
# WRONG: --approval-mode does not exist
codex --approval-mode full-auto -q "..."

# WRONG: o4-mini blocked on ChatGPT account
cat /tmp/prompt.md | codex exec -m o4-mini --full-auto -

# WRONG: trying to pass prompt as argument with newlines
codex exec --full-auto "$(cat /tmp/prompt.md)"  # quoting/escaping fragile
```

## Notes

- This is `personal` scope because it follows my account tier, not the project. Other engineers on different tiers may not hit the `o4-mini` block.
- Re-test after Codex CLI upgrades — both the flag surface and model availability have changed across minor versions.
