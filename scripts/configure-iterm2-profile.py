#!/usr/bin/env python3
"""Pin iTerm2's default profile to Solarized Dark, 14pt font, and stable title.

Called from deploy.zsh's configure_iterm2_profile() function. The previous
version embedded this as a 70-line heredoc inside zsh, which was unreviewable
and unrelated to the surrounding zsh logic.

Usage: configure-iterm2-profile.py <prefs.plist> <color-presets.plist>
"""
from __future__ import annotations

import plistlib
import subprocess
import sys
from copy import deepcopy
from pathlib import Path
from tempfile import NamedTemporaryFile


def main(prefs_path: Path, preset_path: Path) -> int:
    with prefs_path.open("rb") as fh:
        prefs = plistlib.load(fh)
    with preset_path.open("rb") as fh:
        presets = plistlib.load(fh)

    preset = presets["Solarized Dark"]
    bookmarks = prefs.get("New Bookmarks") or []
    default_guid = prefs.get("Default Bookmark Guid")
    bookmark = next(
        (entry for entry in bookmarks if entry.get("Guid") == default_guid),
        None,
    )
    if bookmark is None:
        if not bookmarks:
            return 0
        bookmark = bookmarks[0]

    changed = False
    for key, value in preset.items():
        for target_key in (key, f"{key} (Dark)", f"{key} (Light)"):
            if bookmark.get(target_key) != value:
                bookmark[target_key] = deepcopy(value)
                changed = True

    font = bookmark.get("Normal Font")
    if isinstance(font, str):
        family, size_text = font.rsplit(" ", 1)
        if size_text != "14":
            bookmark["Normal Font"] = f"{family} 14"
            changed = True

    if bookmark.get("Title Components") != 1:
        bookmark["Title Components"] = 1
        changed = True

    for key in ("Allow Title Setting", "Sync Title"):
        if bookmark.get(key) is not False:
            bookmark[key] = False
            changed = True

    if changed:
        with NamedTemporaryFile("wb", delete=False, suffix=".plist") as fh:
            temp_path = Path(fh.name)
            plistlib.dump(prefs, fh, fmt=plistlib.FMT_BINARY, sort_keys=False)
        try:
            subprocess.run(
                ["defaults", "import", "com.googlecode.iterm2", str(temp_path)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        finally:
            temp_path.unlink(missing_ok=True)

    print(
        "  ...applied Solarized Dark preset, set Normal Font to 14pt, and pinned title components"
        if changed
        else "  ...already configured"
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <prefs.plist> <color-presets.plist>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
