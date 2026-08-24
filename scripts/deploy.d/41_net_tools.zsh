# Network tools, in two groups:
#   probes — openbsd-netcat (nc) + socat, used by ~/.ssh/config's optimistic LAN
#     fast-path (Match exec "nc -z -w1 <ip> 22") and for ad-hoc debugging. macOS
#     ships a BSD `nc` already, so there we only ensure socat.
#   fetch  — wget, for CLI convenience (recursive/mirroring downloads, -O/-c
#     muscle memory). Neither macOS nor an Arch base install ships it. mise has
#     no wget backend — autotools C with no prebuilt binaries in the aqua
#     registry — so it comes from brew/pacman under CLAUDE.md's "brew only for
#     what mise can't deliver" rule. zsh/rc.d/08_aliases.zsh redirects its HSTS
#     db into $XDG_CACHE_HOME once it is on PATH.

if [[ $DOTFILES_OS != Linux && $DOTFILES_OS != Darwin ]]; then
    return 0
fi

if [[ $DOTFILES_OS == Darwin ]]; then
    if ensure_homebrew_path; then
        (( ${+commands[socat]} )) || brew_formula_install_or_upgrade socat || true
        (( ${+commands[wget]} )) || brew_formula_install_or_upgrade wget || true
    fi
    return 0
fi

# Linux: nothing to do if all three are already present.
if (( ${+commands[nc]} )) && (( ${+commands[socat]} )) && (( ${+commands[wget]} )); then
    return 0
fi

# Arch-family native install (cachyos/manjaro/endeavouros/... set ID or ID_LIKE
# to "arch"). Mirror 73_tailscale.zsh: source os-release in a subshell, -Sy so a
# stale db entry doesn't 404, --needed for idempotency. See that file's note on
# the partial-upgrade caveat of -Sy without -u.
local distro_id="" distro_like=""
if [[ -r /etc/os-release ]]; then
    distro_id=$(. /etc/os-release 2>/dev/null && print -r -- "${ID:-}")
    distro_like=$(. /etc/os-release 2>/dev/null && print -r -- "${ID_LIKE:-}")
fi

case " $distro_id $distro_like " in
    *" arch "*)
        if (( DEPLOY_DRY_RUN )); then
            print "  [dry-run] would: sudo pacman -Sy --needed --noconfirm openbsd-netcat socat wget"
        elif sudo pacman -Sy --needed --noconfirm openbsd-netcat socat wget; then
            rehash
            print "  ...net tools (nc, socat, wget) present"
        else
            print "  ...failed to install net tools (see output above)"
        fi
        ;;
    *)
        print "net-tools: non-Arch Linux — install nc + socat + wget via your package manager"
        ;;
esac
