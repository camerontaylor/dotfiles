#!/usr/bin/env bash
# setup-swap.sh — two-tier swap (zram + disk swapfile) on a Linux fleet box.
#
# Why this exists: Ubuntu's installer creates /swap.img on an ext4 root but
# SKIPS swap entirely when root is btrfs (swapfiles there need NOCOW + no
# compression, unsupported before kernel 5.0). makemake came up that way —
# 16 GB soldered RAM, zero swap — and has been OOM-killing things ever since
# (a single rustc peaked at 11.9 GB RSS; see mise.toml's codewhale note).
#
# The two tiers, and why both:
#   - zram (priority 100) takes the hot anonymous pages and compresses them in
#     RAM. ~2-3x on real workloads, zero SSD wear, no seek. This is where
#     virtually all swap traffic should land.
#   - a disk swapfile (priority 10) is the backstop for the case zram cannot
#     help with: one allocation genuinely larger than physical RAM. Slow, but
#     "slow" beats "the OOM killer picks postgres".
# The kernel drains the highest-priority swap first, so the file stays cold
# until zram is full. Fleet precedent for both numbers: ceres runs zram at
# priority 100, pluto runs /mnt/ssd-services/swap.img at priority 10.
#
# Linux only. Idempotent — a second run with the same sizes is a no-op.
# Needs sudo (root steps stay human-run; this is not called from deploy).
#
# Usage:
#   scripts/setup-swap.sh [--zram SIZE|off] [--file SIZE|off]
#                         [--swapfile PATH] [--dry-run]
# SIZE accepts a G or M suffix (8G, 8192M); bare numbers are MiB.
# Defaults: both tiers at half of RAM, rounded to a whole GiB, capped at 8G.
#
# To undo: sudo swapoff -a, drop the /swapfile line from /etc/fstab, rm
# /swapfile, rm /etc/systemd/zram-generator.conf /etc/sysctl.d/60-swap.conf.

set -eu

ZRAM_PRIORITY=100
FILE_PRIORITY=10
SWAPFILE=/swapfile
ZRAM_CONF=/etc/systemd/zram-generator.conf
SYSCTL_CONF=/etc/sysctl.d/60-swap.conf
DRY_RUN=0

# swappiness=100 is deliberately below ceres's 150: ceres's only swap IS zram,
# so leaning hard on it is free, whereas makemake's second tier is a SATA file
# and over-eager anon reclaim would thrash it once zram fills. page-cluster=0
# disables swap-in readahead — zram is random-access, so reading neighbours is
# pure waste (this is the one tunable every zram guide agrees on).
SWAPPINESS=100
PAGE_CLUSTER=0

if [ "$(uname -s)" != Linux ]; then
    echo "setup-swap: Linux only (macOS manages its own dynamic swap)" >&2
    exit 0
fi

# --- size parsing ------------------------------------------------------------
# Normalise 8G / 8g / 8192M / 8192 to MiB. Rejects anything else loudly rather
# than silently creating a 0-byte swapfile.
to_mib() {
    _v=$1
    case "$_v" in
        *[Gg]) echo $(( ${_v%?} * 1024 )) ;;
        *[Mm]) echo "${_v%?}" ;;
        *[!0-9]*)
            echo "setup-swap: bad size '$_v' (want 8G, 8192M or 8192)" >&2
            exit 1
            ;;
        *) echo "$_v" ;;
    esac
}

ram_mib=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
# Half of RAM, rounded to the NEAREST whole GiB (16 GB reports as ~15.4 GiB, so
# truncating would give 7G where 8G is plainly meant), then capped at 8G.
default_mib=$(( (ram_mib / 2 + 512) / 1024 * 1024 ))
if [ "$default_mib" -gt 8192 ]; then
    default_mib=8192
fi
if [ "$default_mib" -lt 1024 ]; then
    default_mib=1024
fi

zram_mib=$default_mib
file_mib=$default_mib

while [ $# -gt 0 ]; do
    case "$1" in
        --zram)     shift; if [ "${1:-}" = off ]; then zram_mib=0; else zram_mib=$(to_mib "${1:?--zram needs a size}"); fi ;;
        --file)     shift; if [ "${1:-}" = off ]; then file_mib=0; else file_mib=$(to_mib "${1:?--file needs a size}"); fi ;;
        --swapfile) shift; SWAPFILE=${1:?--swapfile needs a path} ;;
        --dry-run)  DRY_RUN=1 ;;
        -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "setup-swap: unknown argument '$1'" >&2; exit 1 ;;
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

# Write $2 to root-owned file $1 (mode $3) only if the content differs.
# Returns 1 when nothing changed, so callers can skip the reload.
install_conf() {
    _dst=$1
    _content=$2
    _mode=$3
    if [ -f "$_dst" ] && printf '%s' "$_content" | sudo cmp -s - "$_dst"; then
        echo "  $_dst already up to date"
        return 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] would write $_dst (mode $_mode)"
        return 0
    fi
    printf '%s' "$_content" | sudo tee "$_dst" > /dev/null
    sudo chmod "$_mode" "$_dst"
    echo "  wrote $_dst"
    return 0
}

echo "setup-swap on $(hostname -s): ${ram_mib} MiB RAM, zram=${zram_mib} MiB, file=${file_mib} MiB"

# --- tier 1: zram ------------------------------------------------------------
if [ "$zram_mib" -gt 0 ]; then
    echo "zram (priority $ZRAM_PRIORITY):"
    if [ ! -x /usr/lib/systemd/system-generators/zram-generator ] \
       && [ ! -x /lib/systemd/system-generators/zram-generator ]; then
        # Package name differs by distro; only ever install on a distro we know.
        distro_like=""
        if [ -r /etc/os-release ]; then
            distro_like=$(. /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}")
        fi
        case " $distro_like " in
            *" debian "*|*" ubuntu "*) run sudo apt-get install -y systemd-zram-generator ;;
            *" arch "*)                run sudo pacman -S --needed --noconfirm zram-generator ;;
            *)
                echo "  zram-generator not installed and distro '$distro_like' unknown — install it, then re-run" >&2
                zram_mib=0
                ;;
        esac
    fi
fi

if [ "$zram_mib" -gt 0 ]; then
    # zram-size is in MiB (the generator evaluates it as an expression over
    # `ram`, but a literal keeps `swapon --show` matching what we asked for).
    zram_conf_body="# Managed by dotfiles scripts/setup-swap.sh — edit there, not here.
[zram0]
compression-algorithm = zstd
zram-size = $zram_mib
swap-priority = $ZRAM_PRIORITY
fs-type = swap
"
    if install_conf "$ZRAM_CONF" "$zram_conf_body" 644; then
        run sudo systemctl daemon-reload
        # The generator materialises systemd-zram-setup@zram0.service; restart
        # picks up a size change (start alone is a no-op if already running).
        run sudo systemctl restart systemd-zram-setup@zram0.service
    fi
fi

# --- tier 2: disk swapfile ---------------------------------------------------
if [ "$file_mib" -gt 0 ]; then
    echo "swapfile $SWAPFILE (priority $FILE_PRIORITY):"
    swap_dir=$(dirname "$SWAPFILE")
    fstype=$(findmnt -no FSTYPE --target "$swap_dir")

    if [ -e "$SWAPFILE" ]; then
        have_mib=$(( $(stat -c %s "$SWAPFILE") / 1024 / 1024 ))
        echo "  exists (${have_mib} MiB) — leaving it alone"
        if [ "$have_mib" -ne "$file_mib" ]; then
            echo "  NOTE: wanted ${file_mib} MiB. To resize: sudo swapoff $SWAPFILE && sudo rm $SWAPFILE, then re-run." >&2
        fi
    else
        # Guard: never fill the filesystem to create swap.
        avail_mib=$(( $(df -P -k "$swap_dir" | awk 'NR == 2 { print $4 }') / 1024 ))
        if [ "$avail_mib" -lt $(( file_mib + 10240 )) ]; then
            echo "  only ${avail_mib} MiB free on $swap_dir — need ${file_mib} + 10G headroom; skipping" >&2
            file_mib=0
        elif [ "$fstype" = btrfs ]; then
            # btrfs swapfiles must be NOCOW, hole-free and uncompressed;
            # mkswapfile (btrfs-progs >= 6.1) does all three plus mkswap.
            # It will refuse if the subvolume is compressed or snapshotted.
            run sudo btrfs filesystem mkswapfile --size "${file_mib}m" --uuid clear "$SWAPFILE"
        else
            run sudo fallocate -l "${file_mib}M" "$SWAPFILE"
            run sudo chmod 600 "$SWAPFILE"
            run sudo mkswap "$SWAPFILE"
        fi
    fi
fi

if [ "$file_mib" -gt 0 ]; then
    # nofail: a missing/renamed swapfile must never wedge boot.
    fstab_line="$SWAPFILE none swap sw,pri=$FILE_PRIORITY,nofail 0 0"
    if grep -qs "^$SWAPFILE[[:space:]]" /etc/fstab; then
        echo "  /etc/fstab entry already present"
    elif [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] would append to /etc/fstab: $fstab_line"
    else
        printf '\n# swap tier 2 — see dotfiles scripts/setup-swap.sh\n%s\n' "$fstab_line" \
            | sudo tee -a /etc/fstab > /dev/null
        echo "  appended /etc/fstab entry"
        # fstab changed: regenerate the swap unit before swapon, or systemd
        # keeps a stale view of what is mounted.
        run sudo systemctl daemon-reload
    fi
    if ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAPFILE"; then
        run sudo swapon --priority "$FILE_PRIORITY" "$SWAPFILE"
    fi
fi

# --- tuning ------------------------------------------------------------------
sysctl_body="# Managed by dotfiles scripts/setup-swap.sh — edit there, not here.
# See the header of that script for why these two values.
vm.swappiness = $SWAPPINESS
vm.page-cluster = $PAGE_CLUSTER
"
echo "sysctl:"
if install_conf "$SYSCTL_CONF" "$sysctl_body" 644; then
    run sudo sysctl --quiet --load "$SYSCTL_CONF"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry run — nothing changed)"
else
    swapon --show
    free -h | sed -n '1p;3p'
fi
