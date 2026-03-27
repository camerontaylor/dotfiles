#!/usr/bin/env zsh

setopt extended_glob err_exit

local force=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            force=true
            ;;
        *)
            print "Usage: $0 [--force]" >&2
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

# Default XDG paths
XDG_CONFIG_HOME=$HOME/.config

if (( ! ${+commands[sops]} )); then
    print "sops not found; run 'mise install' first" >&2
    exit 1
fi

if [[ ! -f $XDG_CONFIG_HOME/sops/age/keys.txt ]]; then
    print "age key not found at $XDG_CONFIG_HOME/sops/age/keys.txt" >&2
    exit 1
fi

local enc_file target temp_file
for enc_file in {zsh/env.d,zsh/rc.d,nvim/init}/9[0-9]_*.enc(N); do
    target=${enc_file%.enc}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        print "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    print "Decrypting ${enc_file}..."
    temp_file=$(mktemp)
    if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
        chmod 600 $temp_file
        mv $temp_file $target
        print "  ...done"
    else
        rm -f $temp_file
        print "  ...failed to decrypt $enc_file (missing or wrong age key?)"
    fi
done
