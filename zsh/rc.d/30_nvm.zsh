# Auto-install NVM if missing
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "Installing nvm to $NVM_DIR..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm alias default lts/*
    echo "Done. Node $(node --version) set as default."
    return
fi

# Lazy-init: define wrapper functions that load NVM on first use
() {
    local cmd
    for cmd in nvm node npm npx corepack; do
        eval "$cmd () {
            unset -f nvm node npm npx corepack
            source \"\$NVM_DIR/nvm.sh\"
            $cmd \"\$@\"
        }"
    done
}
