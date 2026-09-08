#!/usr/bin/env bash
# btrfs-compress-backfill.sh — rewrite existing data through the compressor.
#
# Adding `compress=` to a btrfs mount only affects NEW writes; everything
# already on disk stays as it was written. This walks the filesystem and
# defragments each file with compression forced on, which rewrites it
# compressed. One-off per filesystem — after this, the mount option carries it.
#
# Deliberate scoping, because a naive `btrfs fi defragment -r /` is a trap:
#   - `-r /` descends into OTHER mounted filesystems (on makemake that means
#     the 1.1T external drives). We use `find -xdev` to stay on one device.
#   - Already-compressed media (photos, video) gets rewritten for no gain —
#     pure SSD wear. Pass --exclude for those trees.
#   - Defrag with -c on a NOCOW file silently compresses a file somebody
#     deliberately marked nodatacow. Those are skipped, which also covers an
#     active swapfile (btrfs swapfiles are always NOCOW).
#   - Defrag BREAKS REF-LINKS (snapshots, `cp --reflink`), so space usage can
#     jump. --min-free aborts before filling the disk.
#
# Long-running (hours for a few hundred GB). Meant to be launched detached:
#   sudo systemd-run --unit=btrfs-backfill --nice=19 \
#       --property=IOSchedulingClass=idle --property=TimeoutStartSec=infinity \
#       /path/to/btrfs-compress-backfill.sh --target / --exclude /some/media
#   journalctl -fu btrfs-backfill        # follow
#   systemctl stop btrfs-backfill        # safe to stop; it is per-file
#
# Safe to interrupt and re-run: defrag is idempotent per file, and a file
# already stored compressed is left alone by the kernel.
#
# Usage: btrfs-compress-backfill.sh [--target PATH] [--exclude PATH]...
#                                   [--algo zstd|lzo|zlib] [--min-free GB]
#                                   [--batch N] [--dry-run]

set -eu

TARGET=/
ALGO=zstd
MIN_FREE_GB=40
BATCH=500
DRY_RUN=0

exclude_file=$(mktemp)
list_raw=$(mktemp)
list=$(mktemp)
nocow=$(mktemp)
batch_file=$(mktemp)
cleanup() {
    rm -f "$exclude_file" "$list_raw" "$list" "$nocow" "$batch_file"
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
    case "$1" in
        --target)   shift; TARGET=${1:?--target needs a path} ;;
        --exclude)  shift; printf '%s\n' "${1:?--exclude needs a path}" >> "$exclude_file" ;;
        --algo)     shift; ALGO=${1:?--algo needs a name} ;;
        --min-free) shift; MIN_FREE_GB=${1:?--min-free needs a number} ;;
        --batch)    shift; BATCH=${1:?--batch needs a number} ;;
        --dry-run)  DRY_RUN=1 ;;
        -h|--help)  sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "btrfs-compress-backfill: unknown argument '$1'" >&2; exit 1 ;;
    esac
    shift
done

if [ "$(uname -s)" != Linux ]; then
    echo "btrfs-compress-backfill: Linux only" >&2
    exit 1
fi
if [ "$(findmnt -no FSTYPE --target "$TARGET")" != btrfs ]; then
    echo "btrfs-compress-backfill: $TARGET is not on a btrfs filesystem" >&2
    exit 1
fi

avail_gb() {
    echo $(( $(df -P -k "$TARGET" | awk 'NR == 2 { print $4 }') / 1024 / 1024 ))
}

echo "== btrfs compress backfill =="
echo "target:   $TARGET  (mounted: $(findmnt -no OPTIONS --target "$TARGET"))"
echo "algo:     $ALGO"
echo "min-free: ${MIN_FREE_GB}G (currently $(avail_gb)G)"

# --- build the work list -----------------------------------------------------
# Prune excluded trees inside find itself rather than filtering afterwards, so
# we never even stat a 49G media library. $@ is the accumulator: it behaves
# identically in bash and zsh, unlike a named array.
set -- "$TARGET" -xdev
while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    echo "exclude:  $ex"
    set -- "$@" -path "$ex" -prune -o
done < "$exclude_file"
set -- "$@" -type f -print0

echo "scanning..."
find "$@" > "$list_raw" 2>/dev/null || true
total_raw=$(tr -dc '\0' < "$list_raw" | wc -c | tr -d ' ')

# NOCOW files must not be compressed. lsattr in bulk (one exec per batch of
# paths) rather than per file; the C flag is column 1.
echo "checking $total_raw files for the NOCOW flag..."
xargs -0 -r lsattr -- < "$list_raw" 2>/dev/null \
    | awk '$1 ~ /C/ { sub(/^[^ ]+[ \t]+/, ""); print }' > "$nocow" || true
nocow_n=$(wc -l < "$nocow" | tr -d ' ')

if [ "$nocow_n" -gt 0 ]; then
    echo "skipping $nocow_n NOCOW file(s):"
    sed 's/^/    /' "$nocow" | head -10
    # -z: NUL-delimited input/output. The pattern file stays newline-delimited,
    # so a path containing a newline would slip through — acceptable, and the
    # kernel refuses an active swapfile anyway.
    grep -zvxFf "$nocow" "$list_raw" > "$list" || true
else
    cp "$list_raw" "$list"
fi
total=$(tr -dc '\0' < "$list" | wc -c | tr -d ' ')
echo "work list: $total files"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry run — nothing rewritten)"
    exit 0
fi

# --- defragment in batches ---------------------------------------------------
# Batched so the free-space guard gets a chance to fire between chunks: defrag
# breaks ref-links, so usage can only go UP while this runs.
done_n=0
batch_n=0
started=$(date +%s)

flush_batch() {
    [ "$batch_n" -gt 0 ] || return 0
    free_gb=$(avail_gb)
    if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
        echo "ABORT: only ${free_gb}G free, below the ${MIN_FREE_GB}G floor (ref-link breakage?)" >&2
        exit 1
    fi
    # --step bounds dirty pages inside a large file; without it a multi-GB file
    # can pin most of RAM before writeback on a 16G box.
    xargs -0 -r btrfs filesystem defragment -c"$ALGO" -t 32M --step 1G -- \
        < "$batch_file" > /dev/null 2>&1 || true
    done_n=$((done_n + batch_n))
    : > "$batch_file"
    batch_n=0
    elapsed=$(( $(date +%s) - started ))
    echo "  $done_n/$total files  ${free_gb}G free  ${elapsed}s elapsed"
}

while IFS= read -r -d '' f; do
    printf '%s\0' "$f" >> "$batch_file"
    batch_n=$((batch_n + 1))
    if [ "$batch_n" -ge "$BATCH" ]; then
        flush_batch
    fi
done < "$list"
flush_batch

sync
echo "== done: $done_n files in $(( $(date +%s) - started ))s, $(avail_gb)G free =="
if command -v compsize > /dev/null 2>&1; then
    compsize "$TARGET" 2>/dev/null || true
else
    echo "(install compsize to see the achieved ratio — du/df cannot show it)"
fi
