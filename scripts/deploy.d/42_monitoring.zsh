# Resource-monitoring tools, Linux half (docs/monitoring.md). The set is split
# by *question asked*, not by preference — one TUI cannot answer all three:
#
#   glance      btop            what is happening right now   (mise; configs/mise.toml)
#   glance      htop            SSH / low-memory fallback     (75_brew_setup.zsh)
#   attribution bandwhich       per-process network           (mise, both OSes)
#   attribution iotop-c         per-process block I/O         (here)
#   attribution bpftrace        short-lived processes that a sampling monitor
#                               never catches (execsnoop/opensnoop one-liners)
#   attribution nvtop           GPU, including Intel i915     (here)
#   history     atop            "what ate the box at 03:12"   (here)
#   profiling   samply          which *function*, not which process (mise)
#
# atop is the one with no real competitor: every interactive monitor is useless
# for post-mortem questions by construction. It is also the only entry here that
# is inert without a systemd unit — see the enable step below.
#
# Deliberately NOT installed: `bottom`/`btm` (btop already covers glance; its
# TOML pane layout is not a need we have) and `perf` (samply is the
# cross-platform profiler and needs no kernel-version-matched userspace).
#
# macOS gets its half in 75_brew_setup.zsh (btop, htop, macmon) — this fragment
# is Linux-only because every tool below is Linux-kernel-coupled.

if [[ $DOTFILES_OS != Linux ]]; then
    return 0
fi

# os-release is designed to be sourced; do it in a subshell so its vars don't
# leak. Arch-family derivatives (cachyos/manjaro/endeavouros) set ID or ID_LIKE
# to "arch". Mirrors 40_tools.zsh / 41_net_tools.zsh.
distro_id="" distro_like=""
if [[ -r /etc/os-release ]]; then
    distro_id=$(. /etc/os-release 2>/dev/null && printf '%s\n' "${ID:-}")
    distro_like=$(. /etc/os-release 2>/dev/null && printf '%s\n' "${ID_LIKE:-}")
fi

# Package name per distro. Arch calls the maintained C rewrite of iotop
# "iotop-c" (the python `iotop` is a different, staler project).
# An ARRAY, not a space-separated string: zsh does not word-split unquoted
# parameters the way bash does, so a string would arrive at pacman as one
# giant package name. "${mon_pkgs[@]}" expands per-element and "${mon_pkgs[*]}"
# joins for display in BOTH shells, which the zsh-only ${=var} spelling does
# not — and bash -n accepts ${=var} happily, so the gate would not catch it.
mon_pkgs=()
mon_installer=""
case " $distro_id $distro_like " in
    *" arch "*)
        mon_pkgs=(atop iotop-c bpftrace nvtop)
        mon_installer=pacman
        ;;
    *" debian "*|*" ubuntu "*)
        mon_pkgs=(atop iotop bpftrace nvtop)
        mon_installer=apt
        ;;
esac

if [[ -z $mon_installer ]]; then
    printf '%s\n' "monitoring: unrecognised Linux distro — install atop/iotop/bpftrace/nvtop by hand"
    return 0
fi

# Skip the package manager entirely when everything is already present, so the
# common case costs nothing. `iotop-c` installs a binary named `iotop`, so probe
# binaries rather than package names.
mon_missing=0
for mon_bin in atop iotop bpftrace nvtop; do
    have "$mon_bin" || mon_missing=1
done

if (( mon_missing )); then
    # sudo can prompt for a password, and the post-merge/post-checkout git hook
    # has no TTY to answer it. Only attempt an install when sudo is already
    # passwordless/cached or stdin is a terminal; otherwise leave a copy-paste
    # hint rather than hanging the hook. Same guard as 75_brew_setup.zsh's htop.
    if [[ $mon_installer == pacman ]]; then
        # -Sy (not -Syu) so a stale db entry doesn't 404, --needed for
        # idempotency. See 73_tailscale.zsh on the partial-upgrade caveat.
        mon_cmd="sudo pacman -S --needed ${mon_pkgs[*]}"
    else
        mon_cmd="sudo apt-get install -y ${mon_pkgs[*]}"
    fi

    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would install monitoring tools: ${mon_pkgs[*]}"
    elif ! { sudo -n true 2>/dev/null || [[ -t 0 ]]; }; then
        printf '%s\n' "monitoring tools missing; install with: $mon_cmd"
    else
        printf '%s\n' "Installing monitoring tools (${mon_pkgs[*]})..."
        if [[ $mon_installer == pacman ]]; then
            mon_ok=0
            sudo pacman -Sy --needed --noconfirm "${mon_pkgs[@]}" > /dev/null 2>&1 || mon_ok=1
        else
            mon_ok=0
            sudo apt-get install -y "${mon_pkgs[@]}" > /dev/null 2>&1 || mon_ok=1
        fi
        if (( mon_ok == 0 )); then
            hash -r
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed (retry: $mon_cmd)"
        fi
    fi
fi

# atop's whole value is the history layer, and that only exists if its units
# run: atop.service writes the interval samples under /var/log/atop that
# `atop -r` replays, and atopacct.service adds per-process accounting so
# processes that started AND exited between samples still show up. Installed
# but not enabled is the silent-failure case — you find out you have no data
# on the day you need it. Unit names differ across atop versions, so enable
# whichever of the candidates this install actually shipped rather than
# hardcoding a set that may not exist.
if have atop && have systemctl; then
    for mon_unit in atop.service atopacct.service atop-rotate.timer; do
        # Producer `|| true`-guarded: under the bash driver's pipefail a grep -q
        # early exit could SIGPIPE systemctl and flip this gate (73_tailscale.zsh).
        { systemctl list-unit-files "$mon_unit" 2>/dev/null || true; } \
            | grep -q "^$mon_unit" || continue
        if { systemctl is-enabled "$mon_unit" 2>/dev/null || true; } \
            | grep -q '^enabled'; then
            continue
        fi
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would: sudo systemctl enable --now $mon_unit"
        elif ! { sudo -n true 2>/dev/null || [[ -t 0 ]]; }; then
            printf '%s\n' "atop history inactive; enable with: sudo systemctl enable --now $mon_unit"
        elif sudo systemctl enable --now "$mon_unit" > /dev/null 2>&1; then
            printf '%s\n' "  ...enabled $mon_unit (atop history recording)"
        else
            printf '%s\n' "  ...failed to enable $mon_unit"
        fi
    done
fi

# samply (and bpftrace/perf) call perf_event_open(2), which the kernel gates on
# kernel.perf_event_paranoid. Arch ships 2 = "userspace measurements only", at
# which samply cannot profile and reports nothing useful; upstream asks for <= 1.
#
# This is a permission gate ONLY — it is checked at perf_event_open() time and
# enables no collection, so there is no idle cost to lowering it. The trade-off
# is disclosure: at 1 any local process can read kernel profiling data. That is
# an accepted risk on a single-user dev box (Cameron, 2026-09-04) and is undone
# by deleting the drop-in below and rebooting (or sysctl -w back to 2).
#
# Written as a drop-in rather than `sysctl -w` so it survives reboot, and
# content-compared first so a re-deploy is a genuine no-op.
mon_sysctl_file=/etc/sysctl.d/60-perf-profiling.conf
mon_sysctl_want='kernel.perf_event_paranoid = 1'
if [[ -r /proc/sys/kernel/perf_event_paranoid ]]; then
    if grep -qxF "$mon_sysctl_want" "$mon_sysctl_file" 2>/dev/null; then
        : # already declared; nothing to do
    elif (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would write $mon_sysctl_file ($mon_sysctl_want)"
    elif ! { sudo -n true 2>/dev/null || [[ -t 0 ]]; }; then
        printf '%s\n' "samply needs kernel.perf_event_paranoid <= 1; set it with:"
        printf '%s\n' "  echo '$mon_sysctl_want' | sudo tee $mon_sysctl_file && sudo sysctl --system"
    else
        printf '%s\n' "Allowing unprivileged profiling (perf_event_paranoid=1)..."
        if printf '%s\n' "# samply/bpftrace need <= 1 to profile without sudo." \
                "# Managed by dotfiles scripts/deploy.d/42_monitoring.zsh." \
                "$mon_sysctl_want" \
                | sudo tee "$mon_sysctl_file" > /dev/null \
            && sudo sysctl -q -w kernel.perf_event_paranoid=1 > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to write $mon_sysctl_file"
        fi
    fi
fi

unset distro_id distro_like mon_pkgs mon_installer mon_missing mon_bin mon_unit mon_cmd mon_ok
unset mon_sysctl_file mon_sysctl_want
