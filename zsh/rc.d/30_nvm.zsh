

#!/usr/bin/env zsh
#set -euo pipefail

# XDG-compliant NVM_DIR (nvm stores data/binaries, not config)
export NVM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvm"

mkdir -p $NVM_DIR

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  #echo "nvm already installed at $NVM_DIR"
else
  echo "Installing nvm to $NVM_DIR..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
# Install latest LTS and set as default
    source "$NVM_DIR/nvm.sh"
    echo "Installing latest LTS Node..."
    nvm install --lts
    nvm alias default lts/*

    echo "Done. Node $(node --version) set as default."
fi

# Load nvm
source "$NVM_DIR/nvm.sh"


