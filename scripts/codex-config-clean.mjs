#!/usr/bin/env node
// Git clean filter for the Codex config.toml (configs/ai/codex/config.toml).
//
// Codex + `omx setup` write machine-specific RUNTIME TRUST STATE directly into
// config.toml — `[projects."…"]` trust acks and `[hooks.state."…"]` hook-trust
// hashes. Because that file is the symlink target of ~/.codex/config.toml, every
// session re-pollutes the tracked dotfile (this is what clobbered it historically).
//
// This filter runs on `git add`: the WORKING TREE keeps the full file (Codex reads
// it unchanged at runtime), but the version stored in git has the runtime tables
// stripped. Real configuration (model, features, mcp_servers, plugins, tui, …) is
// preserved verbatim. Trust state regenerates per-machine on first run.
//
// Enable (per clone — set by the dotfiles deploy step):
//   git config filter.codex-clean.clean "node scripts/codex-config-clean.mjs"
// Wired via .gitattributes:  configs/ai/codex/config.toml filter=codex-clean
//
// Idempotent: running it on already-clean input is a no-op.

import { readFileSync } from 'node:fs';

const DROP_HEADER = /^\[(projects\.|hooks\.state(\]|\.))/;
// Sentinel comments that wrap the (now-stripped) OMX hook trust state. Without the
// tables they describe, they are misleading orphans — drop them too.
const DROP_COMMENT = new Set([
  '# OMX-owned Codex hook trust state',
  '# Trusts only setup-managed native hook wrappers.',
  '# End OMX-owned Codex hook trust state',
]);

const input = readFileSync(0, 'utf8');
const lines = input.split('\n');
const out = [];
let seenHeader = false;
let dropping = false;

for (const line of lines) {
  if (DROP_COMMENT.has(line.trim())) continue;
  const isHeader = /^\s*\[/.test(line);
  if (isHeader) {
    seenHeader = true;
    dropping = DROP_HEADER.test(line.trim());
    if (!dropping) out.push(line);
    continue;
  }
  // Top-level keys/comments before the first table are always config — keep.
  if (!seenHeader) {
    out.push(line);
    continue;
  }
  // Inside a table: emit only if the current table is kept.
  if (!dropping) out.push(line);
}

// Collapse any run of >1 blank line left by stripped tables into a single blank,
// and trim trailing blanks to exactly one terminating newline.
const collapsed = [];
for (const line of out) {
  if (line === '' && collapsed.length && collapsed[collapsed.length - 1] === '') continue;
  collapsed.push(line);
}
while (collapsed.length && collapsed[collapsed.length - 1] === '') collapsed.pop();

process.stdout.write(collapsed.join('\n') + '\n');
