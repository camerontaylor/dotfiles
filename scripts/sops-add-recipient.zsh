#!/usr/bin/env zsh
#
# Append an age public key to .sops.yaml's recipient list and re-encrypt all
# .enc files to the new recipient set. Run this on a machine that already has
# decrypt access — sops updatekeys needs an existing private key to unwrap the
# data key before re-wrapping it for the new recipients.
#
# Usage: scripts/sops-add-recipient.zsh age1<pubkey>
#

setopt extended_glob err_exit

local SCRIPT_DIR=${0:A:h:h}
local sops_yaml=$SCRIPT_DIR/.sops.yaml

if [[ $# -ne 1 ]]; then
    print "Usage: $0 age1<pubkey>" >&2
    exit 1
fi

local new_key=$1

# Bech32 age public key: starts with "age1", 62 chars total.
if [[ ! $new_key =~ '^age1[0-9a-z]{58}$' ]]; then
    print "ERROR: '$new_key' is not a valid age public key (expected age1<58 lowercase alphanumerics>)." >&2
    exit 1
fi

if ! have sops; then
    print "ERROR: sops not found in PATH. Install via mise." >&2
    exit 1
fi

if [[ ! -f $sops_yaml ]]; then
    print "ERROR: $sops_yaml not found — cannot add a recipient to a non-existent rule." >&2
    exit 1
fi

# Collect existing recipients from .sops.yaml (any age1... token).
local -a existing_keys
existing_keys=(${(f)"$(grep -oE 'age1[0-9a-z]{58}' $sops_yaml | sort -u)"})

# Idempotency: bail early if already present.
if (( ${existing_keys[(I)$new_key]} )); then
    print "Key already registered in .sops.yaml — nothing to do."
    exit 0
fi

# Build merged, sorted, de-duped list.
local -a all_keys=(${existing_keys[@]} $new_key)
all_keys=(${(uo)all_keys})

# Rewrite only the age block; preserve everything else (path_regex, comments,
# additional creation_rules) by splicing around the existing `age:` field.
print "Updating .sops.yaml with ${#all_keys} recipients..."
local age_block="    age: >-"
local i
for (( i=1; i <= ${#all_keys}; i++ )); do
    if (( i < ${#all_keys} )); then
        age_block+=$'\n'"      ${all_keys[i]},"
    else
        age_block+=$'\n'"      ${all_keys[i]}"
    fi
done

# awk replacement: when we hit the `    age:` line, emit the new block and
# skip subsequent indented continuation lines until we see a non-continuation.
awk -v block="$age_block" '
    /^    age:/ { print block; in_age=1; next }
    in_age && /^      / { next }
    { in_age=0; print }
' $sops_yaml > ${sops_yaml}.tmp && mv ${sops_yaml}.tmp $sops_yaml

# Re-encrypt every .enc file to the new recipient set.
print "Re-encrypting .enc files..."
local -a enc_files
enc_files=($SCRIPT_DIR/**/*.enc~$SCRIPT_DIR/(plugins|tools|.git)/**/*(N))
local f
for f in $enc_files; do
    print "  ${f#$SCRIPT_DIR/}"
    sops updatekeys -y $f >/dev/null
done

print ""
print "Done. ${#enc_files} files re-encrypted to ${#all_keys} recipients."
print ""
print "Next steps:"
print "  git add .sops.yaml ${${enc_files[@]#$SCRIPT_DIR/}}"
print "  git commit -m 'sops: register $new_key'"
print "  git push"
