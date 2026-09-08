# LLM plan-quota monitoring on ceres

How much of each LLM **subscription** is left, on the Mac, the phone and from
agents — plus pacing cues pushed when the burn rate stops matching the clock.

- Collector: CodexBar CLI in `serve` mode, `127.0.0.1:8791`
- Cue engine: [`scripts/codexbar-quota-cues.py`](../scripts/codexbar-quota-cues.py), every 10 min
- Delivery: self-hosted ntfy, `127.0.0.1:2586`
- Ingress: `usage.wedrifid.dev` and `ntfy.wedrifid.dev`, tailnet-only — see
  [`docs/caddy-ingress.md`](caddy-ingress.md)

## Why this lives here

Plan quota is a **different meter from API spend**, and the distinction drives
the whole design. Anthropic's Admin API and OpenAI's `/v1/organization/usage/*`
report API-key billing; they say nothing about Max/Pro/Codex subscription
windows. Those live behind per-vendor account endpoints, most undocumented:

| Plan | Endpoint | Credential |
|---|---|---|
| Claude | `api.anthropic.com/api/oauth/usage` | `~/.claude/.credentials.json` |
| Codex | `chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json` |
| z.ai | `api.z.ai/api/monitor/usage/quota/limit` | `ZAI_API_KEY` |

Talking to those directly was rejected: they drift (z.ai renamed
`TOKENS_LIMIT` → `CREDIT_LIMIT` on 2026-07-30 and broke six community
trackers), the vendors disagree on protections (OpenAI Cloudflare-gates one
path on `User-Agent`, Anthropic does not gate at all), and Anthropic moved
per-model weekly buckets out of top-level keys into `limits[]`. CodexBar
absorbs that churn — near-daily releases with named provider-breakage fixes —
so the local surface stays a stable JSON contract. Full evaluation:
`~/repos/hart/docs/research/2026-09-04-llm-plan-usage-trackers.md`.

## Sources of truth

| Thing | Tracked | Live |
|---|---|---|
| Units (4) | `configs/ai/codexbar/*.service`, `*.timer` | symlinked into `~/.config/systemd/user/` by `deploy.d/20_symlinks.zsh` (ceres-gated) |
| Cue engine | `scripts/codexbar-quota-cues.py` | run in place by the timer |
| Installer | `scripts/setup-llm-quota.sh` | hand-run |
| Caddy sites | `configs/caddy/Caddyfile` | `/etc/caddy/Caddyfile` |
| CodexBar binary + plugin bundle | — | `~/.local/share/codexbar/` (v0.56.4) |
| ntfy binary | — | `~/.local/share/ntfy/` (v2.28.0) |
| Provider toggles + z.ai key | — | `~/.config/codexbar/config.json` (0600) |
| Dashboard token | — | `~/.local/state/codexbar/{dashboard-token,env}` (0600) |
| Cue dedup state | — | `~/.local/state/codexbar-alerts/state.json` |

Binaries and secrets are deliberately untracked. Neither has a canonical copy
in `~/.local/secrets` — see **Gaps**.

## Endpoints

| URL | Auth | Use |
|---|---|---|
| `https://usage.wedrifid.dev/` | none from the tailnet | web dashboard |
| `.../health` | none | liveness |
| `.../usage` | none | **the integration seam** — JSON for every enabled provider |
| `.../usage?provider=zai` | none | one provider; also the only identity-free form (see Gaps) |
| `.../cost` | none | spend estimates from local logs |
| `.../dashboard/v1/snapshot` | none from the tailnet | redacted snapshot, `schemaVersion` + `staleAfterSeconds` |

The dashboard is token-free **because Caddy, not the browser, holds the
bearer**: the `usage.wedrifid.dev` block injects
`Authorization: Bearer {env.CODEXBAR_DASHBOARD_TOKEN}` (value synced from
`~/.local/state/codexbar/dashboard-token` into `/etc/caddy/env` by
`scripts/setup-caddy-usage-site.sh`). CodexBar's web UI only prompts for a
token when `/dashboard/v1/snapshot` answers 401, and with the header injected
it never does — browsers never see or store the token. The vhost's
`@external` abort is what scopes this to tailnet peers; off-tailnet the
connection is dropped before the proxy. A client that did store an old token
is silently upgraded: `header_up` overwrites whatever it sends with the live
value. Direct loopback access to `127.0.0.1:8791` still needs the token.
| `https://ntfy.wedrifid.dev/quota` | none | cue topic; subscribe the ntfy Android app here |

`--refresh-interval 180` is a **cache TTL, not a poll**: the collector reaches
upstream only when asked and the cache is stale. Measured 9 upstream fetches
across two days — an eager 180 s poller would have made ~1000. Nobody looking
means no API calls.

## Pacing cues

For each window, `r_u` = quota remaining %, `r_t` = time remaining as a % of
the window. Relevance is `(r_t - r_u) / r_t`; beyond ±0.25 the cue fires,
inside it is suppressed as on-pace. Normalising by `r_t` tightens the band as
the window closes, so strictness escalates: at 50 % time remaining it fires
below 37.5 % used, at 1 day left below 82.1 %.

| Window | Cue points | Reported when |
|---|---|---|
| weekly (`windowMinutes >= 1440`, incl. Claude's `Fable only`) | 50 / 75 / 90 % used | HOT |
| weekly | 50 % time left, 1 day left | WASTE |
| 5h | 80 % used | HOT |

5h windows get no waste cue: they reset ~4.8×/day and under-using one is
normal, not a problem. 80 % is chosen because `r_u = 20 < 0.75·r_t` needs
`r_t > 26.7 %`, so it fires with a quarter of the window still to run and stays
silent when 80 % simply reflects good pacing near the reset.

Waste cues matter more than hot ones here: unused capacity on a Max plan is
money already spent.

Two liveness alarms ride along with the cues (added 2026-09-06):

- **window missing** — a provider+window pair previously seen in `/usage`
  has been absent for 3 consecutive polls (~30 min at the 10-minute cadence;
  one-off collector hiccups don't trip it). High priority, `rotating_light`
  tag. The likeliest cause is credential expiry: the collector cannot refresh
  OAuth tokens, and an expired provider silently drops out of `/usage`.
- **collector unreachable** — `/usage` itself failed for 3 consecutive polls.
  Same priority/tag, different title, and per-window miss counters are *not*
  advanced while the endpoint is down (a dead collector is not credential
  expiry).

Both alert once per episode and send a default-priority all-clear
(`... - window back` / `codexbar collector back`) when the thing returns.

### Card images (added 2026-09-06)

Every pacing cue attaches a 1024×512 PNG — a mini CodexBar provider card: all
of the provider's windows as thin bars in its brand hue, a HOT/SLACK chip, a
white pace tick at elapsed% on each bar, and the trigger row emphasised (status
dot, full saturation, translucent projection extension). Design + validated
palette: hart `docs/research/2026-09-06-quota-cue-ntfy-images.md`; new
providers need a hue added to `PROVIDER_COLOR` in the cue script (validate it,
don't guess — the raw CodexBar hues fail CVD checks).

Mechanics: pure-stdlib SVG → `rsvg-convert` (system librsvg) → PNG, written to
`~/.local/state/codexbar-alerts/last-cue.{svg,png}` (the sandbox's only
writable path; doubles as a debug artifact). The PNG is `PUT` as the request
body with title/message/priority/tags/click as **URL-encoded query params**
(headers are latin-1 — the em-dash trap — query params carry UTF-8). Any
render or upload failure falls back to the plain text POST; a cue is never
lost to its picture. Server side: `attachment-cache-dir` +
`attachment-expiry-duration: 24h` in `~/.config/ntfy/server.yml` (enabled
2026-09-06; the Android app shows the card inline via BigPictureStyle).
Liveness alarms stay text-only.

## Install

```sh
sh ~/.local/dotfiles/scripts/setup-llm-quota.sh          # user-space, idempotent
sudo sh ~/.local/dotfiles/scripts/setup-caddy-usage-site.sh   # DNS + Caddy env + Caddyfile, once
```

Then subscribe the ntfy Android app (`io.heckel.ntfy`, F-Droid or Play) to
`https://ntfy.wedrifid.dev`, topic `quota`. For a home-screen number rather
than a push, HTTP Shortcuts (`ch.rmy.android.http_shortcuts`) against
`/usage?provider=zai` — its repeat floor is 10 minutes, which is why the timer
runs at 10 and finer collector polling would buy nothing.

### Fresh machine, in order

1. `./deploy.zsh` — symlinks the four units (ceres only).
2. Log in to each provider CLI at least once: `claude`, `codex`. Their OAuth
   tokens are what the collector reads, and **it cannot refresh them** —
   headless refresh is Cloudflare-blocked on Linux (`anthropics/claude-code#47754`,
   closed as not planned). Claude's token lasts ~8 h, Codex's ~10 days.
3. `sh scripts/setup-llm-quota.sh`.
4. `sudo sh scripts/setup-caddy-usage-site.sh`.
5. Verify each endpoint in the table above. `systemctl --user status` being
   green is **not** sufficient — a collector with stale credentials is active
   and healthy while returning nothing.

## Operating

```sh
codexbar --provider all --format json --pretty      # one-shot, no server
python3 scripts/codexbar-quota-cues.py --show       # pacing table, every window
python3 scripts/codexbar-quota-cues.py --dry-run    # what would fire, sends nothing
journalctl --user -u codexbar-quota-cues -n 20
```

State lives in `~/.local/state/codexbar-alerts/state.json` with three parts:
`cues` (sent-cue slots, keys `provider|label|resetsAt|cue`), `presence`
(last-seen/miss-count per provider+window, feeding the window-missing alarm)
and `collector` (the unreachable-endpoint counter). A v1 flat file migrates
automatically. To retest a cue, delete its key under `cues`; slots self-clear
once their `resetsAt` has actually passed.

Cue slots are matched *fuzzily* on `resetsAt`: collectors jitter the timestamp
by whole seconds mid-window (codex weekly drifted `07:01:48` → `07:01:49` on
2026-09-06, which under exact matching re-fired the same `tleft50pct` cue five
times in ~90 min). Two resets of the same window less than a quarter of the
window span apart are treated as the same instance and the stored slot is
re-keyed; a reset a full span away is a new instance and may fire again.

`--from-file` without a `CUE_STATE` override runs state-read-only, so fixture
experiments cannot clobber the live dedup/presence state.

Updating is manual — CodexBar's Sparkle auto-updater is macOS-app-only. Bump
`CODEXBAR_VERSION` in `scripts/setup-llm-quota.sh` and re-run it.

## Gaps

- **No secret backup.** The dashboard token is regenerable (and losing the
  `/etc/caddy/env` copy just restores the browser token prompt — the canonical
  file is `~/.local/state/codexbar/dashboard-token`), but the z.ai key in
  `~/.config/codexbar/config.json` is not, and neither `CF_WEDRIFID_TOKEN`
  (`/etc/caddy/env`) nor `CF_PROVISION_TOKEN`
  (`~/.config/hart-wiki-mcp/cf-provision.env`) has a canonical copy in
  `~/.local/secrets`. Losing `/etc/caddy/env` stops both `wedrifid.dev` certs
  renewing — silently, for up to ~60 days.
- **`/usage` is unauthenticated and the Codex entry carries `accountEmail`.**
  Readable by anything on the tailnet. `--identity redacted` only covers
  `/dashboard/v1/snapshot`. Per-provider queries (`?provider=zai`,
  `?provider=claude`) are identity-free; the full `/usage` is not. Accepted
  deliberately — it is what makes header-less clients work — but it is a real
  choice, not an oversight.
- **The Host rewrite disables CodexBar's own gating.** `usage.wedrifid.dev`
  rewrites `Host` to the dial target, because CodexBar rejects anything else
  (`{"error":"forbidden host"}`, a DNS-rebinding guard with no allowlist flag).
  The side effect is that CodexBar believes it is on loopback and therefore
  does not token-gate `/usage` and `/cost`. The `remote_ip` matcher in the
  Caddy block is the only boundary; it reads the peer address, not the header,
  so it still holds. Caddy additionally injects the dashboard bearer on every
  request it proxies (see Endpoints) — harmless on the ungated paths, and it
  never reaches CodexBar from a non-tailnet peer because of the same matcher.
- ~~**Credential expiry is the likeliest failure**, and it is quiet.~~
  Closed 2026-09-06: the cue script now alarms when a previously-seen window
  is absent for ~30 min, and separately when the collector itself is
  unreachable (see Pacing cues, liveness alarms).
- **No macOS story yet.** The CLI has Darwin builds and `codexbar serve` would
  work, but nothing here provisions saturn/neptune; they would read
  `usage.wedrifid.dev` over the tailnet, or run SwiftBar against it.
