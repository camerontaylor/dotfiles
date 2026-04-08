#!/usr/bin/env bash
# kill-tsserver.sh -- SessionEnd hook to clean up orphaned tsserver processes
#
# Strategy:
#   Primary: Find typescript-language-server processes that are descendants of
#            a 'claude' process within the current session's process tree.
#   Fallback: Find tsserver.js processes with PPID=1 (reparented to init) that
#             share the same cgroup as the exiting session.
#
# Runs silently -- all output suppressed to avoid leaking to the user.
# Safe: only kills processes that are descendants of this session's claude PID.

exec >/dev/null 2>&1

# Collect all PIDs in the process tree rooted at a given PID (depth-first)
collect_descendants() {
    local root="$1"
    local -a children
    while IFS= read -r child; do
        children+=("$child")
    done < <(awk -v ppid="$root" '$4 == ppid {print $1}' /proc/[0-9]*/stat 2>/dev/null | sort -n)
    for child in "${children[@]}"; do
        echo "$child"
        collect_descendants "$child"
    done
}

# Walk ancestor chain of PID, return 0 if any ancestor comm matches pattern
has_ancestor_matching() {
    local pid="$1"
    local pattern="$2"
    local p
    p=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null) || return 1
    local depth=0
    while [ "$p" -gt 1 ] && [ $depth -lt 15 ]; do
        local comm
        comm=$(cat "/proc/$p/comm" 2>/dev/null) || break
        if [[ "$comm" == *"$pattern"* ]]; then
            return 0
        fi
        p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null) || break
        depth=$((depth + 1))
    done
    return 1
}

# Find all typescript-language-server PIDs via cmdline (comm truncates at 15 chars)
tls_pids=()
for pid_dir in /proc/[0-9]*/; do
    pid="${pid_dir%/}"
    pid="${pid##*/}"
    cmdline=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null) || continue
    if [[ "$cmdline" == *"typescript-language-server"* ]]; then
        tls_pids+=("$pid")
    fi
done

# Primary strategy: kill typescript-language-server processes whose ancestor
# chain includes a 'claude' process (indicating they belong to a Claude session)
to_kill=()
for pid in "${tls_pids[@]}"; do
    if has_ancestor_matching "$pid" "claude"; then
        to_kill+=("$pid")
        # Also collect all descendants (the tsserver.js children)
        while IFS= read -r desc; do
            to_kill+=("$desc")
        done < <(collect_descendants "$pid")
    fi
done

# Kill collected PIDs with SIGTERM first
for pid in "${to_kill[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
done

# Give processes a moment to terminate gracefully, then force-kill stragglers
if [ ${#to_kill[@]} -gt 0 ]; then
    sleep 1
    for pid in "${to_kill[@]}"; do
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    done
fi

# Fallback: find orphaned tsserver.js processes (PPID=1) sharing our cgroup
my_cgroup=$(cat /proc/self/cgroup 2>/dev/null | head -1 | cut -d: -f3)
for pid_dir in /proc/[0-9]*/; do
    pid="${pid_dir%/}"
    pid="${pid##*/}"
    cmdline=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null) || continue
    if [[ "$cmdline" != *"tsserver.js"* ]]; then
        continue
    fi
    ppid=$(awk '/^PPid:/{print $2}' "$pid_dir/status" 2>/dev/null) || continue
    # Only target orphaned processes (reparented to init)
    if [ "$ppid" -ne 1 ]; then
        continue
    fi
    # Validate by cgroup match (same systemd scope = same session)
    if [ -n "$my_cgroup" ]; then
        their_cgroup=$(cat "${pid_dir}cgroup" 2>/dev/null | head -1 | cut -d: -f3)
        if [ "$their_cgroup" != "$my_cgroup" ]; then
            continue
        fi
    fi
    kill -TERM "$pid" 2>/dev/null || true
done

exit 0
