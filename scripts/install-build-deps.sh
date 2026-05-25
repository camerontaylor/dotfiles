#!/bin/bash
set -euo pipefail

# Install build dependencies for env-wrappers (rbenv, pyenv, nodenv, etc.)
# Usage:
#   Linux (Debian/Ubuntu): sudo bash scripts/install-build-deps.sh [--check]
#   Linux (Arch/CachyOS):  sudo bash scripts/install-build-deps.sh [--check]
#   macOS:                 bash scripts/install-build-deps.sh [--check]

OS=$(uname -s)

APT_PACKAGES=(
    autoconf automake curl git libbz2-dev libcurl4-openssl-dev libedit-dev
    libffi-dev libgdbm-dev libgmp-dev libncurses-dev libreadline-dev
    libsqlite3-dev libssl-dev libtool liblzma-dev libxml2-dev libyaml-dev
    libclang-18-dev pkg-config python3-dev tk-dev tmux uuid-dev wget
)

PACMAN_PACKAGES=(
    autoconf automake curl git bzip2 libedit libffi gdbm gmp ncurses readline
    sqlite openssl libtool xz libxml2 libyaml clang pkgconf python tk tmux
    util-linux-libs wget moor
)

BREW_PACKAGES=(
    autoconf automake curl git libffi gdbm gmp ncurses readline sqlite
    openssl@3 libtool xz libxml2 libyaml llvm pkg-config python@3.12
    tcl-tk tmux wget moor
)

detect_linux_pm() {
    if command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null && command -v dpkg &>/dev/null; then
        echo "apt"
    else
        echo ""
    fi
}

ensure_homebrew_path() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x "$brew_bin" ]]; then
            eval "$("$brew_bin" shellenv bash)"
            hash -r
            return 0
        fi
    done

    return 1
}

check_apt_packages() {
    missing=0
    for pkg in "${APT_PACKAGES[@]}"; do
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
}

check_pacman_packages() {
    missing=0
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            echo "  MISSING: $pkg"
            ((missing++)) || true
        fi
    done
    if [[ $missing -eq 0 ]]; then
        echo "All build dependencies installed."
    else
        echo "$missing package(s) missing. Run: sudo bash $0"
    fi
}

check_brew_packages() {
    if ! ensure_homebrew_path; then
        echo "Homebrew not found. Install Homebrew first: https://brew.sh/"
        return 1
    fi

    missing=0
    for pkg in "${BREW_PACKAGES[@]}"; do
        if ! brew list --formula "$pkg" &>/dev/null; then
            echo "  MISSING: $pkg"
            ((missing++)) || true
        fi
    done
    if [[ $missing -eq 0 ]]; then
        echo "All build dependencies installed."
    else
        echo "$missing package(s) missing. Run: bash $0"
    fi
}

if [[ "${1:-}" == "--check" ]]; then
    case "$OS" in
        Linux)
            case "$(detect_linux_pm)" in
                pacman) check_pacman_packages ;;
                apt) check_apt_packages ;;
                *)
                    echo "This Linux installer supports APT (Debian/Ubuntu) and pacman (Arch) only."
                    exit 1
                    ;;
            esac
            ;;
        Darwin) check_brew_packages ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    exit 0
fi

case "$OS" in
    Linux)
        LINUX_PM=$(detect_linux_pm)
        if [[ -z "$LINUX_PM" ]]; then
            echo "This Linux installer supports APT (Debian/Ubuntu) and pacman (Arch) only."
            exit 1
        fi

        if [[ $EUID -ne 0 ]]; then
            echo "Run with sudo: sudo bash $0"
            exit 1
        fi

        case "$LINUX_PM" in
            apt)
                apt update || true
                apt install -y "${APT_PACKAGES[@]}"
                ;;
            pacman)
                pacman -Sy --noconfirm || true
                pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"
                ;;
        esac
        ;;
    Darwin)
        if [[ $EUID -eq 0 ]]; then
            echo "Do not run Homebrew installs with sudo. Run: bash $0"
            exit 1
        fi

        if ! ensure_homebrew_path; then
            echo "Homebrew not found. Install Homebrew first: https://brew.sh/"
            exit 1
        fi

        brew update || true
        brew install "${BREW_PACKAGES[@]}"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

if ! command -v moor &>/dev/null; then
    if [[ "$OS" == "Linux" && $EUID -eq 0 ]]; then
        echo "moor missing; install user-local tools later with: scripts/install-moor.sh"
    else
        "$(dirname "$0")/install-moor.sh"
    fi
fi

echo "Build dependencies installed successfully."
