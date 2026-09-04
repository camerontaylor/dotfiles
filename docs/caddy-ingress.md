# Caddy ingress on ceres

Single source of truth for the machine's TLS ingress. Everything on :443 for
`*.webfront.app` goes through one Caddy process on ceres.

- Tracked config: `configs/caddy/Caddyfile` -> installed to `/etc/caddy/Caddyfile`
- Tracked unit:   `configs/caddy/caddy.service` -> installed to `/etc/systemd/system/caddy.service`
- Secret template: `configs/caddy/env.example` -> real file at `/etc/caddy/env` (**never committed**)
- Installer:      `scripts/setup-caddy.sh`

Both `/etc` files are **copies, not symlinks**. Caddy runs as `User=caddy`
(`configs/caddy/caddy.service:14`) and `/home/ctaylor` is mode `0700`, so the
caddy user cannot read anything inside this repo. The same reasoning drives
`scripts/deploy.d/79_keyd.zsh:5-7`. Re-installing after an edit is a deliberate
step, not automatic.

## Routes

DNS: `ceres.webfront.app` is an **A record to the Tailscale IP `100.82.17.115`**;
every other name is a CNAME onto it. Ingress is therefore reachable only from
the tailnet, not the public internet, even though the certificates are public
Let's Encrypt certs issued over DNS-01.

| Site address | Caddyfile | Backend | Owner | Probe result when healthy |
|---|---|---|---|---|
| `t3.ceres.webfront.app` | `configs/caddy/Caddyfile:6-17` | `localhost:3773` — T3 Code web GUI, user unit `t3code.service` | machine | `200` |
| `*.ceres.webfront.app` | `configs/caddy/Caddyfile:19-28` | `localhost:8080` — portless proxy, user unit `portless.service`; `Host` rewritten to `<label>.ceres` | machine | `404` + `x-portless: 1` for an unregistered app |
| `ceres.webfront.app` | `configs/caddy/Caddyfile:30-36` | static `respond "ceres dev server" 200` | machine | `200` |
| `telemetry.webfront.app` | `configs/caddy/Caddyfile:38-47` | `localhost:3000` — langfuse-web container | `~/repos/telemetry` | `200` |
| `mcp.ceres.webfront.app` | `configs/caddy/Caddyfile:49-68` | `localhost:3111` — openclaw-mcp bridge (default `handle`) and `localhost:3112` — hart wiki MCP (`@wiki` matcher) | `~/repos/hart` | `/mcp` -> `401` (OAuth, expected); `/wiki` -> `405` |

Two ordering facts hold this together and are the reason the file is **not**
split across repos:

1. `t3.` and `mcp.` are more specific site addresses than `*.ceres.webfront.app`,
   so they win. Move either into a separate imported file and the precedence
   relationship stops being visible at the point of edit.
2. Inside the `mcp.` block the `@wiki` matcher must be evaluated before the
   catch-all `handle`, which only works because both live in one block.

A missing route does not fail loudly. If `mcp.ceres.webfront.app` disappeared
from the config, requests would fall through to the `*.ceres.webfront.app`
wildcard and get a portless 404 — a working ingress serving the wrong backend.
See "Why one file" below.

## The secret

`/etc/caddy/env` — 54 bytes, `caddy:caddy`, mode `600`. It contains exactly one
variable, `CF_API_TOKEN`, a Cloudflare API token used by all five `tls { dns
cloudflare {env.CF_API_TOKEN} }` blocks for the DNS-01 challenge. It is loaded
via `EnvironmentFile=/etc/caddy/env` (`configs/caddy/caddy.service:23`).

The canonical copy is `zsh/env.d/91_cloudflare_secrets.zsh`, tracked here only
as the sops-encrypted `zsh/env.d/91_cloudflare_secrets.zsh.enc`. To rebuild
`/etc/caddy/env`, see `configs/caddy/env.example`.

Without this token Caddy cannot renew certificates. It does not need it to
serve existing ones, so the failure is silent for up to ~60 days.

## Restore from bare metal

1. `./deploy.zsh --only 65_secrets` to render secrets from `~/.local/secrets`,
   then `source zsh/env.d/91_cloudflare_secrets.zsh` to get `CF_API_TOKEN` into
   the environment.
2. Install portless (`mise use -g npm:portless`) and start the **user** unit
   `~/.config/systemd/user/portless.service` (`systemctl --user enable --now
   portless`; `loginctl enable-linger ctaylor` so it survives reboot).
3. Confirm the Cloudflare DNS records exist: A `ceres.webfront.app` -> the
   machine's tailnet IP, CNAME `*.ceres.webfront.app` and
   `telemetry.webfront.app` -> `ceres.webfront.app`.
4. Run `scripts/setup-caddy.sh`. It builds a Caddy binary with the
   `caddy-dns/cloudflare` plugin at `/usr/local/bin/caddy` (the distro package
   has no DNS provider modules), writes `/etc/caddy/env`, and installs the two
   tracked files above.
5. Verify with the curl probes in the routes table. `systemctl status caddy`
   being green is **not** sufficient — check each route.

## Editing the config

```sh
$EDITOR configs/caddy/Caddyfile
/usr/local/bin/caddy validate --adapter caddyfile --config configs/caddy/Caddyfile
sudo cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-$(date +%F)
sudo install -m 644 -o root -g root configs/caddy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy      # reload, not restart — no dropped connections
```

To prove an edit is behaviour-preserving, diff the adapted JSON rather than the
text:

```sh
sudo caddy adapt --adapter caddyfile --config /etc/caddy/Caddyfile | python3 -m json.tool --sort-keys > /tmp/before.json
caddy adapt --adapter caddyfile --config configs/caddy/Caddyfile   | python3 -m json.tool --sort-keys > /tmp/after.json
diff -u /tmp/before.json /tmp/after.json
```

Rollback is `sudo install -m 644 <the .bak> /etc/caddy/Caddyfile && sudo
systemctl reload caddy`. `/etc/caddy/` already holds three historical backups
(`Caddyfile.pre-t3.bak`, `.pre-mcp.bak`, `.pre-wiki-mcp.bak`) — leave them.

## Why one file, not a dotfiles base plus a hart include

Splitting along ownership lines (machine routes here, `mcp.*` in `~/repos/hart`)
was considered and rejected:

- Caddy cannot read either repo. `User=caddy` plus `/home/ctaylor` at `0700`
  means both halves must be *copied* into `/etc/caddy/` anyway, so a split buys
  no live-editing benefit — only a second install step that can be skipped.
- `import conf.d/*.caddy` whose glob matches **nothing** is a silent no-op on
  Caddy v2.11.2 (`caddy validate` prints "Valid configuration"). A forgotten
  hart deploy would therefore drop `mcp.ceres.webfront.app` into the portless
  wildcard with no error anywhere.
- A literal `import conf.d/hart.caddy` does fail loudly ("File to import not
  found"), but it fails *closed*: Caddy refuses the whole config and all five
  routes go down instead of one. Both split failure modes are worse than today's.
- The file is 2.2 KB and has changed three times since May 2026 (the three
  `.bak` files in `/etc/caddy/`). It is one precedence ladder, not five
  independent things.

Ownership is recorded in the routes table instead. `~/repos/hart` carries a
pointer to this document in its `AGENTS.md`.
