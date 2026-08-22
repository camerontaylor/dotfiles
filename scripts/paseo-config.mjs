#!/usr/bin/env node
// paseo-config.mjs - idempotently patch ~/.paseo/config.json with the fleet's
// managed settings, preserving everything the daemon owns.
//
// WHY A PATCHER AND NOT A SYMLINK (the usual dotfiles move):
//   The daemon writes config.json itself - `paseo daemon set-password`, the
//   relay toggle, provider enable/disable from the desktop GUI, plugin state.
//   It does so with writeFileSync(tmp) + renameSync(tmp, target) at mode 0600
//   (packages/server/src/server/private-files.ts). An atomic rename REPLACES
//   whatever sits at the target path, so a symlink into this repo survives
//   exactly until the first daemon-side write, then silently becomes a real
//   file and dotfiles stops applying. Same reasoning as the Karabiner JSON in
//   scripts/deploy.d/20_symlinks.zsh - GUI/daemon-owned files get generated,
//   not linked.
//
//   So this merges OUR keys in and leaves the rest alone. Re-running is a
//   no-op when nothing changed (it does not rewrite the file, so it does not
//   provoke a daemon file-watch reload for nothing).
//
// Usage:
//   paseo-config.mjs [--home DIR] [--listen HOST:PORT] [--hostname NAME]...
//                    [--web-ui true|false] [--relay true|false]
//                    [--password-hash BCRYPT] [--dry-run]
//
// Node is guaranteed on every fleet box through mise (configs/mise.toml pins
// node 24), which is also why the JSON handling lives here instead of in the
// calling shell script: no jq dependency, no BSD-vs-GNU sed games.

import { readFileSync, writeFileSync, renameSync, rmSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const PRIVATE_FILE_MODE = 0o600;
const PRIVATE_DIR_MODE = 0o700;
const SCHEMA_URL = "https://paseo.sh/schemas/paseo.config.v1.json";

function usage(code) {
  process.stderr.write(
    [
      "usage: paseo-config.mjs [options]",
      "  --home DIR             Paseo home (default: $PASEO_HOME or ~/.paseo)",
      "  --listen HOST:PORT     daemon.listen",
      "  --hostname NAME        append to daemon.hostnames (repeatable)",
      "  --web-ui true|false    features.webUi.enabled",
      "  --relay true|false     daemon.relay.enabled",
      "  --password-hash HASH   daemon.auth.password (bcrypt)",
      "  --dry-run              print the merged config, write nothing",
      "",
    ].join("\n"),
  );
  process.exit(code);
}

function parseBool(value, flag) {
  if (value === "true") return true;
  if (value === "false") return false;
  process.stderr.write(`paseo-config: ${flag} expects true|false, got ${value}\n`);
  process.exit(2);
}

const opts = { hostnames: [] };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const arg = argv[i];
  const next = () => {
    const value = argv[++i];
    if (value === undefined) {
      process.stderr.write(`paseo-config: ${arg} requires a value\n`);
      process.exit(2);
    }
    return value;
  };
  switch (arg) {
    case "--home": opts.home = next(); break;
    case "--listen": opts.listen = next(); break;
    case "--hostname": opts.hostnames.push(next()); break;
    case "--web-ui": opts.webUi = parseBool(next(), arg); break;
    case "--relay": opts.relay = parseBool(next(), arg); break;
    case "--password-hash": opts.passwordHash = next(); break;
    case "--dry-run": opts.dryRun = true; break;
    case "-h": case "--help": usage(0); break;
    default:
      process.stderr.write(`paseo-config: unknown option ${arg}\n`);
      usage(2);
  }
}

const paseoHome = path.resolve(opts.home ?? process.env.PASEO_HOME ?? path.join(homedir(), ".paseo"));
const configPath = path.join(paseoHome, "config.json");

let existing = {};
let hadFile = false;
try {
  existing = JSON.parse(readFileSync(configPath, "utf8"));
  hadFile = true;
} catch (err) {
  if (err.code !== "ENOENT") {
    // A corrupt config is not ours to silently overwrite - the daemon refuses
    // to start on it too, and clobbering would take the password hash and any
    // GUI-set provider state with it.
    process.stderr.write(`paseo-config: cannot parse ${configPath}: ${err.message}\n`);
    process.stderr.write("  fix or move the file aside, then re-run.\n");
    process.exit(1);
  }
}
if (existing === null || typeof existing !== "object" || Array.isArray(existing)) {
  process.stderr.write(`paseo-config: ${configPath} is not a JSON object\n`);
  process.exit(1);
}

// Deep-copy so the "did anything change?" comparison below is honest.
const merged = JSON.parse(JSON.stringify(existing));
const branch = (obj, key) => {
  if (obj[key] === null || typeof obj[key] !== "object" || Array.isArray(obj[key])) obj[key] = {};
  return obj[key];
};

merged.$schema ??= SCHEMA_URL;
merged.version ??= 1;

const daemon = branch(merged, "daemon");
if (opts.listen !== undefined) daemon.listen = opts.listen;
if (opts.passwordHash !== undefined) branch(daemon, "auth").password = opts.passwordHash;
// Set relay explicitly rather than relying on the default. Per the upstream
// configuration docs, a home whose config OMITTED daemon.relay.enabled when the
// daemon started keeps the legacy relay-enabled behaviour for compatibility -
// so "absent" does not reliably mean "off" on a pre-existing home.
if (opts.relay !== undefined) branch(daemon, "relay").enabled = opts.relay;
if (opts.webUi !== undefined) branch(branch(merged, "features"), "webUi").enabled = opts.webUi;

if (opts.hostnames.length > 0) {
  // `true` means "allow any Host header" - if a human set that deliberately,
  // narrowing it back to a list would be a silent security-relevant change.
  if (daemon.hostnames === true) {
    process.stderr.write("paseo-config: daemon.hostnames is true (any host); leaving it alone\n");
  } else {
    const current = Array.isArray(daemon.hostnames) ? daemon.hostnames : [];
    const seen = new Set(current.map((h) => String(h).trim().toLowerCase()));
    const added = [];
    for (const hostname of opts.hostnames) {
      const key = hostname.trim().toLowerCase();
      if (key && !seen.has(key)) {
        seen.add(key);
        added.push(hostname);
      }
    }
    // Append, never replace: the daemon and the desktop app add entries here too.
    if (current.length > 0 || added.length > 0) daemon.hostnames = [...current, ...added];
  }
}

const serialized = JSON.stringify(merged, null, 2) + "\n";

if (opts.dryRun) {
  process.stdout.write(serialized);
  process.exit(0);
}

if (hadFile && JSON.stringify(existing, null, 2) + "\n" === serialized) {
  process.stdout.write(`  config already current: ${configPath}\n`);
  process.exit(0);
}

// Same write discipline the daemon uses: 0600 temp + atomic rename, inside a
// 0700 home. config.json holds the bcrypt password hash.
mkdirSync(paseoHome, { recursive: true, mode: PRIVATE_DIR_MODE });
const tmpPath = path.join(paseoHome, `.config.json.${process.pid}.tmp`);
try {
  writeFileSync(tmpPath, serialized, { mode: PRIVATE_FILE_MODE });
  renameSync(tmpPath, configPath);
} catch (err) {
  rmSync(tmpPath, { force: true });
  process.stderr.write(`paseo-config: failed to write ${configPath}: ${err.message}\n`);
  process.exit(1);
}

process.stdout.write(`  ${hadFile ? "updated" : "created"} ${configPath}\n`);
