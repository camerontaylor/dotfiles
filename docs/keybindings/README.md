# Keybindings, navigation, GUI & window management

A single, machine-agnostic keyboard scheme built on **four disjoint modifier
planes**. Each plane owns exactly one job so chords never collide:

| Plane | Modifier | Owns | Implemented by |
|-------|----------|------|----------------|
| **Cmd** | `⌘` | Native macOS (copy/paste, switcher, Raycast launcher) | macOS itself — left alone on purpose |
| **Ctrl** | `⌃` | Emacs / readline nav in terminals & native text fields | macOS / readline — left alone on purpose |
| **Hyper** | Caps Lock (hold) | App launching + Raycast actions | [Karabiner-Elements](#karabiner-elements--hyper-layer--linux-style-text-nav) |
| **Alt** | `⌥` (Super on Linux) | Tiling window management | [AeroSpace](#aerospace--tiling-window-management) |

The guiding idea is *don't fight the OS*: `⌘` stays the primary Mac modifier and
terminals keep their native `⌃` emacs nav. We only fix the two things that
actually hurt coming from Linux — Caps Lock becomes useful, and Home/End/word
navigation behaves the Linux way in GUI apps.

> **Printable cheat sheet:** [`keybindings-cheatsheet.html`](keybindings-cheatsheet.html)
> — open in a browser and `⌘P` (scale to fit) for a two-column A4 reference.

---

## What lives where

| Concern | Source of truth | Deployed to | How |
|---------|-----------------|-------------|-----|
| **macOS** — Hyper layer + text navigation | [`configs/karabiner/karabiner.ts`](../../configs/karabiner/karabiner.ts) | `$XDG_CONFIG_HOME/karabiner/karabiner.json` | **generated** by [`scripts/deploy.d/78_karabiner.zsh`](../../scripts/deploy.d/78_karabiner.zsh) |
| **macOS** — tiling window manager | [`configs/aerospace/aerospace.toml`](../../configs/aerospace/aerospace.toml) | `$XDG_CONFIG_HOME/aerospace/aerospace.toml` | **symlinked** by [`scripts/deploy.d/20_symlinks.zsh`](../../scripts/deploy.d/20_symlinks.zsh) |
| **macOS** — app + cask installs | — | — | [`scripts/deploy.d/75_brew_setup.zsh`](../../scripts/deploy.d/75_brew_setup.zsh) |
| **Linux** — Caps→Esc/Hyper | [`configs/keyd/default.conf`](../../configs/keyd/default.conf) | `/etc/keyd/default.conf` | **installed (sudo)** by [`scripts/deploy.d/79_keyd.zsh`](../../scripts/deploy.d/79_keyd.zsh) |
| **Linux** — tiling window manager | [`configs/sway/config`](../../configs/sway/config) | `$XDG_CONFIG_HOME/sway/config` | **symlinked** by [`scripts/deploy.d/20_symlinks.zsh`](../../scripts/deploy.d/20_symlinks.zsh) |
| Printable reference (both) | [`keybindings-cheatsheet.html`](keybindings-cheatsheet.html) | — | committed doc |

The same scheme is implemented on **both platforms**: macOS via Karabiner +
AeroSpace, Linux via keyd + Sway. Super sits where `⌥` does on a Mac, so the WM
modifier is under the same finger everywhere and the planes stay 1:1. The macOS
configs run on the two Macs; the Linux configs target the graphical boxes
(CachyOS desktop + laptop) — headless servers never start a WM, so their symlink
is simply inert.

---

## Karabiner-Elements — Hyper layer & Linux-style text nav

`configs/karabiner/karabiner.ts` is a **typed, self-contained generator**: it
emits the Karabiner JSON rather than being hand-written. It produces three rules:

1. **Caps Lock → Hyper / Escape** — hold Caps for the Hyper layer, tap it for
   Escape.
2. **Linux-style text navigation** (GUI apps only — terminals are excluded by
   bundle id, so readline/emacs nav survives):
   - `Home` / `End` → line start / end (`⌘←` / `⌘→`)
   - `⌃←` / `⌃→` → word left / right (`⌥←` / `⌥→`)
   - `⌃Home` / `⌃End` → document start / end
   - `⌃⌫` / `⌃⌦` → delete word back / forward
   - Shift variants extend the selection.
3. **Hyper launch layer** (hold Caps + key):

   | Key | Action | Key | Action |
   |-----|--------|-----|--------|
   | `t` | Ghostty (terminal) | `n` | Obsidian (notes) |
   | `b` | Browser | `m` | Spotify (music) |
   | `c` | VS Code | `g` | ChatGPT |
   | `f` | Finder | `v` | Raycast clipboard history |
   | `s` | Slack | `e` | Raycast emoji picker |

   `Hyper+Space` emits the literal `⌘⌃⌥⇧` chord for apps that want a real Hyper
   hotkey. **Edit the app names in `karabiner.ts`** to match what you install.

### Why generated, not symlinked

Karabiner-Elements *owns* the live `karabiner.json` — it rewrites that file from
its own GUI and injects machine-specific device state (per-keyboard identifiers)
we don't want bleeding across machines via the repo. So `78_karabiner.zsh`
generates a real file and then leaves Karabiner free to manage it.
Regeneration is **gated on the generator being newer** than the installed config,
so GUI tweaks aren't clobbered on every deploy. To push a curated change, edit
`karabiner.ts` and re-run deploy (or run it directly: `bun configs/karabiner/karabiner.ts`).
The generated JSON is a build artifact and is intentionally **not committed**.

---

## AeroSpace — tiling window management

`configs/aerospace/aerospace.toml` is an i3/Sway-style tiling WM for macOS,
symlinked into place (AeroSpace only ever reads it). Highlights:

- **Focus** `⌥ h j k l`; **move window** `⌥⇧ h j k l` — boundaries stop, so
  focus never shoves the cursor off-screen toward another Mac.
- **Workspaces** `⌥ 1…9`; **send window → workspace + follow** `⌥⇧ 1…9`;
  `⌥Tab` back-and-forth.
- **Layout** `⌥/` tile orientation, `⌥,` accordion, `⌥F` fullscreen,
  `⌥⇧Space` float/unfloat.
- **Resize** `⌥-` / `⌥=`, `⌥0` balance.
- **Multi-monitor (one Mac)** `⌥⌃ h/l` focus monitor; `⌥⇧⌃ h/l` move workspace.
- **Service mode** `⌥⇧;` then: `Esc` reload, `r` flatten tree, `⌫` close all but
  current, `⌥⇧ h j k l` join with neighbour (build grids).

**JankyBorders** is installed alongside (`75_brew_setup.zsh`) to draw a colored
border around the focused window — a tiling WM has no titlebars, so the border
is how you see focus.

### Two Macs + Universal Control

The config is meant to run **identically on both Macs** — each runs its own
AeroSpace instance while Universal Control roams input between them at a separate
layer. Mouse-follows-focus is deliberately tame (`monitor-lazy-center`, only on
explicit monitor switch) so a focus change can't fling the cursor at a screen
edge and trip UC's handoff.

One-time per-Mac system settings (not expressible in the config — see the
comment block at the top of `aerospace.toml` and the cheat sheet):

- **Displays → "Push through the edge…" → OFF** (makes UC handoff deterministic)
- **Desktop & Dock → "Displays have separate Spaces" → OFF** (AeroSpace is far
  more stable with one Space)

---

## Linux — Sway + keyd

The Linux plane mirrors the Mac plane one-for-one:

- **`configs/keyd/default.conf`** is the counterpart to the Karabiner Caps rule.
  [keyd](https://github.com/rvaiya/keyd) is a system-level remapper (runs as root,
  before the compositor), so Caps→Esc-on-tap / Hyper-on-hold works identically
  under Wayland, X11, and the TTY. The Hyper hold emits `Control+Alt+Shift+Super`,
  which Sway reads as `$hyper = Mod4+Mod1+Control+Shift`.
- **`configs/sway/config`** is the counterpart to `aerospace.toml`: `$mod = Super`,
  same `hjkl` focus/move, `$mod 1…9` workspaces, `$mod+Shift 1…9` send-window,
  multi-monitor on `$mod+Ctrl h/l`, plus a `$hyper`-prefixed launch plane
  (`Caps+t/b/c/f/s/n/m/v/e`) matching the Mac mnemonics.

Because there's no Cmd plane on Linux, window-close lives on `$mod+Shift+q` and
config reload/restart on `$mod+Shift+c` / `$mod+Shift+r`. The Sway config also
wires the surrounding Wayland stack (waybar, mako, cliphist, swayidle/swaylock,
grim/slurp screenshots, fuzzel launcher) — those tools must be installed
separately via your distro's package manager.

### Why keyd needs root, not a symlink

Every other config here is a user-level XDG symlink, but keyd reads
`/etc/keyd/default.conf` as root before the session even starts. So
`79_keyd.zsh` copies the tracked config into `/etc` with `sudo` (backing up any
existing file), enables the service, and runs `sudo keyd reload`. It only acts
when the `keyd` binary is present — otherwise it prints install guidance and
leaves `/etc` untouched, so a re-deploy after installing keyd wires it up.
Verify what keyd emits with `sudo keyd monitor`.

---

## Installing / refreshing

Everything is wired through the normal deploy flow:

```sh
# macOS
./deploy.zsh                  # symlinks aerospace.toml, generates karabiner.json
./deploy.zsh --only karabiner # regenerate just the Karabiner config
bun configs/karabiner/karabiner.ts   # regenerate directly (see errors)

# Linux
./deploy.zsh                  # symlinks sway/config, installs /etc/keyd/default.conf
./deploy.zsh --only keyd      # reinstall + reload just the keyd config
sudo keyd reload              # apply keyd changes without a full deploy
swaymsg reload                # apply sway changes in a running session
```

On macOS the casks (AeroSpace, Karabiner-Elements, JankyBorders) are installed by
the brew fragment; after first install, grant Karabiner and AeroSpace the
Accessibility / Input Monitoring permissions macOS prompts for. On Linux, install
`keyd`, `sway`, and the Wayland stack via your package manager (keyd is often in
the AUR on Arch/CachyOS), then run deploy.
