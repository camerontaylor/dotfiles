/**
 * karabiner.ts — typed, self-contained Karabiner-Elements config generator.
 *
 * Scope: the Caps Lock → Hyper (hold) / Escape (tap) mod-tap and the whole
 * Hyper launch layer now live in the *keyboard firmware* (Keychron Launcher,
 * see `../keychron/`) so they survive keyboard/mouse sharing (Universal Control)
 * to another Mac — firmware emits the modifiers below the HID layer, and Raycast
 * catches the resulting chord at the high layer. What remains here is the one
 * thing neither firmware nor Raycast can express: Linux-style text navigation
 * that is *app-aware* (terminals excluded so readline/emacs nav survives). That
 * needs Karabiner's grabbed-HID, frontmost-app-conditioned remapping, and is
 * therefore host-only by nature.
 *
 * Run:   npx tsx karabiner.ts        (or: bun karabiner.ts)
 * Writes ~/.config/karabiner/karabiner.json  (BACK UP your existing file first).
 * Karabiner hot-reloads on save. Ensure a profile named "Default" exists, or it
 * will be created by this writer.
 */

import { writeFileSync, mkdirSync, existsSync, copyFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ----------------------------------------------------------------------------
// Minimal slice of the Karabiner schema (enough for what we emit)
// ----------------------------------------------------------------------------
type Mod =
  | "left_command" | "left_control" | "left_option" | "left_shift"
  | "right_command" | "right_control" | "right_option" | "right_shift"
  | "command" | "control" | "option" | "shift" | "fn" | "any";

interface To {
  key_code?: string;
  modifiers?: Mod[];
}
interface From {
  key_code?: string;
  modifiers?: { mandatory?: Mod[]; optional?: Mod[] };
}
type Condition =
  | { type: "frontmost_application_if" | "frontmost_application_unless"; bundle_identifiers: string[] };

interface Manipulator {
  type: "basic";
  from: From;
  to?: To[];
  conditions?: Condition[];
  description?: string;
}
interface Rule { description: string; manipulators: Manipulator[] }

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
const key = (key_code: string, modifiers?: Mod[]): To => ({ key_code, modifiers });

// Terminals keep their native nav — don't let the GUI nav layer touch them.
const TERMINALS: Condition = {
  type: "frontmost_application_unless",
  bundle_identifiers: [
    "^com\\.apple\\.Terminal$",
    "^com\\.googlecode\\.iterm2$",
    "^net\\.kovidgoyal\\.kitty$",
    "^com\\.github\\.wez\\.wezterm$",
    "^io\\.alacritty$",
    "^com\\.mitchellh\\.ghostty$",
    "^dev\\.warp\\.Warp-Stable$",
  ],
};

/** A GUI-only key translation, e.g. Home -> Cmd+Left. */
const nav = (
  fromKey: string,
  fromMods: Mod[],
  toKey: string,
  toMods: Mod[],
): Manipulator => ({
  type: "basic",
  from: { key_code: fromKey, modifiers: { mandatory: fromMods, optional: ["caps_lock"] } },
  to: [key(toKey, toMods)],
  conditions: [TERMINALS],
});

// ----------------------------------------------------------------------------
// Rules
// ----------------------------------------------------------------------------

// Linux-style text navigation in GUI apps (terminals excluded).
// Edit/disable any block you don't want — these are deliberate, not magic.
const textNav: Rule = {
  description: "Linux-style text navigation (GUI apps only)",
  manipulators: [
    // Line start / end
    nav("home", [], "left_arrow", ["left_command"]),
    nav("end", [], "right_arrow", ["left_command"]),
    nav("home", ["shift"], "left_arrow", ["left_command", "left_shift"]),
    nav("end", ["shift"], "right_arrow", ["left_command", "left_shift"]),

    // Word left / right (Ctrl+Arrow on Linux → Option+Arrow on macOS)
    nav("left_arrow", ["control"], "left_arrow", ["left_option"]),
    nav("right_arrow", ["control"], "right_arrow", ["left_option"]),
    nav("left_arrow", ["control", "shift"], "left_arrow", ["left_option", "left_shift"]),
    nav("right_arrow", ["control", "shift"], "right_arrow", ["left_option", "left_shift"]),

    // Document start / end (Ctrl+Home / Ctrl+End)
    nav("home", ["control"], "up_arrow", ["left_command"]),
    nav("end", ["control"], "down_arrow", ["left_command"]),
    nav("home", ["control", "shift"], "up_arrow", ["left_command", "left_shift"]),
    nav("end", ["control", "shift"], "down_arrow", ["left_command", "left_shift"]),

    // Delete word back / forward (Ctrl+Backspace / Ctrl+Delete)
    nav("delete_or_backspace", ["control"], "delete_or_backspace", ["left_option"]),
    nav("delete_forward", ["control"], "delete_forward", ["left_option"]),
  ],
};

// ----------------------------------------------------------------------------
// Emit
// ----------------------------------------------------------------------------
const rules: Rule[] = [textNav];

const config = {
  global: { show_in_menu_bar: true },
  profiles: [
    {
      name: "Default",
      selected: true,
      virtual_hid_keyboard: { keyboard_type_v2: "ansi" },
      complex_modifications: { rules },
    },
  ],
};

const xdgConfig = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
const dir = join(xdgConfig, "karabiner");
const file = join(dir, "karabiner.json");
mkdirSync(dir, { recursive: true });
if (existsSync(file)) copyFileSync(file, `${file}.bak`); // one-shot backup
writeFileSync(file, JSON.stringify(config, null, 2) + "\n");
console.log(`Wrote ${file} (${rules.length} rules). Backup at ${file}.bak if it existed.`);
