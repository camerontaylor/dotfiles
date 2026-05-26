#!/usr/bin/env zsh

setopt err_exit pipefail

local git_add=false
local config_file

SCRIPT_DIR=${0:A:h:h}
# with systemd-homed `a`/`A` expands to storage location `/home/username.homedir` instead of mounted location `/home/username`
# therefore massage SCRIPT_DIR to expected home location by removing `.homedir` from it
if [[ $SCRIPT_DIR == $HOME.homedir* ]]; then
    SCRIPT_DIR=${SCRIPT_DIR/.homedir/}
fi

config_file=$SCRIPT_DIR/configs/ai/codex/config.toml

while (( $# )); do
    case $1 in
        --git-add)
            git_add=true
            ;;
        --config)
            shift
            if (( ! $# )); then
                print "Usage: $0 [--git-add] [--config PATH]" >&2
                exit 1
            fi
            config_file=${~1}
            ;;
        *)
            print "Usage: $0 [--git-add] [--config PATH]" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ ! -f $config_file ]]; then
    print "Codex config not found: $config_file" >&2
    exit 1
fi

normalize_codex_config() {
    local input=$1
    local output=$2

    awk \
        -v desired_model='model = "gpt-5.4-mini"' \
        -v desired_sandbox='sandbox_mode = "danger-full-access"' \
        -v desired_approval='approval_policy = "never"' \
        -v desired_effort='model_reasoning_effort = "high"' '
        BEGIN {
            in_root = 1
        }

        function emit_missing() {
            if (!seen_model) {
                print desired_model
                seen_model = 1
            }
            if (!seen_sandbox) {
                print desired_sandbox
                seen_sandbox = 1
            }
            if (!seen_approval) {
                print desired_approval
                seen_approval = 1
            }
            if (!seen_effort) {
                print desired_effort
                seen_effort = 1
            }
        }

        {
            if (in_root && $0 ~ /^[[:space:]]*\[/) {
                emit_missing()
                in_root = 0
            }

            if (in_root && $0 ~ /^[[:space:]]*model[[:space:]]*=/) {
                if (!seen_model) {
                    print desired_model
                }
                seen_model = 1
                next
            }

            if (in_root && $0 ~ /^[[:space:]]*sandbox_mode[[:space:]]*=/) {
                if (!seen_sandbox) {
                    print desired_sandbox
                }
                seen_sandbox = 1
                next
            }

            if (in_root && $0 ~ /^[[:space:]]*approval_policy[[:space:]]*=/) {
                if (!seen_approval) {
                    print desired_approval
                }
                seen_approval = 1
                next
            }

            if (in_root && $0 ~ /^[[:space:]]*model_reasoning_effort[[:space:]]*=/) {
                if (!seen_effort) {
                    print desired_effort
                }
                seen_effort = 1
                next
            }

            print
        }

        END {
            if (in_root) {
                emit_missing()
            }
        }
    ' "$input" > "$output"
}

normalize_file() {
    local target=$1
    local tmp

    tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config.XXXXXX")
    normalize_codex_config "$target" "$tmp"

    if cmp -s "$target" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    cp "$tmp" "$target"
    rm -f "$tmp"
    return 0
}

if normalize_file "$config_file"; then
    print "Enforced Codex defaults in ${config_file#$SCRIPT_DIR/}"
fi

if [[ $git_add == true ]] && (( ${+commands[git]} )); then
    local relpath=${config_file#$SCRIPT_DIR/}

    if [[ $relpath != /* ]] &&
        git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        git -C "$SCRIPT_DIR" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1; then
        local index_tmp normalized_tmp mode blob

        index_tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config-index.XXXXXX")
        normalized_tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config-index-normalized.XXXXXX")

        if git -C "$SCRIPT_DIR" show ":$relpath" > "$index_tmp" 2>/dev/null; then
            normalize_codex_config "$index_tmp" "$normalized_tmp"
            if ! cmp -s "$index_tmp" "$normalized_tmp"; then
                mode=$(git -C "$SCRIPT_DIR" ls-files -s -- "$relpath" | awk 'NR == 1 {print $1}')
                blob=$(git -C "$SCRIPT_DIR" hash-object -w "$normalized_tmp")
                git -C "$SCRIPT_DIR" update-index --cacheinfo "$mode" "$blob" "$relpath"
                print "Enforced Codex defaults in staged $relpath"
            fi
        fi

        rm -f "$index_tmp" "$normalized_tmp"
    fi
fi
