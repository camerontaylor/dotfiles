#!/usr/bin/env zsh

setopt extended_glob err_exit

force=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            force=true
            ;;
        *)
            printf '%s\n' "Usage: $0 [--force]" >&2
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

if ! have sops; then
    printf '%s\n' "sops not found; run 'mise install' first" >&2
    exit 1
fi

if [[ ! -f $XDG_CONFIG_HOME/sops/age/keys.txt ]]; then
    printf '%s\n' "age key not found at $XDG_CONFIG_HOME/sops/age/keys.txt" >&2
    printf '%s\n' "" >&2
    printf '%s\n' "  To decrypt secrets, place your age private key at:" >&2
    printf '%s\n' "    $XDG_CONFIG_HOME/sops/age/keys.txt" >&2
    printf '%s\n' "" >&2
    printf '%s\n' "  If you have a backup, copy it there and run this script again." >&2
    printf '%s\n' "  If setting up fresh, run deploy.zsh first to generate a new key." >&2
    printf '%s\n' "  (A new key cannot decrypt existing .enc files — you must re-encrypt them.)" >&2
    exit 1
fi

# Decrypt targets. The old `{dir1,dir2,dir3}/9[0-9]_*.enc(N)` brace-glob was
# zsh-only; find walks the same three directories (per-dir sort, dir order
# preserved — identical iteration order to the glob concatenation) and stays
# silent on zero matches in both shells.
enc_file= target= temp_file=
enc_files=()
while IFS= read -r enc_file; do
    enc_files+=("$enc_file")
done < <(
    for _enc_dir in zsh/env.d zsh/rc.d nvim/init; do
        find $_enc_dir -maxdepth 1 -name '9[0-9]_*.enc' 2>/dev/null | sort
    done
)
for enc_file in "${enc_files[@]}"; do
    target=${enc_file%.enc}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        printf '%s\n' "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    printf '%s\n' "Decrypting ${enc_file}..."
    temp_file=$(mktemp)
    if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
        chmod 600 $temp_file
        mv $temp_file $target
        printf '%s\n' "  ...done"
    else
        rm -f $temp_file
        printf '%s\n' "  ...failed to decrypt $enc_file (missing or wrong age key?)"
    fi
done

# SSH config and managed keys
enc_files=()
while IFS= read -r enc_file; do
    enc_files+=("$enc_file")
done < <(find ssh -maxdepth 1 -name '*.enc' 2>/dev/null | sort)
for enc_file in "${enc_files[@]}"; do
    _enc_base=${enc_file##*/}
    target=ssh/${_enc_base%.enc}
    mkdir -p ssh
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        printf '%s\n' "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
    else
        printf '%s\n' "Decrypting ${enc_file}..."
        temp_file=$(mktemp)
        if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
            if [[ $target == *.pub ]]; then
                chmod 644 $temp_file
            else
                chmod 600 $temp_file
            fi
            mv $temp_file $target
            printf '%s\n' "  ...done"
        else
            rm -f $temp_file
            printf '%s\n' "  ...failed to decrypt $enc_file (missing or wrong age key?)"
        fi
    fi
done

# Portkey gateway runtime state. Targets live outside this repo at
# ~/.local/state/portkey/ — the systemd unit's EnvironmentFile and the
# PORTKEY_LOCAL_API_KEY path both reference them by absolute path.
portkey_state_dir=$HOME/.local/state/portkey
portkey_enc_files=() portkey_targets=()
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
        printf '%s\n' "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    printf '%s\n' "Decrypting ${enc_file} -> ${target}..."
    temp_file=$(mktemp)
    if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
        chmod 600 $temp_file
        mv $temp_file $target
        printf '%s\n' "  ...done"
    else
        rm -f $temp_file
        printf '%s\n' "  ...failed to decrypt $enc_file (missing or wrong age key?)"
    fi
done

# restic repository password for the Immich backup. Target lives outside this
# repo at ~/repos/deploy/immich/ because the backup systemd unit references it
# by absolute path via RESTIC_PASSWORD_FILE.
restic_dir=$HOME/repos/deploy/immich
restic_enc_files=() restic_targets=()
restic_enc_files=(configs/immich/restic-password.enc configs/immich/b2-env.enc)
restic_targets=($restic_dir/.restic-password $restic_dir/.b2-env)
for (( i = 1; i <= ${#restic_enc_files}; i++ )); do
    enc_file=${restic_enc_files[i]}
    target=${restic_targets[i]}
    [[ -f $enc_file ]] || continue
    [[ -d ${target:h} ]] || install -m 700 -d ${target:h}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        printf '%s\n' "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    printf '%s\n' "Decrypting ${enc_file} -> ${target}..."
    temp_file=$(mktemp)
    if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
        chmod 600 $temp_file
        mv $temp_file $target
        printf '%s\n' "  ...done"
    else
        rm -f $temp_file
        printf '%s\n' "  ...failed to decrypt $enc_file (missing or wrong age key?)"
    fi
done

# openclaw-mcp bridge environment. Target lives outside this repo at
# ~/.config/openclaw-mcp/env, which the bridge reads directly.
#
# ceres ONLY. This is server-side config for a bridge that runs on exactly one
# box (see the matching gate in scripts/deploy.d/20_symlinks.zsh): a gateway
# token and an MCP OAuth client secret. Restoring it on saturn/neptune/quaoar
# would spread live credentials to machines that have no use for them.
openclaw_enc_files=() openclaw_targets=()
if [[ $(hostname -s 2>/dev/null) == ceres ]]; then
    openclaw_enc_files=(configs/openclaw-mcp/env.enc)
    openclaw_targets=($HOME/.config/openclaw-mcp/env)
else
    openclaw_enc_files=()
    openclaw_targets=()
fi
for (( i = 1; i <= ${#openclaw_enc_files}; i++ )); do
    enc_file=${openclaw_enc_files[i]}
    target=${openclaw_targets[i]}
    [[ -f $enc_file ]] || continue
    [[ -d ${target:h} ]] || install -m 700 -d ${target:h}
    if ! $force && [[ -f $target && $target -nt $enc_file ]]; then
        printf '%s\n' "Skipping ${enc_file}: plaintext ${target} is newer (use --force to overwrite)"
        continue
    fi
    printf '%s\n' "Decrypting ${enc_file} -> ${target}..."
    temp_file=$(mktemp)
    if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
        chmod 600 $temp_file
        mv $temp_file $target
        printf '%s\n' "  ...done"
    else
        rm -f $temp_file
        printf '%s\n' "  ...failed to decrypt $enc_file (missing or wrong age key?)"
    fi
done
