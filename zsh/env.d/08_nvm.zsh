# XDG-compliant NVM_DIR (nvm stores data/binaries, not config)
export NVM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvm"
[[ -d "$NVM_DIR" ]] || mkdir -p "$NVM_DIR" 2>/dev/null

# Eagerly add default node to PATH so globally installed packages
# (pnpm, etc.) are found without waiting for lazy nvm init
() {
    [[ -f "$NVM_DIR/alias/default" ]] || return
    local nvm_ver=$(<"$NVM_DIR/alias/default")
    # Follow alias chain (e.g. default -> lts/iron -> v20.x.x)
    while [[ -f "$NVM_DIR/alias/$nvm_ver" ]]; do
        nvm_ver=$(<"$NVM_DIR/alias/$nvm_ver")
    done
    # Resolve lts/* to highest installed LTS version
    # (codenames are alphabetical by release, so last glob match = latest)
    if [[ $nvm_ver == lts/* ]]; then
        nvm_ver=
        local f v
        for f in "$NVM_DIR"/alias/lts/*(N); do
            v=$(<"$f")
            [[ -d "$NVM_DIR/versions/node/$v" ]] && nvm_ver=$v
        done
    fi
    [[ -n $nvm_ver ]] || return
    local node_dir="$NVM_DIR/versions/node/$nvm_ver"
    [[ -d $node_dir ]] || node_dir="$NVM_DIR/versions/node/v${nvm_ver#v}"
    [[ -d $node_dir/bin ]] && path=("$node_dir/bin" $path)
}
