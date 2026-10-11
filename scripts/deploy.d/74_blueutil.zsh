# Bluetooth CLI, macOS only. Use upstream's make build with Command Line
# Tools: Homebrew requires full Xcode when no bottle exists (Intel Macs).
# Pin release + checksum together; bump both to upgrade on the next deploy.
# Deploy only installs the CLI; never request Bluetooth access or toggle power.
[[ $DOTFILES_OS == Darwin ]] || return 0

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' '  [dry-run] would install blueutil 2.14.0 from verified upstream source into ~/.local/share/blueutil and link ~/.local/bin/blueutil'
    return 0
fi

# Subshell keeps temporary-file cleanup and variables out of the driver.
(
    bt_version=2.14.0
    bt_sha=8749883d52be4630c0b557656a487432050cc6e5d125f60d5b1efe646797d152
    bt_root=$HOME/.local/share/blueutil
    bt_release=$bt_root/$bt_version
    bt_link=$HOME/.local/bin/blueutil
    bt_target=../share/blueutil/$bt_version/blueutil

    # Don't replace a separately managed executable or symlink.
    if [[ -e $bt_link || -L $bt_link ]]; then
        bt_existing=$(readlink "$bt_link" 2>/dev/null) || {
            printf '%s\n' "blueutil: $bt_link is not a managed symlink; leaving it untouched" >&2
            exit 1
        }
        case $bt_existing in
            ../share/blueutil/*/blueutil|"$bt_root"/*/blueutil) ;;
            *) printf '%s\n' "blueutil: $bt_link belongs to another installer; leaving it untouched" >&2; exit 1 ;;
        esac
    fi

    if [[ $("$bt_release/blueutil" --version 2>/dev/null) != "$bt_version" ]]; then
        if [[ -e $bt_release || -L $bt_release ]]; then
            printf '%s\n' "blueutil: invalid install at $bt_release; move it aside and rerun deploy" >&2
            exit 1
        fi
        for bt_tool in curl shasum tar make xcrun; do
            have "$bt_tool" || { printf '%s\n' "blueutil: missing $bt_tool" >&2; exit 1; }
        done
        xcrun --find clang >/dev/null 2>&1 || {
            printf '%s\n' 'blueutil: install Command Line Tools with xcode-select --install, then rerun deploy' >&2
            exit 1
        }
        # Absolute CLT clang needs an explicit SDK when shell startup has not
        # supplied one (fresh HOME / unattended deployment).
        SDKROOT=$(xcrun --sdk macosx --show-sdk-path) || exit 1
        export SDKROOT
        mkdir -p "$bt_root" || exit 1
        bt_stage=$(mktemp -d "$bt_root/.build.XXXXXX") || exit 1
        trap 'rm -rf "$bt_stage"' EXIT
        printf '%s\n' "Building blueutil $bt_version with Command Line Tools..."
        curl -fL --retry 2 --connect-timeout 15 --max-time 120 \
            "https://github.com/toy/blueutil/archive/refs/tags/v$bt_version.tar.gz" \
            -o "$bt_stage/source.tar.gz" || exit 1
        printf '%s  %s\n' "$bt_sha" "$bt_stage/source.tar.gz" | shasum -a 256 -c - || exit 1
        tar -xzf "$bt_stage/source.tar.gz" -C "$bt_stage" || exit 1
        make -C "$bt_stage/blueutil-$bt_version" CC="$(xcrun --find clang)" || exit 1
        [[ $("$bt_stage/blueutil-$bt_version/blueutil" --version) == "$bt_version" ]] || exit 1
        mv "$bt_stage/blueutil-$bt_version" "$bt_release" || exit 1
    fi

    mkdir -p "$HOME/.local/bin" || exit 1
    if [[ $(readlink "$bt_link" 2>/dev/null) != "$bt_target" ]]; then
        ln -sfn "$bt_target" "$bt_link" || exit 1
    fi
    printf '%s\n' "blueutil $bt_version ready at $bt_link"
)
