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
    print "" >&2
    print "  To decrypt secrets, place your age private key at:" >&2
    print "    $XDG_CONFIG_HOME/sops/age/keys.txt" >&2
    print "" >&2
    print "  If you have a backup, copy it there and run this script again." >&2
    print "  If setting up fresh, run deploy.zsh first to generate a new key." >&2
    print "  (A new key cannot decrypt existing .enc files — you must re-encrypt them.)" >&2
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

# SSH config and managed keys
for enc_file in ssh/*.enc(N); do
    target=ssh/${${enc_file:t}%.enc}
    mkdir -p ssh
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        print "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
    else
        print "Decrypting ${enc_file}..."
        temp_file=$(mktemp)
        if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
            if [[ $target == *.pub ]]; then
                chmod 644 $temp_file
            else
                chmod 600 $temp_file
            fi
            mv $temp_file $target
            print "  ...done"
        else
            rm -f $temp_file
            print "  ...failed to decrypt $enc_file (missing or wrong age key?)"
        fi
    fi
done

# Portkey gateway runtime state. Targets live outside this repo at
# ~/.local/state/portkey/ — the systemd unit's EnvironmentFile and the
# PORTKEY_LOCAL_API_KEY path both reference them by absolute path.
local portkey_state_dir=$HOME/.local/state/portkey
local -a portkey_enc_files portkey_targets
portkey_enc_files=(configs/ai/portkey/state/env.enc configs/ai/portkey/state/local-api-key.enc)
portkey_targets=($portkey_state_dir/env $portkey_state_dir/local-api-key)
if (( ${#portkey_enc_files} > 0 )); then
    install -m 700 -d $portkey_state_dir
fi
for (( i = 1; i <= ${#portkey_enc_files}; i++ )); do
    enc_file=${portkey_enc_files[i]}
    target=${portkey_targets[i]}
    [[ -f $enc_file ]] || continue
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        print "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    print "Decrypting ${enc_file} -> ${target}..."
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

# restic repository password for the Immich backup. Target lives outside this
# repo at ~/repos/deploy/immich/ because the backup systemd unit references it
# by absolute path via RESTIC_PASSWORD_FILE.
local restic_dir=$HOME/repos/deploy/immich
local -a restic_enc_files restic_targets
restic_enc_files=(configs/immich/restic-password.enc configs/immich/b2-env.enc)
restic_targets=($restic_dir/.restic-password $restic_dir/.b2-env)
for (( i = 1; i <= ${#restic_enc_files}; i++ )); do
    enc_file=${restic_enc_files[i]}
    target=${restic_targets[i]}
    [[ -f $enc_file ]] || continue
    [[ -d ${target:h} ]] || install -m 700 -d ${target:h}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        print "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    print "Decrypting ${enc_file} -> ${target}..."
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

# openclaw-mcp bridge environment. Target lives outside this repo at
# ~/.config/openclaw-mcp/env, which the bridge reads directly.
local -a openclaw_enc_files openclaw_targets
openclaw_enc_files=(configs/openclaw-mcp/env.enc)
openclaw_targets=($HOME/.config/openclaw-mcp/env)
for (( i = 1; i <= ${#openclaw_enc_files}; i++ )); do
    enc_file=${openclaw_enc_files[i]}
    target=${openclaw_targets[i]}
    [[ -f $enc_file ]] || continue
    [[ -d ${target:h} ]] || install -m 700 -d ${target:h}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        print "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    print "Decrypting ${enc_file} -> ${target}..."
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
