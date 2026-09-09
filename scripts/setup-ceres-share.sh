#!/usr/bin/env bash
# setup-ceres-share.sh — Samba [downloads] share on ceres (office file server).
#
# ceres-only (hostname-gated). Idempotent. Needs sudo. Steps:
#   1. pacman-install samba (CachyOS/Arch),
#   2. create /srv/downloads as its OWN btrfs subvolume — root runs snapper,
#      and a nested subvolume keeps bulk download data out of every root
#      snapshot (snapshots don't cross subvolume boundaries),
#   3. install configs/samba/smb.conf -> /etc/samba/smb.conf (validated with
#      testparm first), enable+start smb.service.
#
# One manual step after first run: `sudo smbpasswd -a ctaylor` — Samba keeps
# its own password database, nothing to do with the unix password.
#
# Serves two shares (see configs/samba/smb.conf):
#   [downloads]  /srv/downloads   — the shared drop tree (quaoar Syncthing peer)
#   [home]       /home/ctaylor    — the workstation share for saturn/neptune,
#                                   with .ssh/.gnupg/.aws and the bulk trees
#                                   (immich, caches, node_modules) vetoed
#
# Clients: the Macs auto-mount [home] at login via scripts/smb-mount +
#   the com.github.ctaylor.smb-mount LaunchAgent (deployed by
#   scripts/deploy.d/76_smb_mounts.zsh; needs a one-time Keychain entry per
#   Mac — see that script's header). By hand: smb://10.77.0.74/home in Finder
#   (Cmd-K) or ForkLift, or mount -t cifs //10.77.0.74/downloads on Linux.
#
# NOTE: smbd binds eno2/wlan0 only, NOT tailscale0 — these shares are LAN-only
# by design, and bare `ceres` resolves to the Tailscale IP via MagicDNS on the
# Macs. Always address the shares by IP (wired 10.77.0.74 first).

set -eu

host=$(hostname)
if [ "${host%%.*}" != ceres ]; then
    echo "setup-ceres-share: this script is for ceres, not '$host'" >&2
    exit 0
fi

repo_root=$(cd "$(dirname "$0")/.." && pwd)
conf="$repo_root/configs/samba/smb.conf"
if [ ! -f "$conf" ]; then
    echo "setup-ceres-share: $conf not found (run from a dotfiles checkout)" >&2
    exit 1
fi

if ! command -v smbd >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm samba
fi

if ! sudo btrfs subvolume show /srv/downloads >/dev/null 2>&1; then
    sudo btrfs subvolume create /srv/downloads
fi
sudo chown ctaylor:ctaylor /srv/downloads
sudo chmod 2775 /srv/downloads

testparm -s "$conf" >/dev/null
if ! diff -q "$conf" /etc/samba/smb.conf >/dev/null 2>&1; then
    sudo install -D -m 644 "$conf" /etc/samba/smb.conf
    sudo systemctl enable --now smb.service
    sudo systemctl reload-or-restart smb.service
    echo "setup-ceres-share: smb.conf installed, smb.service running"
else
    sudo systemctl enable --now smb.service
    echo "setup-ceres-share: already up to date"
fi

# ceres runs ufw with default-deny INPUT: open 445 to the LAN only, scoped per
# interface like the existing rules ("Skipping" on re-run — idempotent).
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
    sudo ufw allow in on eno2 from 10.77.0.0/24 to any port 445 proto tcp comment 'samba office wired'
    sudo ufw allow in on wlan0 from 192.168.0.0/24 to any port 445 proto tcp comment 'samba wifi LAN'
fi

if ! sudo pdbedit -L 2>/dev/null | grep -q '^ctaylor:'; then
    echo ""
    echo "  Samba user missing — set an SMB password with:"
    echo "    sudo smbpasswd -a ctaylor"
fi
