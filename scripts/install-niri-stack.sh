#!/usr/bin/env bash
# install-niri-stack.sh — provision the niri Wayland desktop stack.
#
# Linux/Arch only. Run by hand once per machine that runs niri:
#     ~/.local/dotfiles/scripts/install-niri-stack.sh
#
# Idempotent: pacman --needed skips already-installed packages.
# Mirrors the layout in ~/.local/dotfiles/configs/{niri,waybar,mako,
# fuzzel,hypr} — those configs are symlinked by deploy.d/20_symlinks.zsh.

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]] || ! command -v pacman >/dev/null 2>&1; then
  echo "FATAL: this script is Arch-Linux-only (no pacman found)." >&2
  exit 2
fi

echo "==> niri stack installer"

# ── Repo packages ──────────────────────────────────────────────────────────
PACMAN_PKGS=(
  # Compositor itself (skipped if already installed)
  niri
  # Terminal + fallback launcher
  ghostty fuzzel
  # Notifications, lock, idle daemon
  mako hyprlock hypridle
  # Screenshot + clipboard + clipboard history + clipboard persistence
  grim slurp cliphist wl-clipboard wl-clip-persist
  # X11 compat layer (niri has no built-in XWayland)
  xwayland-satellite
  # Wallpaper daemon with native rotation
  wpaperd
  # Power menu + monitor profiles + night-light + GTK theme picker
  wlogout kanshi wlsunset nwg-look
  # Brightness + media keys
  brightnessctl playerctl
  # Polkit GUI auth agent (autostarted by niri config)
  polkit-kde-agent
  # Status bar
  waybar
  # XDG portal (file pickers, screensharing) — gnome is the niri-recommended primary
  xdg-desktop-portal-gnome
  # Fonts (Noto base + Nerd Font for waybar icons)
  noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd
  # Icons used by mako + fuzzel
  papirus-icon-theme
)

# Optional: keep awww/swww around for one-off `awww img <file>` calls.
# wpaperd is the autostarted rotation daemon; awww-daemon is NOT autostarted
# (don't run both — they fight for the layer-shell wallpaper surface).
if pacman -Si awww >/dev/null 2>&1; then
  PACMAN_PKGS+=( awww )
elif pacman -Si swww >/dev/null 2>&1; then
  PACMAN_PKGS+=( swww )
fi

mkdir -p "$HOME/Pictures/wallpapers"

# ── AUR packages ───────────────────────────────────────────────────────────
AUR_PKGS=(
  vicinae-bin   # Raycast-like launcher (binary release, fastest install)
)

# ── Remove conflicting bits ────────────────────────────────────────────────
# xdg-desktop-portal-hyprland is for Hyprland, not niri. If both are
# installed, file pickers and screencasts route to the wrong impl.
if pacman -Q xdg-desktop-portal-hyprland >/dev/null 2>&1; then
  echo "==> Removing xdg-desktop-portal-hyprland (wrong portal for niri)"
  sudo pacman -Rns --noconfirm xdg-desktop-portal-hyprland || true
fi

# ── Install ────────────────────────────────────────────────────────────────
echo "==> Installing repo packages: ${#PACMAN_PKGS[@]} packages"
sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

if command -v paru >/dev/null 2>&1; then
  echo "==> Installing AUR packages via paru"
  paru -S --needed --noconfirm "${AUR_PKGS[@]}"
elif command -v yay >/dev/null 2>&1; then
  echo "==> Installing AUR packages via yay"
  yay -S --needed --noconfirm "${AUR_PKGS[@]}"
else
  echo "WARN: no AUR helper found. Install manually:"
  printf '       %s\n' "${AUR_PKGS[@]}"
fi

# ── Vicinae systemd user service ───────────────────────────────────────────
if systemctl --user list-unit-files vicinae.service >/dev/null 2>&1; then
  echo "==> Enabling vicinae user service"
  systemctl --user enable --now vicinae.service || true
fi

# ── Backup any existing niri config before symlink overwrites it ───────────
NIRI_CFG="$HOME/.config/niri/config.kdl"
if [[ -f "$NIRI_CFG" && ! -L "$NIRI_CFG" ]]; then
  bk="$NIRI_CFG.preinstall.$(date +%Y%m%d-%H%M%S).bak"
  cp "$NIRI_CFG" "$bk"
  echo "==> Backed up existing niri config → $bk"
fi

echo ""
echo "==> Install complete."
echo "    Next steps:"
echo "      1. Run ~/.local/dotfiles/deploy.zsh to symlink the new configs."
echo "      2. Drop a wallpaper at ~/.config/wallpaper (any image format awww supports)."
echo "      3. Reload niri:  niri msg action load-config-file"
echo "         (Or log out and back in for a full session restart.)"
echo ""
echo "    New keybinds (Mod = Super):"
echo "      Mod+T          → Ghostty terminal"
echo "      Mod+D          → Vicinae launcher (Raycast-style)"
echo "      Mod+Shift+D    → Fuzzel (fallback launcher)"
echo "      Mod+V          → Clipboard history (cliphist + fuzzel)"
echo "      Mod+O          → Workspaces overview"
echo "      Super+Alt+L    → Lock screen"
echo "      Mod+Shift+Q    → Power menu (wlogout)"
echo "      Shift+PrtSc    → Region screenshot → clipboard"
