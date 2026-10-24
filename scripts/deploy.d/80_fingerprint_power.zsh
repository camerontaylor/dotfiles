# Fingerprint reader power management (Linux only). The ELAN 04f3:0c00 reader
# (elanmoc2 driver) does not resume from USB autosuspend within fprintd's
# transfer timeout, so lock-screen fingerprint unlock fails intermittently with
# "transfer timed out". A udev rule pins power/control=on for just that device.
#
# Mirrors 79_keyd.zsh: a system file under /etc/udev/rules.d/ that must be root-
# owned (udev reads it as root), so it's copied with sudo rather than symlinked.
# Source of truth: configs/udev/81-elan-fingerprint-power.rules. Idempotent.

if [[ $DOTFILES_OS != Linux ]]; then
    return 0
fi

local udev_src=$SCRIPT_DIR/configs/udev/81-elan-fingerprint-power.rules
local udev_target=/etc/udev/rules.d/81-elan-fingerprint-power.rules

# Only relevant if this machine actually has the ELAN 0c00 reader. Skip silently
# elsewhere so the rule isn't installed on boxes that don't need it.
if ! grep -qi '04f3:0c00' <(lsusb 2>/dev/null); then
    return 0
fi

# Install the rule if it differs from what's tracked.
if sudo cmp -s "$udev_src" "$udev_target" 2>/dev/null; then
    print "fingerprint udev rule up to date; skipping"
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] would: sudo install -Dm644 ${(D)udev_src} $udev_target (backing up any existing)"
    print "  [dry-run] would: sudo udevadm control --reload && sudo udevadm trigger --action=add /sys/bus/usb/devices/1-7"
    return 0
fi

print "Installing fingerprint power udev rule to $udev_target..."
if [[ -e $udev_target ]]; then
    sudo cp -p "$udev_target" "$udev_target.bak" 2>/dev/null || true
fi
if sudo install -Dm644 "$udev_src" "$udev_target"; then
    # Reload rules and re-fire 'add' for the reader so it takes effect without a
    # reboot/replug. --action=add re-evaluates ACTION=="add" rules against the
    # live device, applying power/control=on immediately.
    sudo udevadm control --reload > /dev/null 2>&1 || true
    local elan_path
    elan_path=$(for d in /sys/bus/usb/devices/*/; do
        [[ "$(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null)" == 04f3:0c00 ]] && print -r -- "$d" && break
    done)
    if [[ -n $elan_path ]]; then
        sudo udevadm trigger --action=add "$elan_path" > /dev/null 2>&1 || true
    fi
    print "  ...installed and applied (verify: cat ${elan_path:-/sys/.../}power/control -> 'on')"
else
    print "  ...failed to install fingerprint udev rule (see output above)"
fi
