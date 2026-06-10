#!/usr/bin/env node
/**
 * User-owned OMX hook replacement for ~/.codex/hooks.json.
 *
 * Why this exists
 * ---------------
 * OMX plugin/setup owns the default hook command that calls:
 *   dist/scripts/codex-native-hook.js
 * That managed hook is useful for session context and explicit keyword routing,
 * but it also bundles stricter guardrails that this user wants disabled by
 * default: broad Bash non-zero PostToolUse blocking, Stop-hook workflow/final
 * handoff blockers, auto-nudge, document-refresh nudges, sloppy-fallback nudges,
 * and Lore commit enforcement.
 *
 * Durable update rule
 * -------------------
 * Do not edit installed plugin files under mise/npm paths. This wrapper is
 * user-owned. It calls the current OMX plugin through the mise "latest" symlink
 * only for events enabled in ~/.codex/.omx-config.json.
 *
 * Important future-update warning
 * -------------------------------
 * Running `omx setup` may append fresh managed hooks back into hooks.json because
 * setup always installs its native wrappers. If that happens, remove hook commands
 * containing `codex-native-hook.js` again and keep this wrapper command. The
 * managed hook detector only recognizes direct commands to codex-native-hook.js;
 * this wrapper is intentionally named differently so setup preserves it as a
 * user-owned hook.
 *
 * Config flags read from ~/.codex/.omx-config.json:
 *
 *   {
 *     "userOwnedOmxHooks": {
 *       "originalPassThrough": {
 *         "SessionStart": true,
 *         "UserPromptSubmit": true,
 *         "PreToolUse": false,
 *         "PostToolUse": false,
 *         "Stop": false
 *       },
 *       "originalEnvironment": {
 *         "OMX_LORE_COMMIT_GUARD": "0"
 *       }
 *     },
 *     "promptRouting": { "triage": { "enabled": false } },
 *     "autoNudge": { "enabled": false }
 *   }
 *
 * Per-event env overrides, useful for temporary testing:
 *   OMX_USER_HOOK_PASSTHROUGH_SESSIONSTART=0|1
 *   OMX_USER_HOOK_PASSTHROUGH_USERPROMPTSUBMIT=0|1
 *   OMX_USER_HOOK_PASSTHROUGH_PRETOOLUSE=0|1
 *   OMX_USER_HOOK_PASSTHROUGH_POSTTOOLUSE=0|1
 *   OMX_USER_HOOK_PASSTHROUGH_STOP=0|1
 *
 * Diff from stock OMX managed hooks
 * ---------------------------------
 * Enabled by default:
 *   - SessionStart: preserves OMX session/HUD/context bookkeeping.
 *   - UserPromptSubmit: preserves explicit keyword/skill routing context.
 *
 * Disabled by default:
 *   - PreToolUse: disables bundled Bash preflight guardrails, including Lore
 *     commit enforcement, document refresh warnings, sloppy fallback warnings,
 *     and native/tmux OMX command blocks.
 *   - PostToolUse: disables broad non-zero Bash/MCP retry blockers.
 *   - Stop: disables workflow/final-handoff blockers, auto-nudge, sloppy diff,
 *     document-refresh Stop advisories, and mode continuation blockers.
 *
 * If a future OMX release splits these behaviors into official config flags,
 * prefer those flags and simplify this wrapper back toward direct passthrough.
 */

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import { execSync } from 'node:child_process';

const NODE = process.execPath;

// Dynamic ORIGINAL_HOOK discovery: prefer the mise/npm-oh-my-codex path,
// but fall back to the vite-plus installation on macOS.
let ORIGINAL_HOOK = '/home/ctaylor/.local/share/mise/installs/npm-oh-my-codex/latest/lib/node_modules/oh-my-codex/dist/scripts/codex-native-hook.js';
if (!existsSync(ORIGINAL_HOOK)) {
  const candidates = [
    '/Users/ctaylor/.vite-plus/js_runtime/node/24.16.0/lib/node_modules/oh-my-codex/dist/scripts/codex-native-hook.js',
    '/Users/ctaylor/.vite-plus/js_runtime/node/24.15.0/lib/node_modules/oh-my-codex/dist/scripts/codex-native-hook.js',
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      ORIGINAL_HOOK = candidate;
      break;
    }
  }
  if (!existsSync(ORIGINAL_HOOK)) {
    try {
      const result = execSync('find /Users/ctaylor/.vite-plus -path "*/codex-native-hook.js" 2>/dev/null | head -1', { encoding: 'utf8' });
      const found = result.trim();
      if (found && existsSync(found)) {
        ORIGINAL_HOOK = found;
      }
    } catch {
      // Keep the default
    }
  }
}
const CONFIG_PATH = join(homedir(), '.codex', '.omx-config.json');

const DEFAULT_PASS_THROUGH = {
  SessionStart: true,
  UserPromptSubmit: true,
  PreToolUse: false,
  PostToolUse: false,
  Stop: false,
};

const DEFAULT_ORIGINAL_ENVIRONMENT = {
  OMX_LORE_COMMIT_GUARD: '0',
};

function readAllStdin() {
  return readFileSync(0, 'utf8');
}

function safeParseJson(text, fallback) {
  try {
    return JSON.parse(text);
  } catch {
    return fallback;
  }
}

function readConfig() {
  if (!existsSync(CONFIG_PATH)) return {};
  return safeParseJson(readFileSync(CONFIG_PATH, 'utf8'), {});
}

function readHookEventName(payload, argvEvent) {
  const raw = String(
    payload?.hook_event_name ??
      payload?.hookEventName ??
      payload?.event ??
      payload?.name ??
      argvEvent ??
      '',
  ).trim();
  return Object.hasOwn(DEFAULT_PASS_THROUGH, raw) ? raw : argvEvent;
}

function envBool(name) {
  const value = process.env[name];
  if (value === undefined) return undefined;
  const normalized = value.trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return undefined;
}

function envFlagNameForEvent(eventName) {
  return `OMX_USER_HOOK_PASSTHROUGH_${eventName.toUpperCase()}`;
}

function shouldPassThrough(eventName, config) {
  const configured = config?.userOwnedOmxHooks?.originalPassThrough?.[eventName];
  const defaultValue = DEFAULT_PASS_THROUGH[eventName] === true;
  const configValue = typeof configured === 'boolean' ? configured : defaultValue;
  return envBool(envFlagNameForEvent(eventName)) ?? configValue;
}

function buildOriginalEnvironment(config) {
  const configured = config?.userOwnedOmxHooks?.originalEnvironment;
  const explicit = configured && typeof configured === 'object' && !Array.isArray(configured) ? configured : {};
  return Object.fromEntries(
    Object.entries({ ...DEFAULT_ORIGINAL_ENVIRONMENT, ...explicit }).filter(([, value]) => value !== null && value !== undefined),
  );
}

function writeSafeEmptyResponse(eventName) {
  if (eventName === 'Stop') {
    process.stdout.write('{}\n');
  }
}

const rawStdin = readAllStdin();
const payload = safeParseJson(rawStdin.trim() || '{}', {});
const argvEvent = process.argv[2];
const eventName = readHookEventName(payload, argvEvent);
const config = readConfig();

if (!eventName || !shouldPassThrough(eventName, config)) {
  writeSafeEmptyResponse(eventName);
  process.exit(0);
}

if (!existsSync(ORIGINAL_HOOK)) {
  process.stderr.write(`[omx-user-filtered-hook] Original OMX hook not found: ${ORIGINAL_HOOK}\n`);
  writeSafeEmptyResponse(eventName);
  process.exit(0);
}

const child = spawnSync(NODE, [ORIGINAL_HOOK], {
  input: rawStdin,
  encoding: 'utf8',
  env: {
    ...process.env,
    ...buildOriginalEnvironment(config),
  },
});

if (child.stdout) process.stdout.write(child.stdout);
if (child.stderr) process.stderr.write(child.stderr);
if (child.error) {
  process.stderr.write(`[omx-user-filtered-hook] Failed to run original OMX hook: ${child.error.message}\n`);
  writeSafeEmptyResponse(eventName);
  process.exit(0);
}

process.exit(child.status ?? 0);
