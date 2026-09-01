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

if ! have sops; then
    print "sops not found; run 'mise install' first" >&2
    exit 1
fi

if [[ ! -f $XDG_CONFIG_HOME/sops/age/keys.txt ]]; then
    print "age key not found at $XDG_CONFIG_HOME/sops/age/keys.txt" >&2
    exit 1
fi

# Encryption uses the recipient list defined in .sops.yaml (no --age / --config
# overrides) so multi-machine setups stay multi-recipient.

encrypted_matches_plaintext() {
    local plaintext=$1
    local enc_file=$2
    local tmp result

    [[ -f $enc_file ]] || return 1

    tmp=$(mktemp) || return 2
    if sops --decrypt "$enc_file" > "$tmp" 2>/dev/null; then
        if cmp -s "$plaintext" "$tmp"; then
            result=0
        else
            result=$?
        fi
    else
        result=2
    fi
    rm -f "$tmp"

    return $result
}

encrypt_if_changed() {
    local plaintext=$1
    local enc_file=$2
    local compare_status

    # Don't clobber a newer .enc with older plaintext. After a `git pull` the
    # tracked .enc can be ahead of this machine's plaintext (e.g. another box
    # rotated the secret); re-encrypting stale plaintext over it would silently
    # drop that change. Skip-only — it never *forces* a re-encrypt, so the
    # content check below still suppresses SOPS nonce churn. --force overrides.
    if [[ -f $enc_file && $force == false && $enc_file -nt $plaintext ]]; then
        print "Skipping ${plaintext}: encrypted ${enc_file} is newer (use --force to overwrite)"
        return 0
    fi

    if [[ -f $enc_file && $force == false ]]; then
        if encrypted_matches_plaintext "$plaintext" "$enc_file"; then
            print "Skipping ${plaintext}: encrypted ${enc_file} already matches plaintext"
            return 0
        else
            compare_status=$?
            if (( compare_status != 1 )); then
                print "Failed to decrypt ${enc_file}; use --force to overwrite" >&2
                return 1
            fi
        fi
    fi

    print "Encrypting ${plaintext} -> ${enc_file}..."
    if sops --encrypt --input-type binary --output-type binary --output "$enc_file" "$plaintext" 2>/dev/null; then
        if $git_add; then
            git add "$enc_file"
        fi
        print "  ...done"
    else
        print "  ...failed to encrypt $plaintext" >&2
        return 1
    fi
}

local plaintext enc_file
for plaintext in {zsh/env.d,zsh/rc.d,nvim/init}/9[0-9]_*(N); do
    [[ $plaintext == *.enc ]] && continue

    enc_file="${plaintext}.enc"
    encrypt_if_changed "$plaintext" "$enc_file"
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

    encrypt_if_changed "$plaintext" "$enc_file"
done

# Portkey gateway runtime state (provider API keys + local control-plane token).
# The systemd unit reads these directly via EnvironmentFile / a PORTKEY_LOCAL_API_KEY
# path, so encrypted siblings ship via this repo and restore-secrets.zsh writes them
# back to ~/.local/state/portkey with mode 0600.
local -a portkey_plaintexts portkey_enc_files
portkey_plaintexts=($HOME/.local/state/portkey/env $HOME/.local/state/portkey/local-api-key)
portkey_enc_files=(configs/ai/portkey/state/env.enc configs/ai/portkey/state/local-api-key.enc)
for (( i = 1; i <= ${#portkey_plaintexts}; i++ )); do
    plaintext=${portkey_plaintexts[i]}
    enc_file=${portkey_enc_files[i]}
    [[ -f $plaintext ]] || continue

    mkdir -p configs/ai/portkey/state

    encrypt_if_changed "$plaintext" "$enc_file"
done

# restic repository password for the Immich photo library backup.
# This one is load-bearing in an unusual way: the repository is client-side
# encrypted, so losing this password makes the backup unrecoverable — there is
# no reset path. It must survive the loss of the machine it protects, hence
# shipping it here alongside the password manager copy.
local -a restic_plaintexts restic_enc_files
restic_plaintexts=($HOME/repos/deploy/immich/.restic-password $HOME/repos/deploy/immich/.b2-env)
restic_enc_files=(configs/immich/restic-password.enc configs/immich/b2-env.enc)
for (( i = 1; i <= ${#restic_plaintexts}; i++ )); do
    plaintext=${restic_plaintexts[i]}
    enc_file=${restic_enc_files[i]}
    [[ -f $plaintext ]] || continue

    mkdir -p configs/immich

    encrypt_if_changed "$plaintext" "$enc_file"
done

# openclaw-mcp bridge environment (gateway URL + token, model routing).
# The .enc has been tracked since it was first encrypted by hand; wiring it
# through here means it now refreshes on save like every other secret instead of
# silently drifting from the plaintext.
local -a openclaw_plaintexts openclaw_enc_files
openclaw_plaintexts=($XDG_CONFIG_HOME/openclaw-mcp/env)
openclaw_enc_files=(configs/openclaw-mcp/env.enc)
for (( i = 1; i <= ${#openclaw_plaintexts}; i++ )); do
    plaintext=${openclaw_plaintexts[i]}
    enc_file=${openclaw_enc_files[i]}
    [[ -f $plaintext ]] || continue

    mkdir -p configs/openclaw-mcp

    encrypt_if_changed "$plaintext" "$enc_file"
done
