#!/usr/bin/env zsh

set -euo pipefail

log() {
    print -r -- ""
    print -r -- "==> $*"
}

warn() {
    print -r -- ""
    print -r -- "!! $*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

if [[ "$(uname -s)" != Darwin ]]; then
    warn "This bootstrap is for macOS only."
    exit 1
fi

log "Manual permissions to grant before or after this script"
cat <<'EOF'
Open System Settings -> Privacy & Security and grant:

Full Disk Access:
- Terminal.app
- iTerm.app, if you use it
- /usr/libexec/sshd-keygen-wrapper

Developer Tools:
- Terminal.app
- iTerm.app, if you use it

Also allow any prompts for Command Line Tools, network access, or automation.
EOF

log "Enabling SSH login for this user"
sudo systemsetup -setremotelogin on || true
sudo dseditgroup -o edit -a "$USER" -t user com.apple.access_ssh || true

log "Checking Apple Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
    warn "Command Line Tools are missing. Starting Apple's installer now."
    xcode-select --install || true
    cat <<'EOF'

Finish the Command Line Tools installer UI, then run this script again:

  zsh ~/eris-macos-bootstrap.zsh

EOF
    exit 2
fi

sudo xcode-select --switch /Library/Developer/CommandLineTools || true
sudo xcodebuild -license accept || true

log "Installing Homebrew if needed"
if ! have brew; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
else
    warn "Homebrew install did not leave brew in a known location."
    exit 1
fi

log "Installing broad baseline tools"
brew update || true
brew install \
    git \
    zsh \
    bash \
    coreutils \
    gnu-sed \
    grep \
    findutils \
    gawk \
    make \
    curl \
    wget \
    unzip \
    gnupg \
    sops \
    age \
    gh \
    glab \
    awscli \
    mise \
    moor \
    caddy \
    jq \
    ripgrep \
    fd \
    ast-grep \
    neovim \
    tmux \
    || true

brew install --cask iterm2 || true

log "Making Homebrew shellenv available to zsh login shells"
BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
if [[ -x /usr/local/bin/brew ]]; then
    BREW_SHELLENV='eval "$(/usr/local/bin/brew shellenv)"'
fi

touch "$HOME/.zprofile"
if ! grep -Fq 'brew shellenv' "$HOME/.zprofile"; then
    {
        print -r -- ""
        print -r -- "# Homebrew"
        print -r -- "$BREW_SHELLENV"
    } >> "$HOME/.zprofile"
fi

log "Normalizing dotfiles checkout path"
mkdir -p "$HOME/.local"
if [[ -d "$HOME/.local/dotfiles/dotfiles/.git" && ! -d "$HOME/.local/dotfiles/.git" ]]; then
    mv "$HOME/.local/dotfiles/dotfiles" "$HOME/.local/dotfiles.new"
    rmdir "$HOME/.local/dotfiles" 2>/dev/null || rm -rf "$HOME/.local/dotfiles"
    mv "$HOME/.local/dotfiles.new" "$HOME/.local/dotfiles"
fi

if [[ -d "$HOME/.local/dotfiles/.git" ]]; then
    log "Configuring checked-out repo to accept pushes"
    git -C "$HOME/.local/dotfiles" config receive.denyCurrentBranch updateInstead || true

    log "Deploying dotfiles"
    zsh "$HOME/.local/dotfiles/deploy.zsh"
else
    warn "$HOME/.local/dotfiles is not a git checkout yet."
    warn "After cloning it there, run:"
    warn "  git -C ~/.local/dotfiles config receive.denyCurrentBranch updateInstead"
    warn "  zsh ~/.local/dotfiles/deploy.zsh"
fi

log "Done"
cat <<'EOF'

After this finishes, remote push/deploy from Linux should work:

  git push eris main
  ssh user@eris 'cd ~/.local/dotfiles && zsh ./deploy.zsh'

EOF
