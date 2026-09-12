#!/bin/sh
# macOS permission gate — declares the launchd/TCC capabilities this host is
# EXPECTED to have and probes what it ACTUALLY has, reporting drift in both
# directions.
#
# WHY a behavioural probe rather than reading the TCC databases: those are
# themselves Full-Disk-Access protected, so any script able to introspect
# them already holds the permission it set out to check. The probe measures
# CAPABILITY — spawn a real transient LaunchAgent, have it attempt the real
# operation, read its exit code — which needs no privilege, survives Apple
# changing TCC internals, and catches non-TCC regressions that present
# identically (an unreadable ssh Include looks exactly like a revoked grant).
#
# WHY expect= and not just pass/fail: the point of this gate is to replace
# recollection of what was clicked in System Settings with a declaration.
# So an UNEXPECTED GRANT is reported too — that is someone having clicked
# something (or an OS update having widened a default), and it is exactly
# as much drift as a revocation.
#
# Every probe logs to an INTERNAL path. Load-bearing, not taste: a
# StandardOutPath on the external volume kills the job in xpcproxy BEFORE
# exec (exit 78, empty log), so a probe logging to the volume could never
# report its own failure. Same reason launchd_log_dir() exists in
# scripts/deploy.d/lib/helpers.zsh.
#
# The first row is a deliberate CONTROL: internal-only, must pass. If it
# fails the harness is broken and every other verdict is noise.
#
# Measured on neptune 2026-09-11 — FOUR distinct launchd failure shapes, which
# is why the rows below probe interpreters separately AND detect hangs:
#   * non-shell binary reading the volume  -> exit 1, "Operation not permitted"
#   * bad StandardOutPath on the volume    -> exit 78, killed before exec, no log
#   * direct exec of a volume-resident binary -> hangs in exec, live pid, no log
#   * a denied-but-PROMPTABLE access       -> open(2) BLOCKS FOREVER, live pid
#
# That last one is the dangerous one and the reason this gate has a timeout.
# Under launchd there is no UI, so anything that would raise a user prompt
# does not fail — it hangs. Confirmed twice, by sampling the stuck process:
#   * `/usr/local/bin/bash -c "cat <volume file>"` -> the cat blocks in __open
#   * `/bin/zsh -c ...` -> blocks in run_init_scripts on a `gh auth token`
#     child, which is waiting on a keychain prompt that can never be shown
# A hung agent holds a pid, never retries, never logs, and no `launchctl list`
# glance reveals it. Prefer Apple-signed /bin/bash and /bin/zsh (which hold
# grants and so never prompt), and let nothing promptable run under launchd.
# Shells (/bin/bash, /bin/zsh, brew bash) are granted and read the volume
# fine. That asymmetry is the architectural rule: launchd's ProgramArguments[0]
# should always be an INTERNAL shell, never a bare binary and never a path
# that resolves onto the external volume.
#
# POSIX sh per the house rule for scripts/ (dual-shell, bash 3.2 floor): no
# arrays, no `declare -A`, rows are pipe-delimited strings read from a temp
# file so the `while` body keeps its counters (a pipeline would lose them to
# a subshell — same pattern as shell-syntax-gate.sh). argv words are split on
# newlines via tr, never by unquoted word splitting: zsh does not split
# unquoted expansions and bash does, so relying on it silently builds a
# one-element ProgramArguments under zsh (CLAUDE.md foot-gun #1 — this
# script's first draft hit it, and every probe died at exit 78).

set -eu

OFFLOAD_VOL=${OFFLOAD_VOL:-/Volumes/offload}
HOSTSHORT=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo unknown)
OFFLOAD_ROOT=${OFFLOAD_ROOT:-$OFFLOAD_VOL/$HOSTSHORT}
PROBE_PREFIX=com.ctaylor.permprobe
LOGDIR=$HOME/Library/Logs/dotfiles/permission-gate
CANARY=$OFFLOAD_ROOT/.permission-gate-canary
UID_NUM=$(id -u)
TMPROWS=${TMPDIR:-/tmp}/permgate.$$
VERBOSE=0

case ${1:-} in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
        printf '%s\n' "usage: $0 [-v]"
        printf '%s\n' "  Probes the macOS launchd/TCC capabilities declared in this script."
        printf '%s\n' "  Exit 1 if any declared expectation is violated in either direction."
        exit 0
        ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' "macos-permissions-gate: not Darwin — skipping"
    exit 0
fi

cleanup() {
    launchctl list 2>/dev/null | awk -v p="$PROBE_PREFIX" '$3 ~ p {print $3}' > "$TMPROWS.stale" 2>/dev/null || true
    if [ -f "$TMPROWS.stale" ]; then
        while IFS= read -r lbl; do
            [ -n "$lbl" ] && launchctl bootout "gui/$UID_NUM/$lbl" 2>/dev/null || true
        done < "$TMPROWS.stale"
    fi
    rm -f "$TMPROWS" "$TMPROWS.stale" "$CANARY" 2>/dev/null || true
    rm -f "${TMPDIR:-/tmp}/$PROBE_PREFIX".*.plist 2>/dev/null || true
    rm -rf "$LOGDIR" 2>/dev/null || true
}
trap cleanup 0 2 15

# ---------------------------------------------------------------------------
# THE MANIFEST.  id | mode | expect | marker | payload | summary
#
#   marker  string that must appear in the probe's STDOUT for the
#           capability to count as granted. The verdict is read from the
#           log file, NOT from `launchctl print`: a fast job is reaped
#           before the first poll, which reported healthy probes as
#           "never started". The log outlives the job; job state does not.
#   mode    logint  control: /bin/echo, internal log
#           shell   <interpreter> -c <cmd>, internal log   (probes the shell's grant)
#           direct  exec payload as argv (tr ' ' '\n'), internal log
#           logext  /bin/echo with StandardOutPath ON THE VOLUME
#   expect  grant   capability must be present  -> absence is a FAIL
#           deny    capability must be absent   -> presence is DRIFT (someone clicked)
#
# Adding a capability = adding a row here and a remedy() case. Nothing else.
# ---------------------------------------------------------------------------
manifest() {
    cat <<'ROWS'
harness-control|logint|grant|PROBE-OK|-|CONTROL: launchd job with an internal log runs at all
shell-bash-reads-volume|shell|grant|CANARY-OK|/bin/bash cat __CANARY__|launchd /bin/bash can READ the external volume
shell-zsh-reads-volume|shell|grant|CANARY-OK|/bin/zsh cat __CANARY__|launchd /bin/zsh can READ the external volume
shell-brewbash-reads-volume|shell|grant|CANARY-OK|/usr/local/bin/bash cat __CANARY__|launchd brew bash can READ the external volume (granted, but fragile — see remedy)
nonshell-reads-volume|direct|deny|CANARY-OK|/bin/cat __CANARY__|launchd non-shell binary can READ the external volume
direct-exec-from-volume|direct|deny|mise|__OFFLOAD_ROOT__/.local/bin/mise --version|launchd can EXEC a binary living on the volume
ssh-direct-config-parse|direct|grant|hostname|/usr/bin/ssh -G localhost|launchd-exec'd ssh can parse ~/.ssh/config
log-path-on-volume|logext|deny|PROBE-OK|-|launchd can write a LOG onto the external volume
ROWS
}

remedy() {
    case $1 in
        harness-control)
            printf '%s\n' "The probe harness itself failed — launchctl bootstrap or ~/Library/Logs is broken."
            printf '%s\n' "Every other verdict is unreliable until this passes." ;;
        shell-brewbash-reads-volume)
            printf '%s\n' "Brew bash currently holds a grant, but it is the fragile one: TCC keys"
            printf '%s\n' "grants by code-signing hash, so the next \`brew upgrade bash\` silently"
            printf '%s\n' "revokes it — and a revoked grant here presents as a HANG, not an error"
            printf '%s\n' "(see the prompt-hang note in the header), so the agent will simply stop"
            printf '%s\n' "with a live pid and no log. Prefer Apple-signed /bin/bash or /bin/zsh in"
            printf '%s\n' "ProgramArguments. Currently affected: com.ctaylor.dotfiles.prune-tmpdir"
            printf '%s\n' "(/usr/local/bin/zsh) and com.webfront.reap (/usr/local/bin/bash)." ;;
        shell-*-reads-volume)
            printf '%s\n' "If the verdict was HUNG this is NOT a permission problem: the interpreter"
            printf '%s\n' "blocked in its startup files. Known cause — zsh/env.d/08_mise.zsh shells"
            printf '%s\n' "out to \`gh auth token\` to populate GITHUB_TOKEN; under launchd that blocks"
            printf '%s\n' "forever on a keychain it cannot prompt for. The existing guard catches a"
            printf '%s\n' "FAILING gh, not a HANGING one. Fix: bound it, e.g."
            printf '%s\n' "    if _gh_token=\$(GH_PROMPT_DISABLED=1 gh auth token 2>/dev/null); then"
            printf '%s\n' "with a timeout, or skip the lookup entirely in non-interactive shells."
            printf '%s\n' ""
            printf '%s\n' "If the verdict was REGRESSED, a TCC grant was revoked."
            printf '%s\n' "Grants are keyed by path AND code-signing hash, so this is the expected"
            printf '%s\n' "symptom after upgrading a brew-installed shell. Re-grant:"
            printf '%s\n' "    System Settings -> Privacy & Security -> Full Disk Access -> +"
            printf '%s\n' "    (authenticate, then Cmd-Shift-G to type a hidden path), toggle ON"
            printf '%s\n' "Prefer Apple-shipped /bin/bash and /bin/zsh in ProgramArguments: they are"
            printf '%s\n' "platform binaries, so their grants survive OS and brew upgrades."
            printf '%s\n' "Re-bootstrap affected agents afterwards — TCC is evaluated at exec." ;;
        direct-exec-from-volume)
            printf '%s\n' "Expected to be denied: launchd cannot exec a program that lives on the"
            printf '%s\n' "external volume — it hangs in exec with a live pid and never logs."
            printf '%s\n' "This is the standing constraint on the .local row in docs/offload-home.md:"
            printf '%s\n' "ProgramArguments[0] must always resolve to an INTERNAL path." ;;
        nonshell-reads-volume)
            printf '%s\n' "UNEXPECTED GRANT: this was denied when the manifest was written."
            printf '%s\n' "Someone granted Full Disk Access to that binary, or an OS update widened"
            printf '%s\n' "a default. Neither is wrong — but update the expect= field so the"
            printf '%s\n' "declaration matches reality, or revoke the grant." ;;
        ssh-direct-config-parse)
            printf '%s\n' "launchd-exec'd ssh can no longer parse ~/.ssh/config. The usual cause is"
            printf '%s\n' "an Include naming a literal path that launchd cannot read — ssh treats"
            printf '%s\n' "that as FATAL and exits 255 before dialing, whereas a glob matching"
            printf '%s\n' "nothing is tolerated. ssh/config line 1 deliberately globs"
            printf '%s\n' "~/.colima/ssh_config* for this reason; check whether a new literal"
            printf '%s\n' "Include of a path on the external volume has been added since." ;;
        log-path-on-volume)
            printf '%s\n' "UNEXPECTED GRANT: launchd wrote a log onto the volume."
            printf '%s\n' "Harmless, but launchd_log_dir() routes dotfiles-owned agent logs to"
            printf '%s\n' "~/Library/Logs/dotfiles precisely so nothing depends on this. Leave it." ;;
    esac
}

# Write a probe plist. $1 label $2 mode $3 payload $4 outlog $5 errlog -> path
write_plist() {
    pl_label=$1; pl_mode=$2; pl_payload=$3; pl_out=$4; pl_err=$5
    pl_file=${TMPDIR:-/tmp}/$pl_label.plist
    {
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
        printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        printf '%s\n' '<plist version="1.0"><dict>'
        printf '  <key>Label</key><string>%s</string>\n' "$pl_label"
        printf '%s\n' '  <key>ProgramArguments</key><array>'
        case $pl_mode in
            shell)
                # payload = "<interpreter> <command...>"; first word is argv[0],
                # the rest becomes a single -c string.
                pl_interp=$(printf '%s' "$pl_payload" | cut -d' ' -f1)
                pl_cmd=$(printf '%s' "$pl_payload" | cut -d' ' -f2-)
                printf '    <string>%s</string>\n' "$pl_interp"
                printf '%s\n' '    <string>-c</string>'
                # XML-escape. & FIRST, or it double-escapes the entities the
                # later substitutions introduce — the bug that leaves a raw &&
                # in com.ctaylor.dotfiles.pull.plist (99_periodic.zsh).
                printf '    <string>%s</string>\n' "$(printf '%s' "$pl_cmd" \
                    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
                ;;
            direct)
                # tr, never unquoted word splitting (see header note).
                printf '%s' "$pl_payload" | tr ' ' '\n' > "$pl_file.argv"
                # `|| [ -n "$pl_w" ]`: read returns false on a final line
                # with no trailing newline, silently dropping the last argv
                # word. That turned `/bin/cat FILE` into bare `/bin/cat`,
                # which read stdin, hit EOF and exited 0 — a probe that
                # reported "granted" while testing nothing at all.
                while IFS= read -r pl_w || [ -n "$pl_w" ]; do
                    [ -n "$pl_w" ] && printf '    <string>%s</string>\n' "$pl_w"
                done < "$pl_file.argv"
                rm -f "$pl_file.argv"
                ;;
            *)
                printf '%s\n' '    <string>/bin/echo</string><string>PROBE-OK</string>'
                ;;
        esac
        printf '%s\n' '  </array>'
        printf '  <key>StandardOutPath</key><string>%s</string>\n' "$pl_out"
        printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$pl_err"
        printf '%s\n' '  <key>RunAtLoad</key><true/>'
        printf '%s\n' '</dict></plist>'
    } > "$pl_file"
    printf '%s' "$pl_file"
}

# Run a probe -> "<verdict>|<detail>", verdict grant|deny.
# $1 label $2 mode $3 marker $4 payload
#
# The verdict comes from the probe's STDOUT LOG, never from `launchctl print`.
# A probe that does its job exits in milliseconds and launchd reaps it, so
# polling job state raced and reported healthy probes as "never started".
# The log file outlives the job, so presence of the marker is a stable signal
# and its absence after the timeout is a real denial.
run_probe() {
    rp_label=$1; rp_mode=$2; rp_marker=$3; rp_payload=$4
    rp_out=$LOGDIR/$rp_label.out
    rp_err=$LOGDIR/$rp_label.err
    : > "$rp_out"; : > "$rp_err"
    case $rp_mode in
        logext) rp_out=$OFFLOAD_ROOT/$rp_label.out; rm -f "$rp_out" 2>/dev/null || true ;;
    esac
    rp_file=$(write_plist "$rp_label" "$rp_mode" "$rp_payload" "$rp_out" "$rp_err")
    launchctl bootout "gui/$UID_NUM/$rp_label" 2>/dev/null || true
    if ! launchctl bootstrap "gui/$UID_NUM" "$rp_file" 2>/dev/null; then
        rm -f "$rp_file"
        printf '%s' "deny|launchctl refused to bootstrap the probe"
        return 0
    fi
    rp_hit=0; rp_i=0
    while [ "$rp_i" -lt 40 ]; do
        if [ -s "$rp_out" ] && grep -q "$rp_marker" "$rp_out" 2>/dev/null; then
            rp_hit=1
            break
        fi
        [ -s "$rp_err" ] && break
        rp_i=$((rp_i + 1))
        sleep 0.25
    done
    rp_msg=$(head -1 "$rp_err" 2>/dev/null | tr -d '\r' || true)
    rp_state=$(launchctl print "gui/$UID_NUM/$rp_label" 2>/dev/null || true)
    rp_code=$(printf '%s\n' "$rp_state" \
        | sed -n 's/.*last exit code = \([0-9][0-9]*\).*/\1/p' | head -1)
    # A live pid after the timeout is a HANG, not a denial. Distinguishing the
    # two matters: a denial is fixed with a grant, a hang is a bug in whatever
    # the interpreter sources at startup, and the remedies share nothing.
    # Measured on neptune 2026-09-11: `zsh -c` under launchd hangs forever in
    # run_init_scripts because zsh/env.d/08_mise.zsh shells out to
    # `gh auth token`, which blocks on a keychain it cannot prompt for.
    rp_pid=$(printf '%s\n' "$rp_state" | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)[[:space:]]*$/\1/p' | head -1)
    if [ -n "${PERMGATE_DEBUG:-}" ]; then
        printf 'DBG %s hit=%s pid=[%s] code=[%s] msg=[%s] outsize=%s\n' \
            "$rp_label" "$rp_hit" "$rp_pid" "$rp_code" "$rp_msg" \
            "$(wc -c < "$rp_out" 2>/dev/null | tr -d ' ')" >&2
    fi
    [ -n "$rp_pid" ] && kill "$rp_pid" 2>/dev/null || true
    launchctl bootout "gui/$UID_NUM/$rp_label" 2>/dev/null || true
    rm -f "$rp_file"
    case $rp_mode in
        logext) rm -f "$rp_out" 2>/dev/null || true ;;
    esac
    if [ "$rp_hit" -eq 1 ]; then
        printf '%s' "grant|"
    elif [ -n "$rp_pid" ]; then
        printf '%s' "hung|still running as pid $rp_pid after timeout — NOT a permission problem"
    elif [ -n "$rp_msg" ]; then
        printf '%s' "deny|${rp_code:+exit $rp_code — }$rp_msg"
    elif [ "$rp_code" = 78 ]; then
        printf '%s' "deny|exit 78 (EX_CONFIG) — killed in xpcproxy before exec, bad log path"
    elif [ "$rp_code" = 0 ]; then
        printf '%s' "deny|HARNESS BUG: exited 0 but stdout lacked the marker '$rp_marker'"
    else
        printf '%s' "deny|no marker and no stderr — job accepted but never ran (unreadable program path)"
    fi
}

# ---------------------------------------------------------------------------
mkdir -p "$LOGDIR"
printf '%s\n' "macOS permission gate — $HOSTSHORT (volume root: $OFFLOAD_ROOT)"
printf '\n'

vol_present=1
if [ -d "$OFFLOAD_ROOT" ] && printf 'CANARY-OK\n' > "$CANARY" 2>/dev/null; then
    vol_present=1
else
    vol_present=0
    printf '%s\n' "  NOTE: $OFFLOAD_ROOT absent or unwritable — volume rows will SKIP"
fi

manifest | sed -e "s#__CANARY__#$CANARY#g" -e "s#__OFFLOAD_ROOT__#$OFFLOAD_ROOT#g" > "$TMPROWS"

ok=0; regressed=0; drifted=0; skipped=0
problems=""
while IFS='|' read -r id mode expect marker payload summary; do
    [ -n "$id" ] || continue
    needs_vol=0
    case $mode in logext) needs_vol=1 ;; esac
    case $payload in *"$OFFLOAD_ROOT"*) needs_vol=1 ;; esac
    if [ "$needs_vol" -eq 1 ] && [ "$vol_present" -eq 0 ]; then
        printf '  %-28s SKIP            %s\n' "$id" "$summary"
        skipped=$((skipped + 1))
        continue
    fi
    result=$(run_probe "$PROBE_PREFIX.$id" "$mode" "$marker" "$payload")
    actual=${result%%|*}
    detail=${result#*|}
    if [ "$actual" = hung ]; then
        printf '  %-28s HUNG            %s\n' "$id" "$summary"
        regressed=$((regressed + 1))
        problems="$problems $id"
        [ "$VERBOSE" -eq 1 ] && [ -n "$detail" ] && printf '      %s\n' "$detail"
        continue
    fi
    if [ "$actual" = "$expect" ]; then
        printf '  %-28s ok (%-5s)     %s\n' "$id" "$expect" "$summary"
        ok=$((ok + 1))
    elif [ "$expect" = grant ]; then
        printf '  %-28s REGRESSED       %s\n' "$id" "$summary"
        regressed=$((regressed + 1))
        problems="$problems $id"
    else
        printf '  %-28s DRIFT (granted) %s\n' "$id" "$summary"
        drifted=$((drifted + 1))
        problems="$problems $id"
    fi
    if [ "$VERBOSE" -eq 1 ] && [ -n "$detail" ]; then
        printf '      %s\n' "$detail"
    fi
done < "$TMPROWS"

printf '\n  %d as declared, %d regressed, %d unexpected grants, %d skipped\n' \
    "$ok" "$regressed" "$drifted" "$skipped"

for id in $problems; do
    printf '\n--- %s\n' "$id"
    remedy "$id" | sed 's/^/    /'
done

[ "$((regressed + drifted))" -eq 0 ] || exit 1
exit 0
