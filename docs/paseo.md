# Paseo runbook

[Paseo](https://github.com/getpaseo/paseo) is a self-hosted daemon that runs
Claude Code / Codex / Copilot / OpenCode / Pi agents on your own machines and
exposes them to a desktop app, a phone app, a browser, and a CLI. It carries no
model credentials of its own — it drives the agent CLIs already installed and
logged in on the box.

AGPL-3.0. CLI and desktop app versions should stay in lockstep. The Macs use
the beta channel in the desktop app under **Settings → About → Release
channel**; the headless Linux install tracks npm's `@beta` dist-tag.

## Topology

| Box | OS | Install | Daemon lifecycle | Bind |
|---|---|---|---|---|
| saturn | macOS | `paseo` brew cask (app + CLI) | Paseo.app, plus a login LaunchAgent | `[::]:6767` |
| neptune | macOS (Intel) | `paseo` brew cask (app + CLI) | Paseo.app, plus a login LaunchAgent | `[::]:6767` |
| ceres | Arch, headless | `npm:@getpaseo/cli@beta` via mise | `paseo-daemon.service` (systemd) | `[::]:6767` |
| phone | iOS / Android | App Store / Play Store | — | connects over Tailscale |

Every daemon requires a bcrypt password. The phone reaches a box by its
Tailscale `100.x` address on port 6767; a terminal on any box reaches any other
through `paseo-at` (see below).

### Why a direct bind and not loopback-behind-Caddy

`setup-t3.sh` and the portless daemon both bind loopback and let Caddy terminate
TLS at `<svc>.<host>.webfront.app`. Paseo deliberately does not follow that
pattern:

- Its phone clients speak WebSocket to `/ws`, and upstream's own Tailscale guide
  is a direct `host:port` connection.
- Fronting it would add a Host-header allowlist (`daemon.hostnames`) plus
  `daemon.trustedProxies` to get `X-Forwarded-*` right — for TLS that
  Tailscale's WireGuard already provides.
- One less always-on dependency between the phone and the agents.

If you later want `https://paseo.<host>.webfront.app` anyway, add a carve-out
block to `setup-caddy.sh` mirroring the `t3.` one, and append the hostname to
`daemon.hostnames`.

### Bind `[::]`, never `0.0.0.0`

`0.0.0.0` is the IPv4 wildcard and does **not** cover IPv6 loopback. On macOS
`localhost` resolves to `::1` first, so a `0.0.0.0` bind leaves any client that
connects by name — and doesn't fall back to IPv4 quickly — hanging on a dead
address. That is precisely how Paseo.app failed to reach its own daemon on
saturn: `curl http://localhost:6767` returned 200 (curl retries IPv4) while the
desktop app timed out.

`[::]` gives a dual-stack socket that also accepts IPv4-mapped connections, so
`127.0.0.1` and the Tailscale `100.x` IPv4 address keep working. Verified on
saturn — `127.0.0.1`, `[::1]`, `localhost` and `100.104.76.127` all return 200.

Diagnose it with `lsof -nP -iTCP:6767 -sTCP:LISTEN`: the `TYPE` column reads
`IPv4` for the broken bind and `IPv6` for the dual-stack one.

### macOS has no launch-at-login, so we add one

Paseo.app ships no launch-at-login setting (nothing for it in the desktop
package, nothing in the docs) and the daemon dies with the app. Left alone,
saturn and neptune drop off the phone after every reboot until someone walks
over and opens the app.

`setup-paseo.sh` therefore installs a **user** LaunchAgent,
`~/Library/LaunchAgents/local.paseo-daemon.plist` — user, not a system
LaunchDaemon like `t3-serve`, because the daemon spawns claude/codex/opencode
and those need this user's login session and keychain. It also disables
Desktop's built-in daemon management in `desktop-settings.json`; the
LaunchAgent must be the sole daemon owner. With both enabled, Desktop can
misread the password-protected local daemon as unavailable and a duplicate
start fails with exit code 1.

Two deliberate choices in that plist:

- **One-shot** (`RunAtLoad`, no `KeepAlive`). `paseo daemon start` exits 1 when
  a daemon already holds the port — it leaves the running one alone, but under
  `KeepAlive` that non-zero exit becomes a restart loop every time the app got
  there first. One-shot means: start it at login if nothing else has, otherwise
  fail harmlessly into `~/.paseo/launchd.err`.
- **`AbandonProcessGroup`** is load-bearing. `paseo daemon start` forks and
  returns; without it launchd reaps the whole process group when the job exits
  and kills the daemon it just started.

It also sets a PATH containing the mise shims. launchd's default PATH has none,
so a purely GUI-launched daemon cannot even find `claude`.

### Why the config is generated, not symlinked

`~/.paseo/config.json` is **daemon-owned**. `paseo daemon set-password`, the
relay toggle, provider enable/disable from the desktop GUI, and plugin state all
write it — via `writeFileSync(tmp, {mode: 0600})` + `renameSync(tmp, target)`.
An atomic rename *replaces* whatever sits at the target path, so a symlink into
this repo would survive exactly until the first daemon-side write, then silently
become a real file with dotfiles no longer applying.

Same call as the Karabiner JSON in `scripts/deploy.d/20_symlinks.zsh`:
GUI/daemon-owned files get generated. `scripts/paseo-config.mjs` deep-merges
only our keys and leaves the rest alone; re-running is a no-op when nothing
changed.

## First-time setup

### 1. Set the shared daemon password

`PASEO_PASSWORD` lives in the encrypted secrets file so every box and every CLI
client agrees on it:

```zsh
# edit the decrypted file, add:  export PASEO_PASSWORD="…"
$EDITOR ~/.local/dotfiles/zsh/env.d/90_secrets.zsh
./scripts/save-secrets.zsh          # re-encrypt to 90_secrets.zsh.enc
git commit -m "chore(secrets): add paseo daemon password"
```

Then `./deploy.zsh` on the other boxes (or `./scripts/restore-secrets.zsh`) to
land the decrypted copy there.

A bcrypt hash of it goes into `config.json` on every host — the one auth
mechanism that works for **both** a systemd-managed daemon and a GUI-launched
one. `PASEO_PASSWORD` as an environment variable only reaches the daemon on
Linux; the macOS desktop app is launched by the GUI and never sees your shell
environment.

> Without a password, `setup-paseo.sh` refuses to bind past `127.0.0.1`. An
> unauthenticated Paseo daemon on the office LAN is remote code execution as
> you, by design.

### 2. Run the setup script on each box

```zsh
ssh saturn  'cd ~/.local/dotfiles && ./scripts/setup-paseo.sh'
ssh neptune 'cd ~/.local/dotfiles && ./scripts/setup-paseo.sh'
ssh ceres   'cd ~/.local/dotfiles && ./scripts/setup-paseo.sh'
```

Idempotent; re-run it any time to re-apply config or pick up a new password.
It installs (cask on macOS, mise tool on Linux), writes `~/.paseo/config.json`,
installs the supervision (systemd unit on Linux, login LaunchAgent on macOS),
starts the daemon, verifies `/api/health`, and prints the Tailscale address to
type into the phone.

On the Macs the cask also arrives through the normal deploy
(`scripts/deploy.d/75_brew_setup.zsh`), so `./deploy.zsh` keeps it upgraded.

### 3. Connect the phone

1. Tailscale connected on the phone, same tailnet.
2. Paseo → **Settings → Add host → Direct connection**.
3. Host: the box's `tailscale ip -4` address. Port: `6767`. **Use SSL: off**
   (Tailscale already encrypts).
4. Password: the `PASEO_PASSWORD` from step 1.

Repeat per box. Relay is explicitly disabled (`daemon.relay.enabled: false`) —
we want traffic on the tailnet, not through a third-party relay. Note that a
home whose config *omitted* that key when the daemon started keeps the legacy
relay-enabled behaviour, which is why the setup script always writes it.

### 4. Make sure the agents can actually run

Paseo launches the agent CLIs as your user. On each box:

```zsh
claude          # authenticated?
codex login
opencode auth login
```

An unauthenticated provider fails at agent launch, not at daemon start, so the
health check will happily pass while every agent dies.

## Day-to-day

```zsh
paseo-hosts                     # which fleet daemons are up (no auth needed)
paseo-ceres ls                  # list agents on ceres
paseo-at saturn run --provider claude/opus-4.6 "fix the failing test"
paseo-ceres attach <id>
paseo-ceres send <id> "also add tests"
```

`paseo status` / `paseo daemon status` are **local-only** — they take `--home`,
not `--host`, and ignore `$PASEO_HOST`. Running them under `paseo-at ceres`
silently reports *this* box's daemon. To confirm you're talking to the box you
think you are, compare `~/.paseo/server-id` values, or just watch what `ls`
returns.

`paseo-at` sets `$PASEO_HOST`. Do **not** write `paseo --host X ls`: in the
stable CLI `--host` is a per-subcommand option, not a root one, so that form
fails with `unknown option '--host'`. (The README on `main` shows the root form
because it documents the 0.5 beta.) `$PASEO_HOST` works for every subcommand.

Headless web UI on ceres — the daemon serves the browser client on its own port:

```
http://ceres.webfront.app:6767/
```

Static files load without auth; the API and WebSocket still require the
password.

## Operational notes

- **First start downloads speech models.** The daemon eagerly fetches
  `parakeet-tdt-0.6b-v2-int8` and `kokoro-en-v0_19` into
  `~/.paseo/models/local-speech` for local dictation/voice. Expect a few hundred
  MB of background traffic on a fresh home. Set `features.dictation` /
  `features.voiceMode` in `config.json` if you'd rather it didn't.
- **`~/.paseo` holds real state**: `config.json`, `daemon-keypair.json`,
  `server-id`, `projects/`, `agents/`, `worktrees/`, `schedules/`, `daemon.log`.
  Do not delete it to "reset" — you lose device pairings and agent history.
- **Logs**: `~/.paseo/daemon.log` (trace level, 10 MB × 2 rotation) everywhere,
  plus `journalctl -u paseo-daemon -f` on ceres.
- **Restart after a config change**: `daemon.listen` and auth are startup
  settings. `paseo reload` applies runtime-safe keys and *tells you* which paths
  still need a restart. On ceres: `sudo systemctl restart paseo-daemon`. On the
  Macs: **Settings → your host → Overview → Restart daemon**.
- **No launch overrides.** `paseo-daemon.service` passes only `--foreground`
  and `--home` on purpose. Start flags and env vars outrank `config.json` and
  make later edits to those keys silently ineffective (reload reports them under
  `overrideControlledPaths`). Keeping them off the command line leaves
  `config.json` the single source of truth.
- **Re-running is a no-op.** The setup script reuses the existing bcrypt hash
  when it still verifies against `$PASEO_PASSWORD` (bcrypt re-salts on every
  call, so hashing unconditionally would churn the config), and only restarts a
  daemon when the unit or config actually changed — re-running will not
  interrupt agents mid-task.
- **Upgrades**: macOS via `./deploy.zsh` (brew cask, or the app's own updater);
  ceres by re-running `./scripts/setup-paseo.sh`, which re-resolves
  `npm:@getpaseo/cli@latest` through mise.
- **`node-pty`**: Paseo pins `node-pty 1.2.0-beta.15`, which ships a
  `prebuilds/linux-x64` binary — so ceres avoids the build-from-source dance
  `setup-t3.sh` needs. The setup script verifies it anyway; that failure is
  invisible until someone opens an agent terminal.

## Two `paseo` binaries — don't

The cask installs the app **and** a version-locked `paseo` CLI symlinked into
the brew prefix. `@getpaseo/cli` is therefore deliberately **not** in
`.default-npm-packages`: two `paseo` binaries of drifting versions on one PATH
is the Vite+ split-brain again (see the note in
`scripts/deploy.d/70_runtime_installs.zsh`). ceres, which has no cask, gets the
CLI as a mise tool, and `zsh/rc.d/12_paseo.zsh` defines a `paseo` function there
that runs it through `mise exec` — the bare shim would error `No version is set
for shim` until activated, and activating would dirty this repo's symlinked
`mise.toml`.

## Files

| Path | What |
|---|---|
| `scripts/setup-paseo.sh` | per-host install + config + service. One-shot, idempotent. |
| `scripts/paseo-config.mjs` | idempotent `~/.paseo/config.json` deep-merge, atomic 0600 write |
| `scripts/deploy.d/75_brew_setup.zsh` | `paseo` cask on macOS |
| `zsh/rc.d/12_paseo.zsh` | `paseo-at` / `paseo-ceres` / `paseo-hosts`, mise wrapper |
| `zsh/env.d/90_secrets.zsh` | `PASEO_PASSWORD` (encrypted) |
| `/etc/systemd/system/paseo-daemon.service` | generated on ceres by the setup script |
| `~/Library/LaunchAgents/local.paseo-daemon.plist` | generated on the Macs by the setup script |
