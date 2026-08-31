# Paseo runbook

[Paseo](https://github.com/getpaseo/paseo) is a self-hosted daemon that runs
Claude Code / Codex / Copilot / OpenCode / Pi agents on your own machines and
exposes them to a desktop app, a phone app, a browser, and a CLI. It carries no
model credentials of its own — it drives the agent CLIs already installed and
logged in on the box.

Apache-2.0. CLI and desktop app versions should stay in lockstep; on a fork
host the daemon instead reports the app's version with a `.fork.N` suffix —
see *Fork release channel*. The Macs use the beta channel in the desktop app
under **Settings → About → Release channel**; the headless Linux install
tracks npm's `@beta` dist-tag.

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

Three deliberate choices in that plist:

- **One-shot** (`RunAtLoad`, no `KeepAlive`). `paseo daemon start` exits 1 when
  a daemon already holds the port — it leaves the running one alone, but under
  `KeepAlive` that non-zero exit becomes a restart loop every time the app got
  there first. One-shot means: start it at login if nothing else has, otherwise
  fail harmlessly into `~/.paseo/launchd.err`.
- **`AbandonProcessGroup`** is load-bearing. `paseo daemon start` forks and
  returns; without it launchd reaps the whole process group when the job exits
  and kills the daemon it just started.

- **`USER`** decides which credential store Claude Code reads, and is the
  subtlest of the three. Claude Code looks its OAuth token up in the login
  keychain as generic-password service `Claude Code-credentials`, account
  `$USER`. launchd hands a LaunchAgent no `USER` at all — only what
  `EnvironmentVariables` declares — so without it the keychain lookup cannot be
  formed and Claude Code silently falls back to its *file* store,
  `~/.claude/.credentials.json`. See *One login, two stores* below.

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

### One login, two stores

Symptom — agents die, the daemon looks perfectly healthy, and `daemon.log`
carries:

```
"lastResponse":"Failed to authenticate. API Error: 401 OAuth access token has been revoked."
```

Note **revoked**, not *expired*. Claude Code keeps its OAuth token in the login
keychain (`Claude Code-credentials`, account `$USER`) **and** understands a file
store at `~/.claude/.credentials.json`. A box that has ever written the file
holds two copies of one login — and OAuth refresh tokens are single-use, so each
renewal of the keychain copy revokes the token the file still carries. The file
does not decay gracefully; it goes hard-invalid and stays that way. On this
fleet the stale copy dated from June while the keychain copy was renewed daily.

Which store a process reads is decided by whether `USER` is set. That is why the
same binary succeeds in your terminal and 401s under the daemon:

```zsh
P="$HOME/.local/share/mise/shims:$HOME/.local/bin:/usr/bin:/bin"
env -i HOME="$HOME" PATH="$P"              claude -p "say ok"   # 401 revoked  -> file
env -i HOME="$HOME" PATH="$P" USER="$USER" claude -p "say ok"   # ok           -> keychain
```

Those two lines are the diagnostic: if the second succeeds and the first does
not, the login is fine and the daemon's environment is at fault. Fix it in the
plist (`setup-paseo.sh` writes `USER` and `LOGNAME`), not by re-logging-in.

Copying the keychain token into the file is the tempting non-fix — it re-creates
exactly the two-copies-of-one-grant state that breaks at the next renewal. If
you want the file gone, delete it; the keychain is the store that gets renewed.

The same trap is not unique to Claude Code: any provider CLI that resolves a
per-user credential store will misresolve it under launchd. When a new provider
starts failing only under the daemon, test it with the two lines above before
touching its login.

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

The fork channel amends this from an existence rule to a **PATH-level** rule:
interactive `paseo` stays stock on every host — the brew symlink on the Macs,
lockstepped with the app; the `zsh/rc.d/12_paseo.zsh` wrapper running stock
`@latest` on ceres — and fork binaries appear only as versioned absolute
references in launchers, never on PATH. In particular, the fork CLI is never
an mise tool on a Mac: an mise npm install drops a `paseo` shim into the
shims dir, and both the generated plist PATH and interactive shells search
the shims dir ahead of the brew prefix, so the shim would shadow stock
`paseo` — the exact split-brain this section bans. That is why the Macs
install the fork CLI with `npm install --prefix` (see *Fork release
channel*).

## Fork release channel

The fork channel ships daemon fixes from the `custom` branch of the paseo
fork to all three fleet hosts ahead of upstream, without touching the stock
installs above. What ships is the **CLI and the daemon it runs, only** — the
stock Paseo.app stays the GUI client of the forked daemons, and the stock
upgrade paths in *Upgrades* keep working as documented. Releases are cut by
`fork/scripts/release-fork.mjs` in a paseo checkout (publish under dist-tag
`fork`, plus a `fork/v<version>` tag and GitHub Release for provenance); this
section is what an operator at a terminal needs.

- **Artifact home** is public npm under a personal scope. The commands here
  use `@paseo-fork` — the release tooling's working default (`FORK_SCOPE`
  overrides it); the concrete scope is pending approval, and if it changes,
  every command in this section changes with it.
- **Dist-tag `fork`, only `fork`.** Hosts pin exact versions; a daemon is
  never installed floating. The first publish leaves the fresh scope with
  **no `latest` dist-tag**, so a bare `npm install @paseo-fork/paseo-cli`
  errors — correct for a pinned fleet. Do not fix it by moving `latest`.
- **Versions are `<upstream base>.fork.N`** — today `0.7.0-beta.2.fork.1`.
  Semver orders a fork strictly between its base and the next upstream beta
  (`0.7.0-beta.2 < 0.7.0-beta.2.fork.1 < 0.7.0-beta.3`), so a fork host is
  never older than the stock it replaced. When upstream promotes the base to
  stable, the scheme becomes `0.7.0-fork.1` — which sorts *below* stock
  `0.7.0`, as a prerelease of the same version. No npm-hostable scheme avoids
  that, so at promotion the never-older property moves to the two rules that
  carry it day to day: the **base floor** and the protocol-compatibility
  contract (both below).
- **No third-party plugins.** The pack-time rename rewrites the current
  `@getpaseo/plugin*` SDK spellings, and the SDK exists under the fork only
  as `@paseo-fork/paseo-plugin`, so a stock plugin cannot resolve what it
  imports. The fleet runs none; plugin support stays out of scope.
- **The daemon's built-in self-update fails safely** on a fork install: its
  install-origin check (`npm -g @getpaseo/cli`) never matches a mise or
  `--prefix` install. Upgrades are runbook-owned (below); treat the error as
  expected and leave it broken.

### Upgrading a fork host

Smoke the exact artifact first — scratch home, scratch port 6998, always
before any repoint. This is the gate that catches a missed rewrite or a
missing native binary while production is still untouched:

```zsh
# ceres; on the Macs swap the mise exec for the prefix binary
mise install npm:@paseo-fork/paseo-cli@0.7.0-beta.2.fork.1
PASEO_LISTEN=127.0.0.1:6998 PASEO_LOCAL_SPEECH_AUTO_DOWNLOAD=0 \
  PASEO_DICTATION_ENABLED=0 PASEO_VOICE_MODE_ENABLED=0 \
  mise exec npm:@paseo-fork/paseo-cli@0.7.0-beta.2.fork.1 -- \
  paseo daemon start --foreground --home /tmp/paseo-fork-smoke
```

`paseo --version` must print the fork string and `/api/health` must return
200 on 6998; stop the scratch daemon afterwards. The three `PASEO_*` speech
knobs are the same ones paseo's own test suite uses to keep test daemons
quiet — without them, a fresh home eagerly downloads a few hundred MB of
speech models (see *Operational notes*).

ceres — one `sudo -E` run re-installs the pinned tool, rewrites the unit,
restarts the daemon, and verifies `/api/health`. The restart is the human
moment: an agent inside `paseo-daemon.service` cannot sudo
(`NoNewPrivileges`), so agents stage and a human types. **`sudo -E` is
load-bearing** — the script reads `PASEO_PASSWORD` from the environment (see
*Upgrades*):

```zsh
cd ~/.local/dotfiles && echo "pw set: ${PASEO_PASSWORD:+yes}"   # must print yes
sudo -E PASEO_TOOL=npm:@paseo-fork/paseo-cli@0.7.0-beta.2.fork.1 ./scripts/setup-paseo.sh
```

saturn/neptune — **stop the daemon first** (either binary can stop it; same
home, protocol-compatible), install into a **versioned prefix** (never mise
on a Mac, see *Two `paseo` binaries*), then regenerate the plist through the
pin:

```zsh
paseo daemon stop
npm install --prefix ~/.local/share/paseo-fork/0.7.0-beta.2.fork.1 \
  @paseo-fork/paseo-cli@0.7.0-beta.2.fork.1
cd ~/.local/dotfiles
PASEO_FORK_BIN=$HOME/.local/share/paseo-fork/0.7.0-beta.2.fork.1/node_modules/.bin/paseo \
  ./scripts/setup-paseo.sh
launchctl kickstart -k gui/$(id -u)/local.paseo-daemon   # only if the daemon is not running after the script
```

The script validates `PASEO_FORK_BIN` up front (absolute and executable —
launchd consults no PATH), writes it into `ProgramArguments[0]`, and both
its start and restart branches exec the pinned binary — with the daemon
stopped first, the start branch brings the fork daemon up. The `kickstart
-k` is only a fallback for when the daemon is not running afterwards: it
re-runs the one-shot job, and `paseo daemon start` starts anything only
when 6767 is free — a live daemon is left alone, which is why the stop
comes first. Each version gets its own prefix; delete the stale one after
upgrading. A fresh interactive shell must still resolve `command -v paseo`
to the brew prefix.

### Rolling back to stock

Deliberate by design (next section). The Macs:

```zsh
paseo daemon stop                                                # stops the fork daemon
cd ~/.local/dotfiles && PASEO_ALLOW_STOCK_REVERT=1 ./scripts/setup-paseo.sh
launchctl kickstart -k gui/$(id -u)/local.paseo-daemon           # only if the daemon is not running
```

The override regenerates the plist at the brew symlink and restarts the
daemon stock. Verify the stock version and a single listener (below), then
optionally remove `~/.local/share/paseo-fork/<version>`. ceres is the mirror
with an explicit stock pin — set, so the guard does not trip:

```zsh
cd ~/.local/dotfiles && echo "pw set: ${PASEO_PASSWORD:+yes}"   # must print yes
sudo -E PASEO_TOOL=npm:@getpaseo/cli@0.7.0-beta.2 ./scripts/setup-paseo.sh
```

It rewrites the unit back to the stock default and restarts through systemd.

### Verifying a fork host

Invoke the fork binary explicitly. Bare `paseo status` is **expected** to
report the stock CLI — interactive `paseo` stays stock on every host (see
*Two `paseo` binaries*) — and is not a failure signal:

```zsh
# ceres
mise exec npm:@paseo-fork/paseo-cli@0.7.0-beta.2.fork.1 -- paseo status
# saturn / neptune
~/.local/share/paseo-fork/0.7.0-beta.2.fork.1/node_modules/.bin/paseo status
```

Three surfaces must agree on the fork string: the fork binary's `--version`,
the daemon version it reports via `status`, and the daemon version shown in
the stock app (**Settings → your host → Overview**). Exactly one listener on
6767, owned by the fork daemon:

```zsh
lsof -nP -iTCP:6767 -sTCP:LISTEN
```

Reboot survival is by design (one-shot `RunAtLoad` plist;
`Restart=on-failure` unit) but is checked, not assumed: at the next natural
reboot, re-check the single listener and that the daemon still reports the
fork version.

### The pin is an invariant, not an event

`setup-paseo.sh` regenerates launchers from defaults on every routine re-run
(password rotation, hostname change, `PASEO_WEB_UI` toggle). **Every run on a
fork host carries the pin** — `PASEO_TOOL` on ceres, `PASEO_FORK_BIN` on the
Macs. When a run carries no pin and the on-disk launcher points at a fork
build (a `.fork.` version or a non-`@getpaseo` npm scope in the unit's
`ExecStart` or the plist's `ProgramArguments[0]`), the script prints a loud
warning naming the detected pin and both ways out — the exact
re-run-with-pin command, or the deliberate `PASEO_ALLOW_STOCK_REVERT=1`
revert — and skips only the launcher rewrite. Config and password changes
still apply; on ceres a config-driven restart still goes through the
existing pinned unit, and on the Macs the script also keeps the stock CLI
away from the daemon entirely, leaving it running until the next pinned
run. Rollback is therefore never an accident: stock means the override or
the explicit pin, as spelled above.

The Mac guard has a second half for the same reason: `paseo daemon restart`
respawns the daemon from the *calling* CLI's `require.resolve`, so a stock
`paseo` on PATH would silently revert a fork daemon while the plist still
names the fork binary. The script honors `PASEO_FORK_BIN` on both the start
and the restart branches and never lets the PATH binary near the daemon.

### The base floor

Repoint a host to a fork build only when the fork's upstream base is at
least the version of the stock client that talks to it — today, base
`0.7.0-beta.2` under the `0.7.0-beta.2` app. After any stock app
auto-update, check the floor: once the app moves past the fork base, rebase
the fork, cut the next fork release, and repoint. In between, the
protocol-compatibility contract is the safety net: old daemon and new app
parse each other in both directions, and features gate on `server_info`
capability flags, never on version comparison. This rule — not semver —
carries the never-older property once the base is a stable
(`0.7.0-fork.1` sorts below stock `0.7.0`; see the version scheme above).

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
