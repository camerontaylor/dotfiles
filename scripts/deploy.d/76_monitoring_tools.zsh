# Native performance-monitoring tools. Portable btop, bandwhich, and samply
# are installed by mise; these tools depend directly on OS facilities.

if [[ $DOTFILES_OS == Darwin ]]; then
    if ensure_homebrew_path; then
        print "Installing native macOS monitoring tools via brew..."
        brew_formula_install_or_upgrade htop || true
        # macmon is Apple-Silicon-only. Avoid a guaranteed brew failure on the
        # Intel Mac still supported by this repository.
        if [[ $DOTFILES_ARCH == arm64 ]]; then
            brew_formula_install_or_upgrade macmon || true
        else
            print "  ...macmon skipped (requires Apple Silicon)"
        fi
    fi
    return 0
fi

[[ $DOTFILES_OS == Linux ]] || return 0

# Package name and command name differ for iotop-c.
local -a native_monitor_specs=(
    htop:htop
    atop:atop
    iotop-c:iotop
    bpftrace:bpftrace
    nvtop:nvtop
)
local -a missing_packages=()
local spec package binary
for spec in $native_monitor_specs; do
    package=${spec%%:*}
    binary=${spec##*:}
    (( ${+commands[$binary]} )) || missing_packages+=($package)
done

(( ${#missing_packages} )) || return 0

local distro_id="" distro_like=""
if [[ -r /etc/os-release ]]; then
    distro_id=$(. /etc/os-release 2>/dev/null && print -r -- "${ID:-}")
    distro_like=$(. /etc/os-release 2>/dev/null && print -r -- "${ID_LIKE:-}")
fi

local install_hint
case " $distro_id $distro_like " in
    *" arch "*)
        install_hint="sudo pacman -Sy --needed --noconfirm ${missing_packages[*]}"
        ;;
    *" debian "*|*" ubuntu "*)
        install_hint="sudo apt-get install -y ${missing_packages[*]}"
        ;;
    *)
        print "monitoring-tools: unsupported Linux package manager; install: ${missing_packages[*]}"
        return 0
        ;;
esac

if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] would: $install_hint"
elif sudo -n true 2>/dev/null || [[ -t 0 ]]; then
    print "Installing native Linux monitoring tools..."
    if ${(z)install_hint}; then
        rehash
        print "  ...done"
    else
        print "  ...failed; retry manually: $install_hint"
    fi
else
    print "Monitoring tools missing; install them with: $install_hint"
fi
