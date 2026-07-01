# Default a UTF-8 locale when none is inherited.
#
# GUI terminals set LANG from the OS (macOS system prefs, Linux login manager),
# but `ssh host`, cron, and launchd/systemd jobs land with LANG unset. An unset
# locale means LC_CTYPE=C, under which the shell treats output as single-byte
# and byte-mangles multibyte UTF-8 — which is what breaks powerline glyphs and
# prompt separators over ssh (e.g. on the headless fleet macs like saturn).
#
# Only fill when unset (never override an inherited locale), and only to a
# UTF-8 locale the box actually provides, so Linux fleet members that lack
# en_AU fall back cleanly instead of emitting `setlocale: cannot change`
# warnings. BSD-clean: locale/grep flags here exist on both macOS and Linux.
if [[ -z ${LANG:-} ]]; then
    _avail=$(locale -a 2>/dev/null)
    for _cand in en_AU en_US C; do
        # Match both macOS (en_AU.UTF-8) and glibc (en_AU.utf8) spellings.
        if grep -qiE "^${_cand}\.utf-?8$" <<< "$_avail"; then
            export LANG=${_cand}.UTF-8
            break
        fi
    done
    unset _avail _cand
fi
