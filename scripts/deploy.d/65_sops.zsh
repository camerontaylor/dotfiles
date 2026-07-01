# Age-key bootstrap + sops decrypt of SSH/secret artifacts. Reads .sops.yaml
# from repo root as source of truth for registered recipients.

local age_key_dir=$XDG_CONFIG_HOME/sops/age
local age_public_key
if [[ ! -f $age_key_dir/keys.txt ]]; then
    if (( ${+commands[age-keygen]} )); then
        print "Generating age key for secrets..."
        zf_mkdir -p $age_key_dir
        age-keygen -o $age_key_dir/keys.txt 2>/dev/null
        chmod 600 $age_key_dir/keys.txt
        print "  ...done"
        print "  IMPORTANT: Back up $age_key_dir/keys.txt to your password manager!"
    else
        print ""
        print "WARNING: age key not found and age-keygen not available."
        print "  Encrypted secrets (zsh/env.d/90_secrets.zsh etc.) cannot be decrypted."
        print ""
        print "  To restore secrets on this machine, either:"
        print "    1. Copy your existing keys.txt from your password manager to:"
        print "         $age_key_dir/keys.txt"
        print "    2. Or install age (mise install) and re-run deploy.zsh to generate a new key."
        print "       (A new key cannot decrypt existing .enc files — you must re-encrypt them.)"
        print ""
    fi
fi

# Verify this machine's age public key is registered in the committed .sops.yaml.
if [[ -f $age_key_dir/keys.txt ]] && (( ${+commands[age-keygen]} )); then
    age_public_key=$(age-keygen -y $age_key_dir/keys.txt 2>/dev/null)
    if [[ -n $age_public_key ]]; then
        if [[ ! -f $SCRIPT_DIR/.sops.yaml ]]; then
            print ""
            print "WARNING: .sops.yaml not found in repo root."
            print "  This machine's age public key:"
            print "    $age_public_key"
            print "  Add it to .sops.yaml on a registered machine and re-encrypt secrets."
            print ""
        elif ! grep -Fq "$age_public_key" $SCRIPT_DIR/.sops.yaml; then
            print ""
            print "WARNING: this machine's age key is not registered for sops decryption."
            print "  Encrypted secrets (zsh/env.d/9*.zsh.enc, ssh/*.enc) cannot be read."
            print ""
            print "  This machine's public key:"
            print "    $age_public_key"
            print ""
            print "  To register, on an already-registered machine run:"
            print "    scripts/sops-add-recipient.zsh $age_public_key"
            print "  then commit and push. Pull here to pick up the re-encrypted secrets."
            print ""
        fi
    fi
fi

# Decrypt encrypted dotfiles into their ignored plaintext locations.
if (( ${+commands[sops]} )) && [[ -f $age_key_dir/keys.txt ]]; then
    print "Restoring ssh files..."
    local _ssh_enc _ssh_target _ssh_tmp
    for _ssh_enc in $SCRIPT_DIR/ssh/*.enc(N); do
        _ssh_target=$SCRIPT_DIR/ssh/${${_ssh_enc:t}%.enc}
        # Don't clobber a locally-edited plaintext that is newer than the
        # tracked .enc — that silently dropped hand-edited ssh/config before.
        # Skip the decrypt but still (re)assert the ~/.ssh symlink. Override
        # with `deploy.zsh --force` (DEPLOY_FORCE=1) to force a full restore.
        if (( ! ${DEPLOY_FORCE:-0} )) && [[ -f $_ssh_target && $_ssh_target -nt $_ssh_enc ]]; then
            print "  Skipping ${_ssh_enc:t}: ${_ssh_target:t} is newer (deploy.zsh --force to overwrite)"
            zf_ln -sfn $_ssh_target $HOME/.ssh/${_ssh_target:t}
            continue
        fi
        _ssh_tmp=$(mktemp)
        if sops --decrypt $_ssh_enc > $_ssh_tmp 2>/dev/null; then
            if [[ $_ssh_target == *.pub ]]; then
                chmod 644 $_ssh_tmp
            else
                chmod 600 $_ssh_tmp
            fi
            mv $_ssh_tmp $_ssh_target
            zf_ln -sfn $_ssh_target $HOME/.ssh/${_ssh_target:t}
        else
            rm -f $_ssh_tmp
            print "  WARNING: failed to decrypt ${_ssh_enc:t}"
        fi
    done
    print "  ...done"
fi

# Reload systemd to pick up any user units linked above.
if (( ${+commands[systemctl]} )); then
    systemctl --user daemon-reload 2>/dev/null
fi
