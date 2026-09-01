#!/usr/bin/env zsh
#
# Two-tier enforcement of configs/ai/codex/config.toml. Invoked from
# scripts/pre-commit via the --git-add flag; usable standalone for the
# working-tree pass.
#
# HARD-enforced (silent rewrite, working tree AND staged blob):
#   sandbox_mode    = "danger-full-access"
#   approval_policy = "never"
# These are safety/UX defaults that should never drift across commits.
#
# TRANSIENT (revert to HEAD unless SKIP_CODEX_ENFORCE=1 is set):
#   model
#   model_reasoning_effort
# These get tuned per-session for model experimentation. We don't want
# stray drift bundled into unrelated commits, so both the working tree and
# staged blob are reverted to HEAD's value before commit. Real bumps land via:
#
#   SKIP_CODEX_ENFORCE=1 git commit -m "feat(codex): bump model to gpt-5.6-sol"

setopt err_exit pipefail

# Opt-out for intentional model/effort updates.
if [[ -n ${SKIP_CODEX_ENFORCE:-} ]]; then
    exit 0
fi

git_add=false
config_file=

# Resolve the repo root from this script's real location: a hand-rolled
# symlink walk (the repo's canonical pattern, scripts/generate-commit-msg).
# zsh's ${0:A:h:h} has no bash spelling; cd -P yields the same physical path.
_self=$0
while [[ -L $_self ]]; do
    _self_dir=$(cd -P -- "$(dirname -- "$_self")" && pwd)
    _self=$(readlink "$_self")
    [[ $_self != /* ]] && _self=$_self_dir/$_self
done
SCRIPT_DIR=$(dirname -- "$(cd -P -- "$(dirname -- "$_self")" && pwd)")
# with systemd-homed the physical path is the storage location `/home/username.homedir` instead of mounted location `/home/username`
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
                printf '%s\n' "Usage: $0 [--git-add] [--config PATH]" >&2
                exit 1
            fi
            config_file=${~1}
            ;;
        *)
            printf '%s\n' "Usage: $0 [--git-add] [--config PATH]" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ ! -f $config_file ]]; then
    printf '%s\n' "Codex config not found: $config_file" >&2
    exit 1
fi

# Hardcoded hard-enforced lines (verbatim TOML).
desired_sandbox='sandbox_mode = "danger-full-access"'
desired_approval='approval_policy = "never"'

# Pull HEAD's model and effort lines for transient-revert baseline. Empty
# strings = "leave these keys alone" (e.g., file not in HEAD yet, or those
# keys missing from HEAD).
head_model=""
head_effort=""
relpath=${config_file#$SCRIPT_DIR/}
if [[ $relpath != /* ]] && have git \
    && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$SCRIPT_DIR" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1; then
    head_model=$(git -C "$SCRIPT_DIR" show "HEAD:$relpath" 2>/dev/null \
        | awk '/^[[:space:]]*model[[:space:]]*=/ {print; exit}')
    head_effort=$(git -C "$SCRIPT_DIR" show "HEAD:$relpath" 2>/dev/null \
        | awk '/^[[:space:]]*model_reasoning_effort[[:space:]]*=/ {print; exit}')
fi

# Normalize one buffer through awk. apply_transient="yes" enables
# model/effort revert against HEAD; "no" leaves them as-is. Either way,
# sandbox_mode and approval_policy are hard-rewritten and inserted if missing.
normalize_codex_config() {
    local input=$1 output=$2 apply_transient=$3

    local awk_model="" awk_effort=""
    if [[ $apply_transient == yes ]]; then
        awk_model=$head_model
        awk_effort=$head_effort
    fi

    awk \
        -v desired_sandbox="$desired_sandbox" \
        -v desired_approval="$desired_approval" \
        -v desired_model="$awk_model" \
        -v desired_effort="$awk_effort" '
        BEGIN {
            in_root = 1
        }

        function emit_missing() {
            if (!seen_sandbox) {
                print desired_sandbox
                seen_sandbox = 1
            }
            if (!seen_approval) {
                print desired_approval
                seen_approval = 1
            }
            # Deliberately do NOT insert model/effort if missing — those
            # are user-managed transient values; we only revert drift on
            # existing lines, never insist on presence.
        }

        {
            if (in_root && $0 ~ /^[[:space:]]*\[/) {
                emit_missing()
                in_root = 0
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

            if (in_root && $0 ~ /^[[:space:]]*model[[:space:]]*=/) {
                if (desired_model != "") {
                    print desired_model
                    next
                }
            }

            if (in_root && $0 ~ /^[[:space:]]*model_reasoning_effort[[:space:]]*=/) {
                if (desired_effort != "") {
                    print desired_effort
                    next
                }
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
    local target=$1 apply_transient=$2 tmp

    tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config.XXXXXX")
    normalize_codex_config "$target" "$tmp" "$apply_transient"

    if cmp -s "$target" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    cp "$tmp" "$target"
    rm -f "$tmp"
    return 0
}

# Working tree pass: hard-enforce sandbox/approval and revert model/effort
# drift so per-session Codex model experiments do not linger as repo churn.
if normalize_file "$config_file" yes; then
    printf '%s\n' "Enforced Codex defaults in ${relpath:-$config_file}"
fi

# Staged blob pass (--git-add mode): hard-enforce sandbox/approval AND
# revert model/effort drift back to HEAD's value, warning the user when the
# staged blob still needed cleanup after the working-tree pass.
if [[ $git_add == true ]] && have git; then
    if [[ $relpath != /* ]] \
        && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        && git -C "$SCRIPT_DIR" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1; then
        index_tmp= normalized_tmp= mode= blob=

        index_tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config-index.XXXXXX")
        normalized_tmp=$(mktemp "${TMPDIR:-/tmp}/codex-config-index-normalized.XXXXXX")

        if git -C "$SCRIPT_DIR" show ":$relpath" > "$index_tmp" 2>/dev/null; then
            normalize_codex_config "$index_tmp" "$normalized_tmp" yes
            if ! cmp -s "$index_tmp" "$normalized_tmp"; then
                printf '%s\n' "Codex config: reverting drift in staged blob:"
                # diff returns 1 when files differ — which is exactly when
                # this branch runs. Without `|| true` the pipefail+err_exit
                # combo aborts the script before update-index can run.
                { diff "$index_tmp" "$normalized_tmp" 2>/dev/null || true; } \
                    | head -20 \
                    | sed 's/^/  /'

                mode=$(git -C "$SCRIPT_DIR" ls-files -s -- "$relpath" | awk 'NR == 1 {print $1}')
                blob=$(git -C "$SCRIPT_DIR" hash-object -w "$normalized_tmp")
                git -C "$SCRIPT_DIR" update-index --cacheinfo "$mode" "$blob" "$relpath"
                printf '%s\n' "  ...staged blob normalized."
                printf '%s\n' "  ...to commit your model/effort change,"
                printf '%s\n' "     re-run with: SKIP_CODEX_ENFORCE=1 git commit ..."
            fi
        fi

        rm -f "$index_tmp" "$normalized_tmp"
    fi
fi
