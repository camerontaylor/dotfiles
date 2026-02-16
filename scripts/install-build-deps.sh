#!/bin/bash
set -euo pipefail

# Install APT build dependencies for env-wrappers (rbenv, pyenv, nodenv, etc.)
# Usage: sudo bash scripts/install-build-deps.sh [--check]

PACKAGES=(
    autoconf automake curl git libbz2-dev libcurl4-openssl-dev libedit-dev
    libffi-dev libgdbm-dev libgmp-dev libncurses-dev libreadline-dev
    libsqlite3-dev libssl-dev libtool liblzma-dev libxml2-dev libyaml-dev
    pkg-config python3-dev tk-dev uuid-dev wget
)

if [[ "${1:-}" == "--check" ]]; then
    missing=0
    for pkg in "${PACKAGES[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null || ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            echo "  MISSING: $pkg"
            ((missing++)) || true
        fi
    done
    if [[ $missing -eq 0 ]]; then
        echo "All build dependencies installed."
    else
        echo "$missing package(s) missing. Run: sudo bash $0"
    fi
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash $0"
    exit 1
fi

apt update
apt install -y "${PACKAGES[@]}"
echo "Build dependencies installed successfully."
