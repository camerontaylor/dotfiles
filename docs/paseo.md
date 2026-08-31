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

On the Macs the cask arrives through the normal deploy
(`scripts/deploy.d/75_brew_setup.zsh`), but **install-only** — deploy will never
upgrade it. The cask tracks Paseo's *stable* channel while both Macs run *beta*,
and brew judges freshness from its Caskroom receipt rather than the app bundle,
so every deploy upgrade was really a downgrade applied under a live daemon. Two
guards enforce that (they cover different callers, so both are needed): `paseo`
is listed in `$brew_upgrade_skip`, which holds it out of the bare `brew upgrade`
sweep, and its own block has no upgrade branch. See *Upgrades* below.

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

Headless web UI on ceres — **disabled since 2026-08-29**. The daemon can serve
a browser client on its own port, and did on ceres, but it served static files
*without auth* on a service whose whole purpose is running code as you. The
desktop and phone apps already cover that job, so it is off by default:

```zsh
# it is a knob, not a deletion — Linux only, macOS keeps the upstream default
PASEO_WEB_UI=true sudo -E ./scripts/setup-paseo.sh
```

`features.webUi.enabled` is a **startup** setting: `paseo reload` accepts the
new config but reports the path under "these changes require a daemon restart",
so the UI keeps serving until the daemon actually bounces.

Do not reach for `paseo daemon restart` on ceres to force it. The unit is
`Restart=on-failure`, so a *clean* stop is not restarted by systemd — and since
the daemon is `User=ctaylor` + `NoNewPrivileges=true`, nothing running inside it
can sudo the unit back up. Let the next `sudo -E ./scripts/setup-paseo.sh` apply
it, which is also how the CLI gets upgraded.

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
- **Upgrades**: **not** `./deploy.zsh` and **not** `brew upgrade --cask paseo`
  on macOS — both downgrade a beta box to stable (see above). Let the app update
  itself (**Settings -> About -> Release channel** = `beta`), or install the
  release by hand, which is the only way to force a specific beta:

  ```zsh
  # neptune is Intel -> -x64.dmg; saturn is Apple Silicon -> -arm64.dmg
  v=0.7.0-beta.2
  curl -fsSL -o /tmp/paseo.dmg \
    https://github.com/getpaseo/paseo/releases/download/v$v/Paseo-$v-x64.dmg
  hdiutil attach -nobrowse -quiet /tmp/paseo.dmg -mountpoint /tmp/paseo-mnt
  spctl -a -vv -t install /tmp/paseo-mnt/Paseo.app   # expect: accepted / Notarized Developer ID
  osascript -e 'quit app "Paseo"'                    # the daemon dies with the app
  mv /Applications/Paseo.app /tmp/Paseo.app.bak && ditto /tmp/paseo-mnt/Paseo.app /Applications/Paseo.app
  xattr -dr com.apple.quarantine /Applications/Paseo.app
  hdiutil detach /tmp/paseo-mnt -quiet
  launchctl kickstart -k gui/$(id -u)/local.paseo-daemon && open -a Paseo
  ```

  `/Applications` is admin-group writable, so none of this needs `sudo`. The
  `paseo` CLI is a symlink into the app bundle, so it follows automatically.

  ceres: re-run `./scripts/setup-paseo.sh`, which re-resolves `PASEO_TOOL`
  (default `npm:@getpaseo/cli@beta`) through mise and rewrites the unit. It
  needs root, and **`sudo -E` is load-bearing** — the script reads
  `PASEO_PASSWORD` from the environment and never sources `90_secrets.zsh`
  itself; without it the script refuses to widen the bind past `127.0.0.1`,
  cutting off the phone and the rest of the fleet:

  ```zsh
  cd ~/.local/dotfiles && echo "pw set: ${PASEO_PASSWORD:+yes}"   # must print yes
  sudo -E PASEO_TOOL=npm:@getpaseo/cli@0.7.0-beta.2 ./scripts/setup-paseo.sh
  ```

  A Paseo *agent* on ceres cannot do this to itself: agents run inside
  `paseo-daemon.service`'s own cgroup, which is `User=ctaylor` +
  `NoNewPrivileges=true`, so `sudo` fails outright. An agent can safely stage
  the version (`mise install npm:@getpaseo/cli@<ver>`) and leave the restart to
  a human at a real terminal.
- **`node-pty`**: Paseo pins `node-pty 1.2.0-beta.15`, which ships a
  `prebuilds/linux-x64` binary — so ceres avoids the build-from-source dance
  `setup-t3.sh` needs. The setup script verifies it anyway; that failure is
  invisible until someone opens an agent terminal.

## Troubleshooting: "paseo is down"

### `daemon status` lies about two of its four health fields

Against a **completely healthy** daemon, `paseo daemon status` (CLI
`0.7.0-beta.2`) reports:

```
Local Daemon      unresponsive
Connected Daemon  unreachable
Note              Local daemon PID is running but websocket at :::6767 is not reachable
```

Verified 2026-08-31 on neptune *and* saturn at the same time — saturn's daemon
had not crashed, was serving the phone, and still printed all three lines. It is
a CLI probe bug, not a per-box fault. Do not go chasing a bind or an auth
problem on the strength of that `Note`; the daemon really is listening on
`[::]:6767` and the websocket really does accept upgrades.

`Local Daemon` is worth reading for exactly one value: **`stale_pid` is real.**
It means the PID recorded in `~/.paseo/paseo.pid` is gone and nothing holds
6767 — the daemon is genuinely dead and needs the kickstart below.

The `Providers` block at the bottom of that output is also trustworthy; it is
resolved by the CLI itself rather than probed over the socket.

### Ground truth instead

```zsh
# 1. HTTP health on every address a client might use. All four must return 200.
ip4=$(tailscale ip -4)
for t in 127.0.0.1 '[::1]' localhost "$ip4"; do
  printf '%-18s ' "$t"
  curl -fsS -m 5 -o /dev/null -w '%{http_code}\n' "http://$t:6767/api/health" || echo FAIL
done

# 2. The websocket the phone and desktop actually speak. Want 101.
#    curl exits non-zero (28, timeout) because the socket stays open after the
#    upgrade — that is success, read the status code, not the exit code.
curl -s -m 5 -o /dev/null -w '%{http_code}\n' \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  http://localhost:6767/ws

# 3. End to end: does it list agents, and did real clients reattach?
#    Filter the metrics chatter or it buries everything else.
paseo ls
grep -a -o '"msg":"[^"]*"' ~/.paseo/daemon.log \
  | grep -av ws_runtime_metrics | tail -15   # want "Client connected via hello"

# 4. Is the bind dual-stack? TYPE must read IPv6, not IPv4 (see "Bind [::]" above).
lsof -nP -iTCP:6767 -sTCP:LISTEN
```

Check 2 proves the websocket endpoint is **live**, not that auth works: the
upgrade succeeds at the HTTP layer (101) and the daemon then rejects the
passwordless connection at the application layer. So the probe writes its own
scare line into `daemon.log` —

```
"userAgent":"curl/8.7.1","remoteAddress":"::1","hasToken":false,
"msg":"Rejected WebSocket connection with invalid daemon password"
```

— one per run. Before reading that as a client failing to authenticate, check
`userAgent` and `hasToken`: `curl/*` with `hasToken:false` is your own probe.

What actually proves auth works is a real client reaching `Client connected via
hello`. Grep for it and read the user-agent: `okhttp/*` from a `100.x`
`remoteAddress` with `"peer":"external"` is **the phone over Tailscale**, which
is usually the thing you are really trying to confirm. A client that cannot
authenticate logs the rejection under its own user-agent and never reaches
`hello`. `Daemon password authentication enabled` in the startup log confirms
the daemon is enforcing a password at all.

### Recovering a dead macOS daemon

The LaunchAgent is one-shot `RunAtLoad` with no `KeepAlive` (deliberately — see
*macOS has no launch-at-login* above), so a daemon that dies **mid-session stays
dead until the next login**. `launchctl print` will show `state = not running`
and `active count = 0`, which is correct and not itself the fault.

```zsh
ssh neptune 'launchctl kickstart -k gui/$(id -u)/local.paseo-daemon'
```

Agents survive this. The five agents on neptune — including two mid-run —
reattached from `~/.paseo/agents/` after a 2026-08-31 restart. Prefer the
kickstart over a bare `paseo daemon start` so the LaunchAgent stays the single
daemon owner.

### A full disk kills the daemon silently

This is how neptune went down on 2026-08-30. The daemon takes an unhandled
`ENOSPC` while persisting an agent snapshot and exits with no crash report, no
dialog, and nothing in the system log:

```zsh
grep -a ENOSPC ~/.paseo/daemon.log | tail -3
```

```
Error: ENOSPC: no space left on device
path: /Users/ctaylor/.paseo/agents/<agent>/.<uuid>.json.<pid>.<ts>.tmp
```

Nothing restarts it afterwards, so the box drops off the phone until someone
notices. Note the disk may look fine by the time you investigate — the daemon
dying releases its own handles, and `56_tmpdir_prune.zsh` reaps `~/.tmp` daily.
Check the log for `ENOSPC` before concluding the disk was never the problem.
neptune's usual offenders, worst first: `~/.tmp/ruby-build.*`, `mise prune`,
`~/.cache/npm`, then `~/repos/worktrees` and `~/.paseo/worktrees`.

### `launchd.err` is append-mode — check timestamps before trusting it

The plist appends rather than truncates, so the tail of
`~/.paseo/launchd.err` can be months stale and reference a hostname and daemon
version that no longer exist. On neptune in 2026-08 its last lines were still
from `"hostname":"iMac"` / `"daemonVersion":"0.4.0"` in the previous August —
including a run of `Rejected WebSocket connection with invalid daemon password`
that had nothing to do with the outage being diagnosed. Read `~/.paseo/daemon.log`
for current state; treat `launchd.err` as history.

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
