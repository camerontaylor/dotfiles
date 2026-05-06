#!/usr/bin/env zsh

setopt extended_glob err_exit

local force=false
local git_add=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            force=true
            ;;
        --git-add)
            git_add=true
            ;;
        *)
            print "Usage: $0 [--force] [--git-add]" >&2
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

# Encryption uses the recipient list defined in .sops.yaml (no --age / --config
# overrides) so multi-machine setups stay multi-recipient.

local plaintext enc_file
for plaintext in {zsh/env.d,zsh/rc.d,nvim/init}/9[0-9]_*(N); do
    [[ $plaintext == *.enc ]] && continue

    enc_file="${plaintext}.enc"
    if ! $force && [[ -f $enc_file && $enc_file -nt $plaintext ]]; then
        print "Skipping ${plaintext}: encrypted ${enc_file} is newer (use --force to overwrite)"
        continue
    fi

    if [[ ! -f $enc_file || $plaintext -nt $enc_file || $force == true ]]; then
        print "Encrypting ${plaintext} -> ${enc_file}..."
        if sops --encrypt --input-type binary --output-type binary --output $enc_file $plaintext 2>/dev/null; then
            if $git_add; then
                git add $enc_file
            fi
            print "  ...done"
        else
            print "  ...failed to encrypt $plaintext" >&2
            exit 1
        fi
    fi
done

# SSH config and managed keys
local -a ssh_plaintexts ssh_enc_files
ssh_plaintexts=($HOME/.ssh/config ssh/webfront_claw ssh/webfront_claw.pub $HOME/.ssh/id_ed25519 $HOME/.ssh/id_ed25519.pub)
ssh_enc_files=(ssh/config.enc ssh/webfront_claw.enc ssh/webfront_claw.pub.enc ssh/id_ed25519.enc ssh/id_ed25519.pub.enc)
local i
for (( i = 1; i <= ${#ssh_plaintexts}; i++ )); do
    plaintext=${ssh_plaintexts[i]}
    enc_file=${ssh_enc_files[i]}
    [[ -f $plaintext ]] || continue

    mkdir -p ssh

    if ! $force && [[ -f $enc_file && $enc_file -nt $plaintext ]]; then
        print "Skipping ${plaintext}: encrypted ${enc_file} is newer (use --force to overwrite)"
    else
        print "Encrypting ${plaintext} -> ${enc_file}..."
        if sops --encrypt --input-type binary --output-type binary --output $enc_file $plaintext 2>/dev/null; then
            if $git_add; then
                git add $enc_file
            fi
            print "  ...done"
        else
            print "  ...failed to encrypt $plaintext" >&2
            exit 1
        fi
    fi
done

# Portless CA and server certs
local portless_dir=$HOME/.portless
for f (ca.pem ca-key.pem server.pem server-key.pem); do
    plaintext=$portless_dir/$f
    enc_file=configs/portless/${f}.enc
    [[ -f $plaintext ]] || continue

    if ! $force && [[ -f $enc_file && $enc_file -nt $plaintext ]]; then
        print "Skipping ${plaintext}: encrypted ${enc_file} is newer (use --force to overwrite)"
        continue
    fi

    print "Encrypting ${plaintext} -> ${enc_file}..."
    if sops --encrypt --input-type binary --output-type binary --output $enc_file $plaintext 2>/dev/null; then
        if $git_add; then
            git add $enc_file
        fi
        print "  ...done"
    else
        print "  ...failed to encrypt $plaintext" >&2
        exit 1
    fi
done
