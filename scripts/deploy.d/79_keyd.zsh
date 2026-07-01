# keyd — system-level key remapper (Linux only). Delivers the Caps Lock =
# Esc-on-tap / Hyper-on-hold behaviour that Karabiner provides on macOS
# (78_karabiner.zsh), so the keyboard scheme is identical across every machine.
#
# keyd reads /etc/keyd/default.conf as ROOT (it runs before the compositor), so
# unlike every XDG config in 20_symlinks.zsh this cannot be a user symlink — we
# copy the tracked configs/keyd/default.conf into place with sudo and reload.
# Source of truth: configs/keyd/default.conf. Idempotent: a re-deploy with an
# unchanged config is a no-op (and avoids a sudo prompt where possible).

if [[ $DOTFILES_OS != Linux ]]; then
    return 0
fi

local keyd_src=$SCRIPT_DIR/configs/keyd/default.conf
local keyd_target=/etc/keyd/default.conf

# keyd is not in every distro's default repos (often AUR on Arch). Don't try to
# install it blindly — if it's absent, tell the user how and bail without
# touching /etc. Re-running deploy after installing it wires everything up.
if (( ! ${+commands[keyd]} )); then
    local distro_like=""
    if [[ -r /etc/os-release ]]; then
        distro_like=$(. /etc/os-release 2>/dev/null && print -r -- "${ID:-} ${ID_LIKE:-}")
    fi
    print "keyd not installed — Caps→Esc/Hyper inactive on this box. Install it, then re-run deploy:"
    case " $distro_like " in
        *" arch "*) print "  paru -S keyd   (or: yay -S keyd / sudo pacman -S keyd if your repos carry it)" ;;
        *" debian "*|*" ubuntu "*) print "  build from source — see https://github.com/rvaiya/keyd (not packaged in apt)" ;;
        *) print "  see https://github.com/rvaiya/keyd#installation" ;;
    esac
    return 0
fi

# keyd present. Install the config if it differs from what's tracked.
if sudo cmp -s "$keyd_src" "$keyd_target" 2>/dev/null; then
    print "keyd config up to date; skipping"
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] would: sudo install -Dm644 ${(D)keyd_src} $keyd_target (backing up any existing)"
    print "  [dry-run] would: sudo systemctl enable --now keyd && sudo keyd reload"
    return 0
fi

print "Installing keyd config to $keyd_target..."
# Back up an existing target once per change so a hand-edited /etc file is never
# silently lost (mirrors the karabiner.json .bak behaviour).
if [[ -e $keyd_target ]]; then
    sudo cp -p "$keyd_target" "$keyd_target.bak" 2>/dev/null || true
fi
if sudo install -Dm644 "$keyd_src" "$keyd_target"; then
    # Enable the service (no-op if already enabled) and hot-reload the config.
    sudo systemctl enable --now keyd > /dev/null 2>&1 || true
    sudo keyd reload > /dev/null 2>&1 || true
    print "  ...installed and reloaded (verify with: sudo keyd monitor)"
else
    print "  ...failed to install keyd config (see output above)"
fi
