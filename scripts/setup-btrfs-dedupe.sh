#!/usr/bin/env bash
# setup-btrfs-dedupe.sh — monthly out-of-band btrfs dedupe via duperemove.
#
# Why this exists: btrfs shares extents on write (snapshots, `cp --reflink`),
# but nothing ever notices that two files written independently happen to hold
# the same bytes. On a dev box that is a lot of space — node_modules replicated
# across mise-installed node versions, container layers, npm caches. A first
# pass on ceres 2026-09-20 reclaimed ~16 GiB of 226 GiB (6.2M files, 301 GB).
#
# Why duperemove and not dduper: dduper reads btrfs's own csum tree instead of
# the file data, which sounds strictly better and is not. btrfs csums cover the
# ON-DISK bytes, so on a compress=zstd fleet the csums of a compressed extent
# cover the COMPRESSED bytes and dduper's offset arithmetic silently misses
# every compressed extent. Measured head to head on the same files: dduper
# 224s/1.26 GiB, duperemove 27s/2.47 GiB. dduper also ships a packing bug that
# makes FIDEDUPERANGE fail with EINVAL while reporting success.
#
# Why a persistent hashfile: it is the entire reason this can be monthly.
#   cold run (no hashfile)     46m06s   6,230,406 files   301.1 GB hashed
#   incremental (+8 min later)  3m36s      67,121 files    12.7 GB hashed
#   incremental (back to back)  2m46s       4,252 files     2.5 GB hashed
# The ~2m46s floor is stat(2) over 6.2M files plus loading the 3.1 GB hashfile;
# it never reaches zero because the box always has churn.
#
# Why the hashfile lives in /var/cache: that is subvol @cache, and snapper on
# this fleet snapshots only `/` (subvol @). btrfs snapshots are NOT recursive,
# so a nested subvolume is not captured. A 3.1 GB file under @ would otherwise
# be pinned by every one of the 51 snapshots.
#
# Dedupe is safe: FIDEDUPERANGE byte-compares the ranges in-kernel and refuses
# to share anything that differs, so it cannot corrupt data. Verified here by
# sha256 over 238 files before and after — identical. It is also snapshot-safe
# in the way defrag is not: dedupe only ever ADDS reflinks.
#
# Expect some failures and ignore them: systemd journals are NOCOW (+C) and
# btrfs refuses dedupe on NODATACOW inodes (EINVAL). 483 of those on the first
# run here, all journals.
#
# Linux only. Idempotent — a second run with no changes is a no-op.
# Needs sudo (root steps stay human-run; this is NOT called from deploy).
#
# Usage:
#   scripts/setup-btrfs-dedupe.sh [--hashfile PATH] [--adopt PATH]
#                                 [--run-now] [--uninstall] [--dry-run]

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TRACKED_SERVICE="$REPO_ROOT/configs/btrfs-dedupe/btrfs-dedupe.service"
TRACKED_TIMER="$REPO_ROOT/configs/btrfs-dedupe/btrfs-dedupe.timer"
LIVE_SERVICE=/etc/systemd/system/btrfs-dedupe.service
LIVE_TIMER=/etc/systemd/system/btrfs-dedupe.timer

HASHFILE=/var/cache/duperemove/hashfile.db
ADOPT=
RUN_NOW=0
UNINSTALL=0
DRY_RUN=0

if [ "$(uname -s)" != Linux ]; then
    echo "setup-btrfs-dedupe: Linux only (macOS has no btrfs)" >&2
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --hashfile)  shift; HASHFILE=${1:?--hashfile needs a path} ;;
        --adopt)     shift; ADOPT=${1:?--adopt needs a path} ;;
        --run-now)   RUN_NOW=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --dry-run)   DRY_RUN=1 ;;
        -h|--help)   sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "setup-btrfs-dedupe: unknown argument '$1'" >&2; exit 1 ;;
    esac
    shift
done

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# --- uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    echo "setup-btrfs-dedupe: removing timer and units"
    run sudo systemctl disable --now btrfs-dedupe.timer
    run sudo rm -f "$LIVE_TIMER" "$LIVE_SERVICE"
    run sudo systemctl daemon-reload
    echo "  units removed. Hashfile left in place: $HASHFILE"
    echo "  (delete it by hand if you want the space back)"
    exit 0
fi

# --- preflight ---------------------------------------------------------------
if ! command -v duperemove >/dev/null 2>&1; then
    echo "setup-btrfs-dedupe: duperemove not installed." >&2
    echo "  Arch/CachyOS: sudo pacman -S duperemove" >&2
    echo "  Debian/Ubuntu: sudo apt install duperemove" >&2
    exit 1
fi

if [ "$(findmnt -no FSTYPE --target / 2>/dev/null)" != btrfs ]; then
    echo "setup-btrfs-dedupe: / is not btrfs — nothing to dedupe" >&2
    exit 1
fi

for f in "$TRACKED_SERVICE" "$TRACKED_TIMER"; do
    if [ ! -f "$f" ]; then
        echo "setup-btrfs-dedupe: missing tracked unit $f" >&2
        exit 1
    fi
done

echo "setup-btrfs-dedupe: duperemove $(duperemove --version 2>&1 | head -1 | awk '{print $2}')"
echo "  hashfile: $HASHFILE"

# --- hashfile directory ------------------------------------------------------
# 0700 root: the hashfile records every path on the box, so it is not
# world-readable. Warn loudly if it is somewhere snapper will snapshot it.
hash_dir=$(dirname -- "$HASHFILE")
run sudo install -d -o root -g root -m 700 "$hash_dir"

case "$hash_dir" in
    /var/cache/*|/var/tmp/*) ;;
    *)
        echo "  WARNING: $hash_dir may sit inside a snapshotted subvolume."
        echo "           A multi-GB hashfile there gets pinned by every snapshot."
        ;;
esac

# Adopt an existing hashfile rather than paying for a cold rebuild. A cold run
# is 46 min; adopting keeps the 3 min incremental path from the very first run.
if [ -n "$ADOPT" ]; then
    if [ ! -f "$ADOPT" ]; then
        echo "setup-btrfs-dedupe: --adopt $ADOPT does not exist" >&2
        exit 1
    fi
    if [ "$ADOPT" = "$HASHFILE" ]; then
        echo "  adopt: source and destination are the same file, skipping"
    else
        echo "  adopting existing hashfile from $ADOPT ($(du -h "$ADOPT" | cut -f1))"
        run sudo cp --reflink=auto -- "$ADOPT" "$HASHFILE"
        run sudo chown root:root "$HASHFILE"
        run sudo chmod 600 "$HASHFILE"
    fi
fi

# --- install units -----------------------------------------------------------
# configs/btrfs-dedupe/*.{service,timer} are the tracked source of truth. Back
# up a live unit that has diverged so hand-edits are never silently discarded.
install_unit() {
    _tracked=$1
    _live=$2
    if [ -f "$_live" ] && ! cmp -s "$_tracked" "$_live"; then
        _bak="$_live.bak-$(date +%Y%m%d-%H%M%S)"
        echo "  NOTE: live $(basename "$_live") differs from the tracked unit"
        echo "        backup: $_bak (port wanted edits into configs/btrfs-dedupe/)"
        run sudo cp -p "$_live" "$_bak"
    fi
    run sudo install -o root -g root -m 644 "$_tracked" "$_live"
}

install_unit "$TRACKED_SERVICE" "$LIVE_SERVICE"
install_unit "$TRACKED_TIMER"   "$LIVE_TIMER"

# The tracked unit hard-codes the default hashfile path. If the operator chose
# another one, express that as a drop-in rather than editing the tracked unit.
if [ "$HASHFILE" != /var/cache/duperemove/hashfile.db ]; then
    echo "  non-default hashfile: writing drop-in override"
    _dropin=/etc/systemd/system/btrfs-dedupe.service.d
    run sudo mkdir -p "$_dropin"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] write $_dropin/hashfile.conf"
    else
        sudo tee "$_dropin/hashfile.conf" >/dev/null <<DROPIN
[Service]
ExecStart=
ExecStart=/usr/bin/duperemove -dhqr \\
    --hashfile=$HASHFILE \\
    --skip-zeroes \\
    --exclude=/.snapshots/* \\
    --exclude=$hash_dir/* \\
    /boot /etc /home /mnt /opt /root /srv /usr /var
DROPIN
    fi
fi

run sudo systemctl daemon-reload
run sudo systemctl enable --now btrfs-dedupe.timer

if [ "$RUN_NOW" -eq 1 ]; then
    echo "  starting a run now (detached; follow with: journalctl -fu btrfs-dedupe)"
    run sudo systemctl start --no-block btrfs-dedupe.service
fi

# --- report ------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
    echo
    systemctl list-timers btrfs-dedupe.timer --no-pager 2>/dev/null || true
    echo
    echo "  next run:  systemctl list-timers btrfs-dedupe.timer"
    echo "  run now:   sudo systemctl start btrfs-dedupe.service"
    echo "  watch:     journalctl -fu btrfs-dedupe"
    echo "  measure:   sudo btrfs filesystem df /   (NOT duperemove's own summary,"
    echo "             which reports bytes now shared, not bytes reclaimed)"
fi
