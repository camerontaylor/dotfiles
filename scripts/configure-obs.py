#!/usr/bin/env python3
"""Seed OBS with the tracked two-track recording config (Track 1 = mic,
Track 2 = desktop/app audio via ScreenCaptureKit).

Called from scripts/deploy.d/77_obs.zsh on hosts opted in via
configs/obs/hosts.conf. NON-DESTRUCTIVE: OBS continuously writes back to its
own scene/profile files, so this never overwrites an existing "TwoTrack"
profile or scene collection -- it only seeds them when absent. That means a
symlink model (as used for read-only configs like aerospace.toml) is wrong
here; we copy templates instead.

Usage: configure-obs.py <repo-obs-dir> <obs-config-dir>
  <repo-obs-dir>    e.g. $SCRIPT_DIR/configs/obs   (tracked templates)
  <obs-config-dir>  e.g. ~/Library/Application Support/obs-studio

Honors DEPLOY_DRY_RUN=1 in the environment (prints intended actions, writes
nothing), matching the rest of the deploy flow.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

NAME = "TwoTrack"


def dry_run() -> bool:
    return os.environ.get("DEPLOY_DRY_RUN", "0") == "1"


def obs_running() -> bool:
    """True if an OBS.app process is live (so we must not touch user.ini,
    which OBS rewrites on exit)."""
    try:
        r = subprocess.run(
            ["pgrep", "-f", "/Applications/OBS.app/Contents/MacOS/OBS"],
            capture_output=True,
        )
        return r.returncode == 0
    except OSError:
        return False


def set_ini_key(text: str, section: str, key: str, value: str) -> str:
    """Set key=value inside [section], preserving all other lines. Appends the
    key to the section if missing, or creates the section at EOF if absent.
    Deliberately line-based (not configparser) to preserve OBS's exact
    formatting and avoid reordering keys OBS cares about."""
    lines = text.splitlines()
    out: list[str] = []
    in_sec = False
    done = False
    hdr = f"[{section}]"
    for ln in lines:
        stripped = ln.strip()
        is_header = stripped.startswith("[") and stripped.endswith("]")
        if is_header:
            if in_sec and not done:  # leaving target section without the key
                out.append(f"{key}={value}")
                done = True
            in_sec = stripped == hdr
            out.append(ln)
            continue
        if in_sec and re.match(rf"^{re.escape(key)}=", ln):
            out.append(f"{key}={value}")
            done = True
            in_sec = False  # ignore any later duplicate in the same section
            continue
        out.append(ln)
    if in_sec and not done:  # target section was the last one in the file
        out.append(f"{key}={value}")
        done = True
    result = "\n".join(out)
    if not done:  # section never existed
        result = result.rstrip("\n") + f"\n\n[{section}]\n{key}={value}"
    return result.rstrip("\n") + "\n"


def main(repo_dir: Path, obs_dir: Path) -> int:
    home = os.path.expanduser("~")
    scene_tmpl = repo_dir / "scenes" / f"{NAME}.json"
    prof_tmpl = repo_dir / "profiles" / NAME / "basic.ini"
    if not scene_tmpl.is_file() or not prof_tmpl.is_file():
        print(f"  ...OBS templates missing under {repo_dir}, skipping")
        return 0

    scene_dst = obs_dir / "basic" / "scenes" / f"{NAME}.json"
    prof_dst = obs_dir / "basic" / "profiles" / NAME / "basic.ini"
    user_ini = obs_dir / "user.ini"

    seeded = False

    # --- 1. scene collection (verbatim; no machine-specific paths inside) ---
    if scene_dst.exists():
        print(f"  ...scene collection '{NAME}' already present, leaving it")
    else:
        if dry_run():
            print(f"  [dry-run] would seed scene collection -> {scene_dst}")
        else:
            scene_dst.parent.mkdir(parents=True, exist_ok=True)
            scene_dst.write_text(scene_tmpl.read_text())
            print(f"  ...seeded scene collection '{NAME}'")
        seeded = True

    # --- 2. profile (substitute @HOME@ -> real home for the record path) ---
    if prof_dst.exists():
        print(f"  ...profile '{NAME}' already present, leaving it")
    else:
        ini = prof_tmpl.read_text().replace("@HOME@", home)
        if dry_run():
            print(f"  [dry-run] would seed profile -> {prof_dst}")
        else:
            prof_dst.parent.mkdir(parents=True, exist_ok=True)
            prof_dst.write_text(ini)
            print(f"  ...seeded profile '{NAME}' (records to {home}/Movies)")
        seeded = True

    if not seeded:
        return 0

    # --- 3. point OBS at TwoTrack, but only when it's safe to edit user.ini ---
    if obs_running():
        print("  ...OBS is running; open Profile + Scene Collection menus and")
        print(f"     pick '{NAME}', or quit OBS and re-run deploy to auto-select")
        return 0

    if dry_run():
        print(f"  [dry-run] would point user.ini [Basic] at '{NAME}'")
        return 0

    text = user_ini.read_text() if user_ini.exists() else "[General]\nFirstRun=false\n"
    for key, val in (
        ("Profile", NAME),
        ("ProfileDir", NAME),
        ("SceneCollection", NAME),
        ("SceneCollectionFile", f"{NAME}.json"),
    ):
        text = set_ini_key(text, "Basic", key, val)
    user_ini.write_text(text)
    print(f"  ...selected profile + scene collection '{NAME}'")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
