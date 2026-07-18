/**
 * karabiner.ts — typed, self-contained Karabiner-Elements config generator.
 *
 * Philosophy: Cmd stays the primary Mac modifier (we don't fight the OS or the
 * terminal). We fix the two things that actually hurt coming from Linux —
 * (1) Caps Lock becomes a Hyper key (Esc on tap), and (2) Home/End/word/doc
 * navigation behaves like Linux in GUI apps — and we leave terminals untouched
 * so readline/emacs nav keeps working there.
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
  shell_command?: string;
  set_variable?: { name: string; value: number };
}
interface From {
  key_code?: string;
  modifiers?: { mandatory?: Mod[]; optional?: Mod[] };
}
type Condition =
  | { type: "variable_if" | "variable_unless"; name: string; value: number }
  | { type: "frontmost_application_if" | "frontmost_application_unless"; bundle_identifiers: string[] };

interface Manipulator {
  type: "basic";
  from: From;
  to?: To[];
  to_if_alone?: To[];
  to_after_key_up?: To[];
  conditions?: Condition[];
  description?: string;
}
interface Rule { description: string; manipulators: Manipulator[] }

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
const app = (name: string): To => ({ shell_command: `open -a '${name}'` });
const raycast = (deeplink: string): To => ({ shell_command: `open '${deeplink}'` });
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

/** A Hyper-layer binding: hold Caps + <k> -> action. */
const hyper = (k: string, ...actions: To[]): Manipulator => ({
  type: "basic",
  from: { key_code: k, modifiers: { optional: ["any"] } },
  to: actions,
  conditions: [{ type: "variable_if", name: "hyper", value: 1 }],
});

// ----------------------------------------------------------------------------
// Rules
// ----------------------------------------------------------------------------

// 1) Caps Lock = Hyper (hold) / Escape (tap)
const hyperKey: Rule = {
  description: "Caps Lock → Hyper layer on hold, Escape on tap",
  manipulators: [
    {
      type: "basic",
      from: { key_code: "caps_lock", modifiers: { optional: ["any"] } },
      to: [{ set_variable: { name: "hyper", value: 1 } }],
      to_after_key_up: [{ set_variable: { name: "hyper", value: 0 } }],
      to_if_alone: [{ key_code: "escape" }],
    },
  ],
};

// 2) Linux-style text navigation in GUI apps (terminals excluded)
//    Edit/disable any block you don't want — these are deliberate, not magic.
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

// 3) Hyper launches & actions. EDIT the app names to match what you install.
//    Mnemonic letters; keep these disjoint from AeroSpace (Alt) and Raycast.
const hyperLayer: Rule = {
  description: "Hyper layer: launch apps + Raycast actions",
  manipulators: [
    hyper("t", app("Ghostty")),               // Terminal
    hyper("b", app("Google Chrome")),          // Browser  (e.g. Arc / Firefox)
    hyper("c", app("Visual Studio Code")),     // Code     (e.g. Cursor / Zed)
    hyper("f", app("Finder")),
    hyper("s", app("Slack")),
    hyper("n", app("Obsidian")),               // Notes
    hyper("m", app("Spotify")),                // Music
    hyper("g", app("ChatGPT")),                // swap for Claude / etc.

    // Raycast deeplinks (you registered it — lean on it)
    hyper("v", raycast("raycast://extensions/raycast/clipboard-history/clipboard-history")),
    hyper("e", raycast("raycast://extensions/raycast/emoji-symbols/search-emoji-symbols")),
    hyper("z", raycast("raycast://extensions/GastroGeek/folder-search/search")), // folder search (was ⌘Z — clashed with undo)

    // Optional: emit the real ⌘⌃⌥⇧ chord for apps that want a literal Hyper hotkey
    hyper("spacebar", key("spacebar", ["left_command", "left_control", "left_option", "left_shift"])),
  ],
};

// ----------------------------------------------------------------------------
// Emit
// ----------------------------------------------------------------------------
const rules: Rule[] = [hyperKey, textNav, hyperLayer];

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
