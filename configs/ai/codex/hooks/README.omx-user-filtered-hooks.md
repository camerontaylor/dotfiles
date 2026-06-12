# User-owned OMX filtered hooks

`~/.codex/hooks.json` intentionally points at `~/.codex/hooks/omx-user-filtered-hook.mjs` instead of the direct OMX-managed `codex-native-hook` command.

The wrapper keeps useful stock OMX behavior by default:

- `SessionStart`: enabled
- `UserPromptSubmit`: enabled

The wrapper disables the behavior currently considered noisy/offensive by default:

- `PreToolUse`: disabled
- `PostToolUse`: disabled
- `Stop`: disabled
- `OMX_LORE_COMMIT_GUARD`: set to `0` for any event that is passed through
- `promptRouting.triage.enabled`: set to `false` in `~/.codex/.omx-config.json`
- `autoNudge.enabled`: set to `false` in `~/.codex/.omx-config.json`

## Future updates

Do not patch installed OMX plugin files under `~/.codex/plugins/cache/...` or `~/.local/share/mise/installs/npm-oh-my-codex/...`.

If `omx setup`, plugin-scoped hooks, or a plugin update re-adds direct `codex-native-hook` entries, remove/disable those managed entries again and leave the wrapper entries. Direct `codex-native-hook` commands are setup-owned; this wrapper is user-owned.

## Temporary overrides

Set any of these to `1` or `0` for one Codex launch/session:

- `OMX_USER_HOOK_PASSTHROUGH_SESSIONSTART`
- `OMX_USER_HOOK_PASSTHROUGH_USERPROMPTSUBMIT`
- `OMX_USER_HOOK_PASSTHROUGH_PRETOOLUSE`
- `OMX_USER_HOOK_PASSTHROUGH_POSTTOOLUSE`
- `OMX_USER_HOOK_PASSTHROUGH_STOP`

Persistent flags live in `~/.codex/.omx-config.json` under `userOwnedOmxHooks.originalPassThrough`.
