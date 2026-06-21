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
    # Homebrew's tap-trust gate (HOMEBREW_REQUIRE_TAP_TRUST) makes brew ignore
    # non-official taps until trusted; trust this specific formula so the install
    # below isn't silently skipped. No-op on brew versions without `trust`.
    if brew trust --help > /dev/null 2>&1; then
        brew trust --formula satococoa/tap/wtp > /dev/null 2>&1 || true
    fi
    local brew_output
    if brew_output=$(brew install satococoa/tap/wtp 2>&1); then
        rehash
        if (( ${+commands[wtp]} )); then
            print "  ...done"
            exit 0
        fi
        # brew install exited 0 but the keg is unlinked — typically because a
        # sibling completion dir (e.g. /usr/local/share/fish/vendor_completions.d)
        # is owned by another user and brew aborts the entire link when any
        # single symlink fails. Bypass the link step by pointing ~/.local/bin/wtp
        # at the keg directly; that's all we actually need.
        local wtp_prefix=
        wtp_prefix=$(brew --prefix satococoa/tap/wtp 2>/dev/null) || wtp_prefix=
        if [[ -n $wtp_prefix && -x $wtp_prefix/bin/wtp ]]; then
            mkdir -p $install_dir
            ln -sf $wtp_prefix/bin/wtp $target
            rehash
            print "  ...brew keg was unlinked; symlinking $wtp_prefix/bin/wtp -> $target"
            print "  brew said:"
            print -r -- "$brew_output" | sed 's/^/    /'
            print "  ...done"
            exit 0
        fi
        print "  ...brew install reported success but produced no wtp binary"
        print -r -- "$brew_output" | sed 's/^/    /'
    else
        print "  ...Homebrew install failed:"
        print -r -- "$brew_output" | sed 's/^/    /'
    fi
    print "  ...trying direct release asset"
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
    if [[ $wtp_os == Darwin ]]; then
        print "  ...wtp upstream only ships Darwin arm64 binaries; install Homebrew then: brew install satococoa/tap/wtp"
    else
        print "  ...unsupported platform for wtp auto-install, skipping"
    fi
    exit 1
fi
