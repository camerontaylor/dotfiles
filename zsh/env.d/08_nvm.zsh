# XDG-compliant NVM_DIR (nvm stores data/binaries, not config)
export NVM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvm"
mkdir -p $NVM_DIR
