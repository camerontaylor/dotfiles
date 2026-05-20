#!/usr/bin/env zsh
set -euo pipefail

# Deploy user-local tools (no sudo required)
# Usage: zsh scripts/deploy.zsh

BINDIR="${1:-$HOME/.local/bin}"
mkdir -p "$BINDIR"

OS=$(uname -s)

ensure_homebrew_path() {
  if command -v brew &>/dev/null; then
    return 0
  fi

  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv zsh)"
      hash -r
      return 0
    fi
  done

  return 1
}

brew_install_if_missing() {
  local formula="$1"
  local binary="${2:-$formula}"

  if ! ensure_homebrew_path; then
    echo "Homebrew not found; skipping $formula."
    return 0
  fi

  if command -v "$binary" &>/dev/null; then
    echo "$binary already installed: $("$binary" --version 2>/dev/null | head -1)"
    return 0
  fi

  echo "Installing $formula with Homebrew..."
  brew install "$formula"
}

# ── Neovim (AppImage) ────────────────────────────────────────────────
install_nvim() {
  if [[ "$OS" == "Darwin" ]]; then
    brew_install_if_missing neovim nvim
    return
  fi

  if [[ "$OS" != "Linux" ]]; then
    echo "Unsupported OS for nvim auto-install: $OS"
    return
  fi

  local current=""
  if command -v nvim &>/dev/null; then
    current=$(nvim --version 2>/dev/null | head -1 | awk '{print $2}')
  fi

  local latest
  latest=$(curl -sI https://github.com/neovim/neovim/releases/latest \
    | grep -i ^location: | sed 's|.*/tag/||' | tr -d '\r')

  if [[ "$current" == "$latest" ]]; then
    echo "nvim $current is already up to date."
    return
  fi

  echo "Installing nvim $latest to $BINDIR (was: ${current:-not installed})..."
  curl -Lo /tmp/nvim-appimage "https://github.com/neovim/neovim/releases/download/${latest}/nvim-linux-x86_64.appimage"
  chmod +x /tmp/nvim-appimage
  command mv -f -- /tmp/nvim-appimage "$BINDIR/nvim"

  echo "Installed: $($BINDIR/nvim --version | head -1)"
}

# ── Moor ─────────────────────────────────────────────────────────────
install_moor() {
  if [[ "$OS" == "Darwin" ]]; then
    brew_install_if_missing moor moor
    return
  fi

  if command -v moor &>/dev/null; then
    echo "moor already installed: $(moor --version)"
    return
  fi

  bash "$(dirname "$0")/install-moor.sh" "$BINDIR"
}

# ── Ripgrep ──────────────────────────────────────────────────────────
install_rg() {
  if [[ "$OS" == "Darwin" ]]; then
    brew_install_if_missing ripgrep rg
    return
  fi

  if [[ "$OS" != "Linux" ]]; then
    echo "Unsupported OS for rg auto-install: $OS"
    return
  fi

  local current=""
  if command -v rg &>/dev/null; then
    current=$(rg --version 2>/dev/null | head -1 | awk '{print $2}')
  fi

  local latest
  latest=$(curl -sI https://github.com/BurntSushi/ripgrep/releases/latest \
    | grep -i ^location: | sed 's|.*/tag/||' | tr -d '\r')

  if [[ "$current" == "$latest" ]]; then
    echo "rg $current is already up to date."
    return
  fi

  echo "Installing rg $latest to $BINDIR (was: ${current:-not installed})..."
  curl -Lo /tmp/rg.tar.gz "https://github.com/BurntSushi/ripgrep/releases/download/${latest}/ripgrep-${latest}-x86_64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/rg.tar.gz -C /tmp
  command mv -f -- "/tmp/ripgrep-${latest}-x86_64-unknown-linux-musl/rg" "$BINDIR/rg"
  chmod +x "$BINDIR/rg"
  rm -rf /tmp/rg.tar.gz "/tmp/ripgrep-${latest}-x86_64-unknown-linux-musl"

  echo "Installed: $($BINDIR/rg --version | head -1)"
}

# ── ast-grep ─────────────────────────────────────────────────────────
install_sg() {
  if [[ "$OS" == "Darwin" ]]; then
    brew_install_if_missing ast-grep sg
    return
  fi

  if [[ "$OS" != "Linux" ]]; then
    echo "Unsupported OS for sg auto-install: $OS"
    return
  fi

  local current=""
  if command -v sg &>/dev/null; then
    current=$(sg --version 2>/dev/null | awk '{print $2}')
  fi

  local latest
  latest=$(curl -sI https://github.com/ast-grep/ast-grep/releases/latest \
    | grep -i ^location: | sed 's|.*/tag/||' | tr -d '\r')

  if [[ "$current" == "$latest" ]]; then
    echo "sg $current is already up to date."
    return
  fi

  echo "Installing sg $latest to $BINDIR (was: ${current:-not installed})..."
  curl -Lo /tmp/sg.zip "https://github.com/ast-grep/ast-grep/releases/download/${latest}/app-x86_64-unknown-linux-gnu.zip"
  unzip -o /tmp/sg.zip -d /tmp/sg-extract
  command mv -f -- /tmp/sg-extract/sg "$BINDIR/sg"
  chmod +x "$BINDIR/sg"
  rm -rf /tmp/sg.zip /tmp/sg-extract

  echo "Installed: $($BINDIR/sg --version)"
}

# ── Run ──────────────────────────────────────────────────────────────
install_nvim
install_moor
install_rg
install_sg

echo "Deploy complete."
