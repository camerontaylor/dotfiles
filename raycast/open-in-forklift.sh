#!/usr/bin/env bash

# Raycast Script Command — open the current Finder location in ForkLift.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open in ForkLift
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🚜
# @raycast.packageName ForkLift
# @raycast.description Open the frontmost Finder folder (or the selected item's folder) in ForkLift.

# Ask Finder where we are: the front window's folder, else the selected item's
# container, else the Desktop as a last resort.
dir="$(osascript <<'APPLESCRIPT'
tell application "Finder"
  if (count of Finder windows) > 0 then
    try
      return POSIX path of (target of front Finder window as alias)
    end try
  end if
  try
    set sel to selection
    if sel is not {} then
      return POSIX path of ((container of (item 1 of sel)) as alias)
    end if
  end try
  return POSIX path of (desktop as alias)
end tell
APPLESCRIPT
)"

if [[ -z "$dir" ]]; then
  echo "Couldn't determine a folder"
  exit 1
fi

open -a "ForkLift" "$dir"
echo "ForkLift → $dir"
