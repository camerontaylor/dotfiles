#!/usr/bin/env bash
# capture-shortcuts.sh — dump the App Shortcuts you've set on THIS Mac so you
# can copy them into macos-defaults.sh and version them.
#
#   ./capture-shortcuts.sh
#
# It reads NSUserKeyEquivalents from the global domain plus any apps you list,
# and prints them as ready-to-paste set_app_shortcut lines where possible.
set -uo pipefail

# Apps to inspect (add your own). "global" = the All Applications shortcuts.
TARGETS=("global" "ForkLift" "Finder")

bundle_id() { osascript -e "id of app \"$1\"" 2>/dev/null; }

dump() {
  local target="$1" domain
  if [[ "$target" == "global" ]]; then domain="NSGlobalDomain"
  else domain="$(bundle_id "$target")"; [[ -z "$domain" ]] && return; fi

  # Skip if no custom shortcuts exist for this domain.
  defaults read "$domain" NSUserKeyEquivalents >/dev/null 2>&1 || return

  echo "# --- $target ($domain) ---"
  # Convert the dict to JSON and emit one line per shortcut.
  defaults export "$domain" - 2>/dev/null \
    | plutil -extract NSUserKeyEquivalents json -o - - 2>/dev/null \
    | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
t=sys.argv[1]
for title,keyeq in d.items():
    print(f"set_app_shortcut \"{t}\" \"{title}\" {chr(39)}{keyeq}{chr(39)}")
' "$target" 2>/dev/null \
    || defaults read "$domain" NSUserKeyEquivalents   # fallback: raw dump
  echo
}

echo "# Paste the relevant lines into macos-defaults.sh:"
echo
for t in "${TARGETS[@]}"; do dump "$t"; done
