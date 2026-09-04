# Resource monitoring

What is using the CPU / memory / disk / network / GPU, and what *was* using it
an hour ago. Derived from a 2026-08-23 recommendation review; installed by
`scripts/deploy.d/42_monitoring.zsh` (Linux), `scripts/deploy.d/75_brew_setup.zsh`
(macOS) and `configs/mise.toml` (both), and smoke-tested by
`scripts/deploy.d/85_verify_tools.zsh`.

## The premise: `top` conflates three jobs

Replacing `top` with a single prettier `top` always disappoints, because `top`
is answering three different questions badly at once. Split them and each has a
clear best answer:

| Layer | Question | Why one tool can't cover it |
|---|---|---|
| **Glance** | what is happening *right now* | needs to be instant and always-on |
| **Attribution** | *which process*, and for which resource | needs per-resource kernel plumbing |
| **History** | what ate the box at 03:12 | must have been recording *before* you asked |

A fourth layer — **profiling** — answers "which *function* in which process",
and only matters once attribution has named the process.

## What is installed

| Layer | Tool | Linux | macOS | Notes |
|---|---|---|---|---|
| Glance | `btop` | mise | brew | primary. disk + net + CPU + GPU in one place |
| Glance | `htop` | pacman | brew | fallback over SSH and on low-memory boxes |
| Apple Silicon | `macmon` | — | brew, **arm64 only** | power draw, ANE-vs-GPU split |
| Attribution | `bandwhich` | mise | mise | per-process network |
| Attribution | `iotop-c` | pacman | — | per-process block I/O (binary is `iotop`) |
| Attribution | `bpftrace` | pacman | — | short-lived processes; `execsnoop`/`opensnoop` |
| Attribution | `nvtop` | pacman | — | GPU, incl. Intel i915 (ceres has UHD 630) |
| History | `atop` | pacman | — | no real competitor; **needs its units enabled** |
| Profiling | `samply` | mise | mise | sampling profiler → Firefox Profiler UI |

Per host: ceres gets everything except `macmon`; saturn (Apple Silicon) gets
the macOS column including `macmon`; neptune (Intel Mac) gets the macOS column
*without* `macmon`.

### Deliberately not installed

- **`bottom` / `btm`** — its one unique feature is a TOML pane layout, which is
  not a need we have. `btop` already owns the glance layer, and the binary
  being named `btm` rather than `bottom` is a permanent low-grade annoyance.
- **`mactop`** — same IOReport basis as `macmon` plus fans, thermal state and
  memory bandwidth. More surface area for questions we don't currently ask.
- **`perf`** — `samply` is the cross-platform profiler and needs no
  kernel-version-matched userspace package. Add `perf` + `hotspot` by hand if
  you ever need native depth.

## Three things that make this silently useless

Each of these has already bitten this fleet.

### 1. A mise tool installed but not declared

`btop`, `bandwhich` and `samply` were once installed straight into mise's store
without being added to `configs/mise.toml`. mise then knew the *binary*
existed but had no version to resolve, so every invocation died with:

```
mise ERROR No version is set for shim: bandwhich
```

`bandwhich` and `samply` were dead on ceres for ~6 days and nothing reported
it. **Never `mise use -g` a tool here** — add it to `configs/mise.toml` and let
deploy install it, and add it to `85_verify_tools.zsh` so a future breakage
surfaces as a warning instead of a surprise.

### 2. `atop` installed but not recording

`atop`'s entire value is answering questions *after* the fact, and it can only
do that if `atop.service` has been writing samples to `/var/log/atop` all
along. Installed-but-not-enabled looks identical to installed-and-working right
up until the moment you need the data. `42_monitoring.zsh` enables
`atop.service` (interval samples) and `atopacct.service` (process accounting,
so processes that start *and exit* between samples still appear).

Replay with `atop -r /var/log/atop/atop_YYYYMMDD`, then `t` / `T` to step
forward and back through the intervals.

### 3. `samply` blocked by `perf_event_paranoid`

Arch ships `kernel.perf_event_paranoid = 2` ("userspace measurements only"), at
which `samply` cannot profile. `42_monitoring.zsh` drops it to `1` via
`/etc/sysctl.d/60-perf-profiling.conf`.

This is a **permission gate only** — it is checked inside `perf_event_open(2)`
and enables no collection, so there is no idle cost. The trade-off is
disclosure: at `1`, any local process can read kernel profiling data. Accepted
for a single-user dev box (Cameron, 2026-09-04). To revert:

```sh
sudo rm /etc/sysctl.d/60-perf-profiling.conf
sudo sysctl -w kernel.perf_event_paranoid=2
```

## Recipes

```sh
btop                          # glance
bandwhich                     # what is talking to the network, by process
sudo iotop -o                 # only processes actually doing I/O
nvtop                         # GPU

# a process is being spawned in a loop and no sampling monitor catches it
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s %s\n", comm, str(args->filename)); }'

# what happened at 03:12 this morning
atop -r /var/log/atop/atop_$(date +%Y%m%d)

# which function is hot (opens the Firefox Profiler UI)
samply record ./my-slow-program

# macOS, Apple Silicon only: power draw incl. ANE vs GPU
macmon                        # TUI
macmon -i 500                 # faster refresh (interval is in MILLISECONDS)
macmon pipe                   # JSON per sample, for scripting
macmon serve                  # same metrics over HTTP
```
