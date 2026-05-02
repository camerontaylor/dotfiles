#!/usr/bin/env zsh

setopt extended_glob err_exit pipefail

local force=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            force=true
            ;;
        *)
            print "Usage: $0 [--force|-f]" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR=${0:A:h:h}
# with systemd-homed `a`/`A` expands to storage location `/home/username.homedir` instead of mounted location `/home/username`
# therefore massage SCRIPT_DIR to expected home location by removing `.homedir` from it
if [[ $SCRIPT_DIR == $HOME.homedir* ]]; then
    SCRIPT_DIR=${SCRIPT_DIR/.homedir/}
fi
cd $SCRIPT_DIR

local install_dir=$HOME/.local/bin
local target=$install_dir/wtp

if (( ${+commands[wtp]} )) && ! $force; then
    print "wtp already installed, skipping"
    exit 0
fi

if $force && (( ${+commands[wtp]} )); then
    print "Reinstalling wtp..."
else
    print "Installing wtp..."
fi

local wtp_arch=$(uname -m)
local wtp_os=$(uname -s)

ensure_homebrew_path() {
    if (( ${+commands[brew]} )); then
        return 0
    fi

    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x $brew_bin ]]; then
            eval "$($brew_bin shellenv zsh)"
            rehash
            return 0
        fi
    done

    return 1
}

if [[ $wtp_os == Darwin ]] && ensure_homebrew_path; then
    if brew install satococoa/tap/wtp > /dev/null 2>&1; then
        rehash
        print "  ...done"
        exit 0
    fi
    print "  ...Homebrew install failed, trying direct release asset"
fi

if [[ $wtp_os == Linux && ($wtp_arch == x86_64 || $wtp_arch == aarch64) ]] || [[ $wtp_os == Darwin && $wtp_arch == arm64 ]]; then
    [[ $wtp_arch == aarch64 ]] && wtp_arch=arm64
    local wtp_version
    wtp_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/satococoa/wtp/releases/latest | sed 's|.*/tag/v||')
    local wtp_tmp=$(mktemp -d)
    trap 'rm -rf "$wtp_tmp"' EXIT
    if [[ -n $wtp_version ]] && curl -fsSL "https://github.com/satococoa/wtp/releases/download/v${wtp_version}/wtp_${wtp_version}_${wtp_os}_${wtp_arch}.tar.gz" | tar xz -C $wtp_tmp; then
        mkdir -p $install_dir
        mv -f $wtp_tmp/wtp $target
        chmod +x $target
        print "  ...done"
    else
        print "  ...failed to download wtp release asset, skipping"
        exit 1
    fi
else
    print "  ...unsupported platform for wtp auto-install, skipping"
    exit 1
fi
