# Keychron K10 HE — firmware keymap

`k10-he-keymap.json` is the keymap exported from **Keychron Launcher**
(<https://launcher.keychron.com>) for the Keychron K10 HE (Hall-Effect).

This is a **reference artifact, not an auto-deployed config.** Keychron Launcher
is a web app that flashes the board over WebHID; there is no CLI to apply a
keymap, so this file is version-controlled for backup/reproducibility and
applied **manually**:

> Launcher → connect the K10 HE → **Import keymap** → select this file → **Flash**.

Re-export and re-commit this file whenever you change the board in Launcher, so
the repo stays the source of truth for what's flashed.

## Why the keyboard is a keybinding layer

The K10 HE sits at the **lowest** of the three layers that make up the
[keybinding scheme](../../docs/keybindings/README.md):

| Layer | Tool | Reach |
|-------|------|-------|
| Firmware (this file) | Keychron Launcher | Below HID — travels through **anything**, including Universal Control / KVM, but has no app context |
| Grabbed-HID remap | Karabiner (`../karabiner/karabiner.ts`) | One machine, full app context, invisible to synthetic input |
| High-layer hotkeys | Raycast / AeroSpace | Catches synthetic input (UC), but only fires commands — can't remap keys |

The rule of thumb: push each action to the **lowest layer that still satisfies
its needs**. Anything the firmware can express (a mod-tap, a plain remap)
survives keyboard/mouse sharing to another Mac; anything needing app-awareness
(the terminal-excluded text-nav) must stay in Karabiner and is host-only.

## Intended firmware change: Caps → Hyper / Escape

As exported, **Caps Lock is still `KC_CAPS`** (matrix row 3 col 0 = `57`). The
plan is to move the Caps mod-tap *off* Karabiner and *into* firmware so it works
on every host, including a Universal-Control target:

> Caps → **`HYPR_T(KC_ESC)`** — hold = Hyper (`⌘⌃⌥⇧`), tap = Escape.

In Launcher, set the Caps key via the mod-tap / custom-keycode field. If the HE
Launcher build doesn't expose `HYPR_T` (verify in the UI), keep Caps→Hyper/Esc
in Karabiner as the fallback (host-only). After flashing, **re-export and
re-commit this file.**
