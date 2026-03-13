#!/bin/bash
set -euo pipefail

# Default install directory (can be overridden with $1)
BINDIR="${1:-$HOME/.local/bin}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# Get latest release tag
LATEST=$(curl -sI https://github.com/walles/moor/releases/latest | grep -i ^location: | sed 's|.*/tag/||' | tr -d '\r')

echo "Installing moor $LATEST for $OS/$ARCH to $BINDIR..."

mkdir -p "$BINDIR"
curl -Lo /tmp/moor "https://github.com/walles/moor/releases/download/${LATEST}/moor-${LATEST}-${OS}-${ARCH}"
chmod +x /tmp/moor
mv /tmp/moor "$BINDIR/moor"

echo "Installed: $($BINDIR/moor --version)"
