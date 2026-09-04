# macOS settings

Reproducible macOS keyboard shortcuts and Finder prefs that macOS does **not**
sync on its own. Lives in the dotfiles so every Mac gets the same behaviour.

## Files

- **`macos-defaults.sh`** — apply the settings: App Shortcuts, Finder/navigation
  prefs, and default-app associations (open text/code in VS Code, via `duti`).
  Idempotent and change-aware: each value is written only when it differs, and
  Finder is relaunched only when something actually changed. Honors `DRY_RUN=1`.
  **Drift-correcting:** if you change one of these by hand it gets put back on the
  next run — but the old value is saved to a rollback file first (see below).
- **`capture-shortcuts.sh`** — read App Shortcuts you've set by hand on the
  current Mac, printed as ready-to-paste `set_app_shortcut` lines for
  `macos-defaults.sh`.

## Rollback

Before overwriting any differing value, the old value is appended to a
timestamped, **non-tracked** restore script under
`${XDG_STATE_HOME:-~/.local/state}/macos-defaults/backup-<timestamp>.sh`
(outside the repo, so it's never committed; created only when something actually
changes, never in dry-run). To undo a run, execute that file — then `killall
Finder` if it reverted a Finder pref. Both the per-extension and the broad
UTI-family associations are recorded. `duti` can only *query* by extension
(`-x`), never by UTI, so the UTI side reads the LaunchServices preference store
directly to decide whether a write is needed.

## Use

```sh
./macos-defaults.sh             # apply on a new (or current) machine
DRY_RUN=1 ./macos-defaults.sh   # show what would change, touch nothing
./capture-shortcuts.sh          # snapshot what's currently configured
```

On macOS, `macos-defaults.sh` also runs automatically during deploy via
[`scripts/deploy.d/77_macos_defaults.zsh`](../deploy.d/77_macos_defaults.zsh)
(and respects `./deploy.zsh --dry-run`). Because it's change-aware, re-running on
every `git pull` is a quiet no-op once your settings are in place.

## What these cover vs. what syncs itself

| Mechanism | Covers |
|-----------|--------|
| **These scripts** | App Shortcuts (e.g. ForkLift "Show Invisible Files" = ⌘⇧.), Finder/navigation prefs, and default-app associations (`duti`) — macOS does **not** sync these |
| iCloud (automatic) | Text Replacements, Keychain, Safari |
| Raycast Cloud Sync (automatic) | Raycast aliases, hotkeys, extensions |

So for Raycast/Text Replacements you don't need anything here — just enable the
relevant sync. Raycast *script commands* are the exception (Cloud Sync doesn't
carry the script files); those live in [`raycast/`](../../raycast/README.md).

## App Shortcut modifier encoding (`NSUserKeyEquivalents`)

`@` = ⌘ Command · `~` = ⌥ Option · `^` = ⌃ Control · `$` = ⇧ Shift

The last character is the key. Example: ⌘⇧. → `@$.`

## Notes

- Shortcut changes register after a logout/login or app restart (Finder prefs
  apply immediately on relaunch).
- `set_app_shortcut` resolves bundle IDs by app name, so it skips cleanly on a
  Mac where an app isn't installed.
- The ForkLift menu title (`Show Invisible Files`) must match its View menu
  exactly — fix it in `macos-defaults.sh` if your version differs.
- Default-app associations need [`duti`](https://github.com/moretension/duti)
  (`brew install duti`; `75_brew_setup.zsh` installs it). The script skips that
  section cleanly if `duti` or VS Code is missing. Verify a binding with
  `duti -x md`; trim the extension list in the script to taste.
- **If you add a file type, check it converges**: apply once, then re-run with
  `DRY_RUN=1` and confirm it reports nothing. macOS silently refuses some
  bindings, and a refused one is retried on every `git pull` (each retry
  relaunching Finder). Three known-unbindable cases are documented in the
  script and deliberately excluded:
  - `.html` — Chrome owns `public.html` as default browser, and VS Code
    declares html as `CFBundleTypeRole=Editor` only, so a `role all` bind
    fails. Bind `public.html editor` if you want it, and leave double-click
    to Chrome.
  - `.conf`, `.env`, `.vim` — no installed app declares them, so macOS
    synthesises a *dynamic* UTI (`dyn.…`) and rejects the bind with error -50.
  - `public.python-script` — VS Code ships no `UTImportedTypeDeclarations`
    (it claims extensions only), and LaunchServices won't record a handler for
    a UTI the app never claims. `duti -s` still exits 0. `.py` is what binds.
- `duti` can't reassign double-clicking a **folder** away from Finder (macOS
  special-cases `public.folder`). Use the Raycast **Open in ForkLift** command in
  [`raycast/`](../../raycast/README.md) for that.
- Everything is reversible: run the rollback file, or flip the booleans / delete
  the `NSUserKeyEquivalents` keys by hand.
