#!/usr/bin/env bash
# setup-office-lan.sh — pin this box's static IP on the office wired segment.
#
# Topology: the office switch interconnects the planet boxes but has NO uplink
# to the router (internet arrives over wifi), so ethernet never gets a DHCP
# lease. Each box therefore pins a static, GATEWAY-LESS 10.77.0.x IP on its
# wired NIC: the connected route sends inter-box traffic (ssh/smb/syncthing)
# down the wire at line rate, while the wifi default route — and thus internet
# — is untouched. Deliberately static, not DHCP-from-a-box: no boot-order
# dependency, and nothing to fight the real router if the switch ever gets
# uplinked. Wired last octet mirrors the box's wifi DHCP octet.
#
# Companion: the fast-path Match blocks at the top of ssh/config probe these
# wired IPs first, so `ssh ceres` etc. pick the wire automatically.
#
# Idempotent. Run once per box (and after a reinstall/re-cable). Needs sudo.

set -eu

PREFIX=10.77.0
NETMASK=255.255.255.0

os=$(uname -s)
if [ "$os" = Darwin ]; then
    host=$(scutil --get LocalHostName)   # `hostname` is unreliable (iMac != neptune)
else
    host=$(hostname)
    host=${host%%.*}
fi

case "$host" in
    saturn)   octet=102 iface=en0    ;;  # 2.5GbE USB adapter
    neptune)  octet=101 iface=en0    ;;  # iMac built-in 1GbE
    ceres)    octet=74  iface=eno2   ;;  # onboard 1GbE (second port)
    makemake) octet=97  iface=enp3s0 ;;  # onboard 1GbE
    *)
        echo "setup-office-lan: no wired mapping for '$host' — nothing to do" >&2
        exit 0
        ;;
esac

ip="$PREFIX.$octet"

if [ "$os" = Darwin ]; then
    # Both Macs expose the wired NIC as the "Ethernet" service. Omitting the
    # router argument is the load-bearing part: manual IP, no default route.
    if [ "$(ipconfig getifaddr "$iface" 2>/dev/null || true)" = "$ip" ]; then
        echo "office-lan: $iface already $ip"
    else
        sudo networksetup -setmanual Ethernet "$ip" "$NETMASK"
        echo "office-lan: Ethernet ($iface) set to $ip"
    fi
else
    # NetworkManager owns the NICs on the Linux boxes. never-default is
    # belt-and-braces: even if a gateway appears on the segment one day, this
    # profile must not capture the default route.
    if nmcli -t -f NAME con show | grep -qx office-lan; then
        echo "office-lan: connection already exists ($(nmcli -g ip4.address device show "$iface" 2>/dev/null || echo down))"
    else
        sudo nmcli con add type ethernet ifname "$iface" con-name office-lan \
            ipv4.method manual ipv4.addresses "$ip/24" \
            ipv4.never-default yes ipv6.method link-local
        sudo nmcli con up office-lan
        echo "office-lan: $iface up at $ip"
    fi
fi
