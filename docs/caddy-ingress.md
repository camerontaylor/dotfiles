# Caddy ingress on ceres

All fleet HTTPS routes use `wedrifid.dev`. The migration on 2026-10-02 moved
Ceres development ingress, telemetry and the tailnet MCP bridge to this zone.

- Source: `configs/caddy/Caddyfile`; installed copy: `/etc/caddy/Caddyfile`.
- Unit: `configs/caddy/caddy.service`; installed in `/etc/systemd/system/`.
- Secret template: `configs/caddy/env.example`; real file: `/etc/caddy/env`.
- Installer: `scripts/setup-caddy.sh`.

The root-owned files are copies because `User=caddy` cannot traverse the
user's mode-0700 home. Edit the tracked source, then deliberately install it.

## Routing and access

DNS-only A records point to Ceres's Tailscale address `100.82.17.115`.
DNS addressing alone is not access control: Caddy also listens on public
interfaces. Each private route imports `wedrifid_tailnet`, which aborts
connections whose actual peer address is outside the tailnet IPv4/IPv6 ranges.
Appreciation has an additional device allowlist. Public tunnel services
`mcp.wedrifid.dev`, `fred.wedrifid.dev` and `miniflux.wedrifid.dev` keep their
separate authentication and Cloudflare controls.

| Name | Backend |
|---|---|
| `ceres.wedrifid.dev` | Host response |
| `*.ceres.wedrifid.dev` | Portless :8080, Host rewritten to `<app>.ceres` |
| `t3.ceres.wedrifid.dev` | T3 Code :3773 |
| `telemetry.wedrifid.dev` | Langfuse :3000 |
| `mcp.ceres.wedrifid.dev` | Wiki paths :3112; remaining MCP paths :3111 |

The specific T3 and MCP routes take precedence over the development wildcard.
Keep the wiki matcher before the MCP catch-all. A missing specific route can
silently fall through to portless; process health alone does not verify routing.
All other service definitions are in infra `web/catalog.toml`, with deployment
and domain references in infra `docs/fleet-domains.md`.

```sh
infra/bin/render-fleet-page --check-caddy configs/caddy/Caddyfile
infra/bin/ensure-fleet-dns                 # dry run; --apply writes DNS
```

The checker covers catalog service cards and `[[route]]` development names,
including multi-label and wildcard names. It verifies the actual imported gate,
not just an import statement. The DNS reconciler creates DNS-only A records.

Service-specific proxy headers remain significant: qBittorrent rewrites Host
and removes Origin/Referer for its CSRF checks; Syncthing rewrites Host; usage
injects the dashboard bearer and rewrites Host to the collector bind address.

## Credentials and restore

`/etc/caddy/env` is mode 0600, owned by caddy:caddy. `CF_WEDRIFID_TOKEN` now has
an encrypted canonical copy in `~/.local/secrets/shell/91_cloudflare_secrets.yaml`.
The shell renderer exports it; Pluto's selective renderer writes only this
credential to its Caddy environment. Existing customer-zone credentials are
preserved but are not used by fleet TLS routes.

The dashboard token is generated on Neptune and mirrored to Ceres;
`scripts/setup-caddy-usage-site.sh` installs it. Never commit real credentials.
An EnvironmentFile change requires a Caddy restart to load the new environment;
a routing-only change can reload without dropping connections.

1. Run `./deploy.zsh --only 65_secrets` and source the generated Cloudflare shell
   secrets under `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/`.
2. Install/start the user Portless unit and enable user lingering as required.
3. Reconcile DNS from infra's catalog and host definitions.
4. Run `scripts/setup-caddy.sh`, then `scripts/setup-caddy-usage-site.sh`.
5. Probe every specific route over the tailnet; also verify external access aborts.

## Installing a routing change

Validate with the Cloudflare credential in the validation environment, keeping
it out of command arguments and logs. Back up the installed Caddyfile, then:

```sh
sudo install -m 644 -o root -g root configs/caddy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Rollback by reinstalling the backup and reloading. Keep unrelated routes and
credentials intact. The tracked file remains one precedence ladder; splitting
it into optional imports could silently remove a specific route. The installer
uses the tracked file when available and preserves unrelated environment keys.
