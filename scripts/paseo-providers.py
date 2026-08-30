#!/usr/bin/env python3
"""Merge this repo's desired paseo agent providers into ~/.paseo/config.json.

Run by scripts/deploy.d/81_paseo_providers.zsh; safe to run by hand.

WHY A MERGE AND NOT A SYMLINK
~/.paseo/config.json is app-owned and machine-specific: paseo itself rewrites
it, and it carries daemon.hostnames (the box's own name), a per-machine
auth.password bcrypt hash, and terminal/agent profiles set from the UI. Linking
one repo file over it -- the treatment most configs get in 20_symlinks.zsh --
would clobber all of that on every box. So this reads the live file, sets only
the keys the repo owns, and writes everything else back untouched. Same reason
Karabiner is generated rather than symlinked (see 78_karabiner.zsh).

WHY THE TOKEN IS NOT IN THE TEMPLATE
paseo hands provider `env` to the spawned agent verbatim and expands nothing
(provider-registry.ts, `env: override.env`), so the Z.AI token must sit literal
in config.json. This repo is public, so configs/ai/paseo/providers.json carries
the placeholder __ZAI_API_KEY__ and this script substitutes it from the box's
own ~/.gjc/agent/.env -- rendered from ~/.local/secrets by secrets-render.zsh
(services/gjc/env.yaml, gated `all`, so it is present on every box). The secret
therefore never enters the repo and is never copied between machines.

Exit status: 0 on success (changed or already current), 1 on failure.
Prints exactly one of "changed", "unchanged", or "skip: <reason>"; the caller
reloads the daemon only on "changed". Never prints the token.
"""
import argparse
import datetime
import json
import os
import sys

CONFIG = os.path.expanduser("~/.paseo/config.json")
GJC_ENV = os.path.expanduser("~/.gjc/agent/.env")
GJC_BIN = os.path.expanduser("~/.local/bin/gjc")


def skip(reason):
    print("skip: %s" % reason)
    sys.exit(0)


def fail(reason):
    print("FAIL: %s" % reason, file=sys.stderr)
    sys.exit(1)


def read_zai_key(path):
    """Pull ZAI_API_KEY out of the rendered dotenv. sops writes it verbatim:
    no quoting, no escaping, so split on the first '=' and take the rest."""
    try:
        with open(path) as handle:
            for line in handle:
                line = line.strip()
                if line.startswith("ZAI_API_KEY="):
                    return line.split("=", 1)[1].strip()
    except OSError as exc:
        fail("cannot read %s (%s)" % (path, exc))
    return None


def substitute(node, gjc_bin, token):
    """Walk the template replacing the two placeholders in string leaves."""
    if isinstance(node, dict):
        return {k: substitute(v, gjc_bin, token) for k, v in node.items()
                if k != "_comment"}
    if isinstance(node, list):
        return [substitute(v, gjc_bin, token) for v in node]
    if isinstance(node, str):
        return node.replace("__GJC_BIN__", gjc_bin).replace("__ZAI_API_KEY__", token)
    return node


def upsert_profiles(existing, desired):
    """Match on `name`, not `id`: the name is what the repo means, while ids are
    generated per daemon and a user may already have re-created the profile from
    the UI under a different id. Preserve the live entry's id in that case so
    anything referencing it keeps working."""
    out = list(existing)
    for want in desired:
        for index, have in enumerate(out):
            if have.get("name") == want.get("name"):
                merged = dict(want)
                merged["id"] = have.get("id", want["id"])
                out[index] = merged
                break
        else:
            out.append(dict(want))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("template")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(CONFIG):
        skip("no %s (paseo not set up on this box)" % CONFIG)
    if not os.path.exists(GJC_BIN):
        skip("no gjc at %s" % GJC_BIN)
    if not os.path.exists(GJC_ENV):
        skip("no %s (secrets not rendered yet)" % GJC_ENV)

    token = read_zai_key(GJC_ENV)
    if not token:
        skip("ZAI_API_KEY not in %s" % GJC_ENV)

    with open(args.template) as handle:
        desired = substitute(json.load(handle), GJC_BIN, token)

    try:
        with open(CONFIG) as handle:
            config = json.load(handle)
    except (OSError, ValueError) as exc:
        fail("cannot parse %s (%s)" % (CONFIG, exc))

    before = json.dumps(config, sort_keys=True)

    providers = config.setdefault("agents", {}).setdefault("providers", {})
    providers.update(desired.get("agents", {}).get("providers", {}))

    want_profiles = desired.get("daemon", {}).get("agentProfiles", [])
    if want_profiles:
        daemon = config.setdefault("daemon", {})
        daemon["agentProfiles"] = upsert_profiles(
            daemon.get("agentProfiles", []), want_profiles)

    if json.dumps(config, sort_keys=True) == before:
        print("unchanged")
        return

    if args.dry_run:
        print("changed")
        return

    # Back up the live file before replacing it, matching the naming paseo's own
    # tooling uses (config.json.pre-<what>-<stamp>), then swap atomically so a
    # crash mid-write can never leave a truncated config behind.
    stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    backup = "%s.pre-paseo-providers-%s" % (CONFIG, stamp)
    with open(CONFIG) as src, open(backup, "w") as dst:
        dst.write(src.read())
    os.chmod(backup, 0o600)

    tmp = CONFIG + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, CONFIG)

    with open(CONFIG) as handle:  # prove the written file still parses
        json.load(handle)

    print("changed")


if __name__ == "__main__":
    main()
