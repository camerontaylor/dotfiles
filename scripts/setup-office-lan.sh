#!/usr/bin/env bash
# One-off home Ethernet setup. Never invoke from unattended deploy hooks.
# The switch and router now share 192.168.0.0/24; ordinary hosts use .1.
# Ceres retains .254 for DHCP clients and the selected-device VPN gateway.
# Pluto is configured by infra nixos/hosts/pluto.nix and configs/pluto/.
set -eu

os=$(uname -s)
if [ "$os" = Darwin ]; then
    host=$(scutil --get LocalHostName)
else
    host=$(hostname)
    host=${host%%.*}
fi
case "$host" in
    saturn)   octet=4; iface=en0; metric=40 ;;
    neptune)  octet=5; iface=en0; metric=40 ;;
    ceres)    octet=3; iface=eno2; metric=20 ;;
    makemake) octet=2; iface=enp3s0; metric=40 ;;
    *) echo "setup-office-lan: no mapping for $host" >&2; exit 0 ;;
esac
ip=192.168.0.$octet
if [ "$os" = Darwin ]; then
    sudo networksetup -setmanual Ethernet "$ip" 255.255.255.0 192.168.0.1
    sudo networksetup -setdnsservers Ethernet 192.168.0.2 1.1.1.1
else
    addresses=$ip/24
    # Temporary compatibility for two existing ad hoc proxy listeners.
    if [ "$host" = makemake ]; then addresses=$addresses,10.77.0.2/24; fi
    if [ "$host" = ceres ]; then
        addresses=$addresses,192.168.0.254/24,10.77.0.3/24,10.77.0.1/24
    fi
    if ! nmcli -t -f NAME con show | grep -qx office-lan; then
        sudo nmcli con add type ethernet ifname "$iface" con-name office-lan
    fi
    sudo nmcli con modify office-lan ipv4.method manual \
        ipv4.addresses "$addresses" ipv4.gateway 192.168.0.1 \
        ipv4.dns "192.168.0.2,1.1.1.1" ipv4.ignore-auto-dns yes \
        ipv4.never-default no ipv4.route-metric "$metric" ipv6.method link-local
    if nmcli -t -f NAME con show --active | grep -qx office-lan; then
        sudo nmcli device reapply "$iface"
    else
        sudo nmcli con up office-lan
    fi
fi
echo "office-lan: $iface configured as $ip via router 192.168.0.1"
