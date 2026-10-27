#!/usr/bin/env bash
# setup-power-cap.sh — persistent Intel RAPL package power cap (PL1).
#
# Why this exists: ceres (i5-8500, OptiPlex 7060 Micro) draws 61-65 W on any
# all-core load and its fan follows. A 25 W PL1 cap is acoustically
# indistinguishable from idle and keeps ~69 % of worst-case (AVX2 matmul)
# compute at 1.8x the efficiency; 45 W keeps 88.5 % and is 10 dB(A) quieter.
# Full measurements: docs/ceres-acoustics.md ("The power cap").
#
# The cap is a sysfs write, so it resets to the firmware default at every
# boot. This installs a udev rule that re-applies it whenever the intel-rapl:0
# powercap device appears — at boot, and again if intel_rapl_msr is reloaded —
# rather than a oneshot unit that would race the module load.
#
# Linux + Intel RAPL only. Idempotent. Needs sudo (root steps stay human-run;
# this is not called from deploy).
#
# Usage:
#   scripts/setup-power-cap.sh [WATTS|off] [--dry-run]
# Default: 25 W. "off" removes the rule and restores the 65 W firmware default
# (ceres's value; read it from a fresh boot on other hardware).
#
# To undo by hand: rm /etc/udev/rules.d/71-rapl-pl1-cap.rules, reboot.

set -eu

RULE=/etc/udev/rules.d/71-rapl-pl1-cap.rules
ZONE=/sys/class/powercap/intel-rapl:0
DEFAULT_WATTS=65
WATTS=25
DRY_RUN=0

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=1 ;;
        off) WATTS=off ;;
        ''|*[!0-9]*) echo "setup-power-cap: bad argument '$arg' (want WATTS, off, --dry-run)" >&2; exit 2 ;;
        *) WATTS=$arg ;;
    esac
done

if [ "$(uname -s)" != Linux ] || [ ! -e "$ZONE/constraint_0_power_limit_uw" ]; then
    echo "setup-power-cap: no Intel RAPL package zone at $ZONE" >&2
    exit 1
fi
if [ "$(cat "$ZONE/constraint_0_name")" != long_term ]; then
    echo "setup-power-cap: constraint_0 of $ZONE is not long_term (PL1); refusing" >&2
    exit 1
fi

run() {
    if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}

if [ "$WATTS" = off ]; then
    [ -e "$RULE" ] && run sudo rm -f "$RULE"
    run sudo udevadm control --reload
    run sudo sh -c "echo $((DEFAULT_WATTS * 1000000)) > $ZONE/constraint_0_power_limit_uw"
else
    uw=$((WATTS * 1000000))
    want="# Managed by dotfiles scripts/setup-power-cap.sh — PL1 cap, see docs/ceres-acoustics.md
ACTION==\"add\", SUBSYSTEM==\"powercap\", KERNEL==\"intel-rapl:0\", ATTR{constraint_0_power_limit_uw}=\"$uw\""
    if [ -e "$RULE" ] && [ "$(cat "$RULE")" = "$want" ]; then
        echo "setup-power-cap: $RULE already at ${WATTS} W"
    elif [ "$DRY_RUN" = 1 ]; then
        echo "+ write $RULE:"; echo "$want"
    else
        printf '%s\n' "$want" | sudo tee "$RULE" >/dev/null
    fi
    run sudo udevadm control --reload
    # Replay the boot-time add event, so this run exercises the exact path a
    # reboot will take instead of a separate direct write.
    run sudo udevadm trigger --action=add "$ZONE"
    run sudo udevadm settle
fi

[ "$DRY_RUN" = 1 ] && exit 0
echo "setup-power-cap: PL1 now $(( $(cat "$ZONE/constraint_0_power_limit_uw") / 1000000 )) W"
