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
every other `webfront.app` name is a CNAME onto it. Ingress is therefore
reachable only from the tailnet, not the public internet, even though the
certificates are public Let's Encrypt certs issued over DNS-01.

The `wedrifid.dev` routes are a different shape: each is its own grey-cloud
(DNS-only) A record straight at `100.82.17.115`, on a **separate Cloudflare
account**, so they use `CF_WEDRIFID_TOKEN` rather than `CF_API_TOKEN`. None of
them relies on DNS for access control -- Caddy binds `*:443` and ceres has a
public IP, so every `wedrifid.dev` block carries
`@external not remote_ip 100.64.0.0/10 ...` + `abort`.
That matcher is the actual boundary; a CGNAT address in DNS is only addressing.

Two of these proxy to a loopback backend and treat `Host` differently, deliberately: `usage` rewrites it to the dial target because CodexBar refuses any request whose `Host` is not its own bind address, while `ntfy` passes it through because ntfy builds links from `base-url` plus the request host. Copying either block for a third service means deciding which case it is.

| Site address | Caddyfile | Backend | Owner | Probe result when healthy |
|---|---|---|---|---|
| `t3.ceres.webfront.app` | `configs/caddy/Caddyfile:6-17` | `localhost:3773` — T3 Code web GUI, user unit `t3code.service` | machine | `200` |
| `*.ceres.webfront.app` | `configs/caddy/Caddyfile:19-28` | `localhost:8080` — portless proxy, user unit `portless.service`; `Host` rewritten to `<label>.ceres` | machine | `404` + `x-portless: 1` for an unregistered app |
| `ceres.webfront.app` | `configs/caddy/Caddyfile:30-36` | static `respond "ceres dev server" 200` | machine | `200` |
| `telemetry.webfront.app` | `configs/caddy/Caddyfile:38-47` | `localhost:3000` — langfuse-web container | `~/repos/telemetry` | `200` |
| `mcp.ceres.webfront.app` | `configs/caddy/Caddyfile:49-68` | `localhost:3111` — openclaw-mcp bridge (default `handle`) and `localhost:3112` — hart wiki MCP (`@wiki` matcher) | `~/repos/hart` | `/mcp` -> `401` (OAuth, expected); `/wiki` -> `405` |
| `immich.wedrifid.dev` | `configs/caddy/Caddyfile:77-88` | `100.82.17.115:2283` — immich container | `~/repos/deploy/immich` | `200` from the tailnet; connection refused elsewhere |
| `usage.wedrifid.dev` | `configs/caddy/Caddyfile:95-128` | `127.0.0.1:8791` — CodexBar quota collector, user unit `codexbar-serve.service`; Caddy injects `Authorization: Bearer {env.CODEXBAR_DASHBOARD_TOKEN}` so tailnet browsers need no token (see the secret section below) | `~/.local/agents/docs/llm-quota.md` (agents repo; Caddy side stays dotfiles) | `/health` -> `{"version":...,"status":"ok"}`; `/dashboard/v1/snapshot` -> `200` with no auth header |
| `ntfy.wedrifid.dev` | `configs/caddy/Caddyfile:130-142` | `127.0.0.1:2586` — ntfy server, user unit `ntfy-server.service` | `~/.local/agents/docs/llm-quota.md` (agents repo; Caddy side stays dotfiles) | `/v1/health` -> `{"healthy":true}` |
| `appreciation.wedrifid.dev` | `configs/caddy/Caddyfile:156-174` | `unix//run/appreciation/app.sock` — SvelteKit/Bun app, user unit `appreciation.service`; the socket (not a port) is load-bearing for the app's X-Forwarded-For identity check | `~/repos/hart/appreciation` (unit tracked there; tmpfiles.d snapshot at `configs/appreciation/appreciation.conf`) | `200` from Cameron's devices; abort/reset elsewhere |

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

`/etc/caddy/env` — `caddy:caddy`, mode `600`. It contains **three**
variables, loaded via `EnvironmentFile=/etc/caddy/env`
(`configs/caddy/caddy.service:23`):

- `CF_API_TOKEN` — the **webfront.app** Cloudflare account, used by the five
  `*.webfront.app` blocks for DNS-01.
- `CF_WEDRIFID_TOKEN` — the **personal wedrifid.dev** account, used by the
  `wedrifid.dev` blocks for DNS-01. Different account entirely; the two tokens
  are not interchangeable.
- `CODEXBAR_DASHBOARD_TOKEN` — the CodexBar dashboard token, copied from
  `~/.local/state/codexbar/dashboard-token` (which stays canonical and 0600) by
  `scripts/setup-caddy-usage-site.sh`. Injected as a request header on
  `usage.wedrifid.dev` only; losing it just restores the dashboard's
  enter-a-token prompt, so it is the least sensitive of the three.

⚠ Neither wedrifid.dev credential has a canonical copy in `~/.local/secrets`.
Verified 2026-09-04 by decrypting every `*.yaml` there: the only Cloudflare
material is `CF_API_TOKEN` / `CF_Account_ID` / `CF_Zone_ID`, and that token
reaches zone `webfront.app` only. Two unbacked-up tokens can edit
`wedrifid.dev`:

- `CF_WEDRIFID_TOKEN` in `/etc/caddy/env` (root-only) — DNS-01 for both
  `wedrifid.dev` certs.
- `CF_PROVISION_TOKEN` in `~/.config/hart-wiki-mcp/cf-provision.env` (0600,
  **user-readable**) — token "hart-wiki-mcp-provisioner", minted 2026-08-16,
  Account Tunnel Edit + Zone WAF Edit + Zone DNS Edit on `wedrifid.dev`. See
  `~/repos/hart/docs/handover-home-ip-drift.md:25`. Confirmed live to reach
  exactly one zone: `wedrifid.dev`.

Because the provisioner token carries Zone DNS Edit, it can serve as a
replacement for `CF_WEDRIFID_TOKEN` if `/etc/caddy/env` is ever lost — DNS-01
needs no more than that. It is a fallback, not a backup: both files are on the
same disk. Add both to the secrets repo:

```sh
sops edit ~/.local/secrets/shell/91_cloudflare_secrets.yaml   # add CF_WEDRIFID_TOKEN
# then add a row in scripts/secrets-render.zsh -- note a row whose source file
# is missing makes the whole render FAIL (secrets-render.zsh:304), so add the
# value first, the row second.
```

The canonical copy is `shell/91_cloudflare_secrets.yaml` in the private secrets
repo (`~/.local/secrets`), rendered on each deploy to
`$XDG_STATE_HOME/secrets/zsh/91_cloudflare_secrets.zsh`. To rebuild
`/etc/caddy/env`, see `configs/caddy/env.example`.

Without this token Caddy cannot renew certificates. It does not need it to
serve existing ones, so the failure is silent for up to ~60 days.

## Restore from bare metal

1. `./deploy.zsh --only 65_secrets` to render secrets from `~/.local/secrets`,
   then `source "${XDG_STATE_HOME:-$HOME/.local/state}"/secrets/zsh/91_cloudflare_secrets.zsh`
   to get `CF_API_TOKEN` into the environment. (Any new interactive shell has
   it already — `zsh/env.d/89_secrets_loader.zsh` sources that dir.)
2. Install portless (`mise use -g npm:portless`) and start the **user** unit
   `~/.config/systemd/user/portless.service` (`systemctl --user enable --now
   portless`; `loginctl enable-linger ctaylor` so it survives reboot).
3. Confirm the Cloudflare DNS records exist: A `ceres.webfront.app` -> the
   machine's tailnet IP, CNAME `*.ceres.webfront.app` and
   `telemetry.webfront.app` -> `ceres.webfront.app`. On the **personal**
   account, grey-cloud A records `immich.wedrifid.dev` and
   `usage.wedrifid.dev` -> `100.82.17.115`
   (`scripts/setup-caddy-usage-site.sh` creates or corrects the latter, and
   also syncs `CODEXBAR_DASHBOARD_TOKEN` into `/etc/caddy/env` — run it after
   `setup-caddy.sh` so the usage dashboard is token-free again).
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
                                 # EXCEPT after editing /etc/caddy/env: {env.*}
                                 # resolve in the running process from its
                                 # start-time environment, so env changes need
                                 # `systemctl restart caddy`
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

### The hazard this created, and the fix (2026-09-04)

Keeping one file is right, but it left a trap: `scripts/setup-caddy.sh` did not
*install* `configs/caddy/Caddyfile` — it **regenerated** `/etc/caddy/Caddyfile`
from an inline heredoc emitting only the three machine routes. The tracked copy
had meanwhile gone three blocks stale, so running the installer would have
silently deleted `telemetry`, `mcp.ceres`, `immich` and `usage`, and
`write_caddy_env` would have truncated `CF_WEDRIFID_TOKEN` out of existence.
Per the note above, a missing route fails quietly into the portless wildcard.

Both are fixed:

- `write_caddyfile()` now installs `configs/caddy/Caddyfile` when it exists
  (with a timestamped backup), falling back to the generated template only when
  bootstrapping a host that has no tracked file. The doc's claim that the
  tracked file is the source of truth is now true of the code.
- `write_caddy_env()` preserves every key it does not manage, so
  `CF_WEDRIFID_TOKEN` survives a re-run.
- `configs/caddy/Caddyfile` has been resynced from `/etc/caddy/Caddyfile` and
  carries every live route (resynced again 2026-09-08, when the installer's
  adapt-diff caught that `appreciation.wedrifid.dev` had been added to `/etc`
  only — installing the tracked file would have silently dropped it).

Ownership is recorded in the routes table instead. `~/repos/hart` carries a
pointer to this document in its `AGENTS.md`.
