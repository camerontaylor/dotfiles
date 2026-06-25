# Raycast Script Commands

[Raycast Script Commands](https://github.com/raycast/script-commands) live here so
they're version-controlled and ride along to every Mac via the dotfiles. Raycast's
own Cloud Sync covers aliases, hotkeys, and extensions — but **not** custom script
files, so those belong in the repo.

## One-time wiring (per Mac)

Raycast reads script commands from directories you register; there's no config
file to symlink, so add this folder once:

1. Raycast → **Settings → Extensions → Script Commands → Add Directories**
2. Point it at this folder: `~/repos/dotfiles/raycast`
3. Each `*.sh` here shows up as a command (e.g. **Open in ForkLift**). Give it an
   alias (e.g. `fl`) or hotkey in its row.

New scripts dropped here appear automatically (Raycast rescans the directory).

## Commands

- **`open-in-forklift.sh`** — *Open in ForkLift.* Opens the frontmost Finder
  window's folder (falling back to the selected item's container, then the
  Desktop) in ForkLift. This is the practical workaround for the one thing `duti`
  can't do: reassign double-clicking a *folder* away from Finder.

## Notes

- First run prompts for **Automation** permission (Raycast controlling Finder) —
  approve it or the script can't read the Finder path.
- Scripts must be executable (`chmod +x`); they already are in the repo.
